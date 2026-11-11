import Foundation
import Security
import SwiftUI

private struct ProxyKeyResponseEnvelope: Decodable {
    let result: ProxyKeyResponseResult
}

private struct ProxyKeyResponseResult: Decodable {
    let data: ProxyKeyResponseData
}

private struct ProxyKeyResponseData: Decodable {
    let json: ProxyKeyValidation
}

private struct ProxyKeyValidation: Decodable {
    let success: Bool?
    let valid: Bool?
    let active: Bool?
    let status: String?
    let errorCode: String?
    let message: String?
    let reason: String?
    let expiresAt: String?
}

@MainActor
final class ExternalSystemAuthSession: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isChecking = false
    @Published private(set) var expiresAt: Date?
    @Published var errorMessage: String?

    private static let endpoint = URL(string: "https://proxysystem.org/api/trpc/proxyKeys.publicCheckKey")!
    private static let keychainService = "com.qingtang.3106.external-system"
    private static let keychainAccount = "access-key"
    private static let deviceService = "com.qingtang.3106.device-binding"
    private static let deviceAccount = "installation-id"
    private static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    private var storedKey: String?
    private var didPassCalculatorGate = false
    private var monitorTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?

    init() {
        storedKey = Self.readKeychain(service: Self.keychainService, account: Self.keychainAccount)
    }

    deinit {
        monitorTask?.cancel()
        expiryTask?.cancel()
    }

    func passCalculatorGate() {
        guard !didPassCalculatorGate else { return }
        didPassCalculatorGate = true

        if let storedKey, !storedKey.isEmpty {
            Task { await validate(storedKey, saveOnSuccess: false) }
        }

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshStoredSession()
            }
        }
    }

    func submit(_ rawKey: String) {
        guard didPassCalculatorGate else { return }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = "Digite sua key para continuar."
            return
        }
        errorMessage = nil
        Task { await validate(key, saveOnSuccess: true) }
    }

    func refreshStoredSession() async {
        guard didPassCalculatorGate, !isChecking,
              let storedKey, !storedKey.isEmpty else { return }

        if let expiresAt, Date() >= expiresAt {
            invalidate(message: "Sua key expirou. Digite uma nova para continuar.")
            return
        }
        await validate(storedKey, saveOnSuccess: false)
    }

    private func validate(_ key: String, saveOnSuccess: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let deviceID = try Self.deviceIdentifier()
            var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
            let input: [String: Any] = ["json": ["key": key, "deviceId": deviceID]]
            let inputData = try JSONSerialization.data(withJSONObject: input)
            let inputString = String(decoding: inputData, as: UTF8.self)
            components.queryItems = [URLQueryItem(name: "input", value: inputString)]
            guard let url = components.url else { throw URLError(.badURL) }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

            let (data, response) = try await Self.urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let envelope = try JSONDecoder().decode(ProxyKeyResponseEnvelope.self, from: data)
            let result = envelope.result.data.json
            let accepted = result.success == true
                && result.active == true
                && result.status?.lowercased() == "active"

            guard accepted else {
                let message: String
                if result.status?.lowercased() == "device_mismatch"
                    || result.errorCode?.uppercased() == "DEVICE_MISMATCH" {
                    message = result.message ?? "Esta key já está vinculada a outro aparelho."
                } else {
                    message = result.message ?? result.reason ?? "Key inválida ou expirada."
                }
                invalidate(message: message)
                return
            }

            let parsedExpiry = result.expiresAt.flatMap(Self.parseDate)
            if let parsedExpiry, parsedExpiry <= Date() {
                invalidate(message: "Sua key expirou. Digite uma nova para continuar.")
                return
            }

            storedKey = key
            if saveOnSuccess {
                Self.writeKeychain(key, service: Self.keychainService, account: Self.keychainAccount)
            }
            expiresAt = parsedExpiry
            errorMessage = nil
            isAuthenticated = true
            scheduleExpiryCheck()
        } catch {
            if let expiresAt, Date() >= expiresAt {
                invalidate(message: "Sua key expirou. Digite uma nova para continuar.")
            } else if !isAuthenticated {
                errorMessage = "Não foi possível validar a key. Confira sua conexão e tente novamente."
            }
        }
    }

    func requestNewKey() {
        guard !isChecking else { return }
        expiryTask?.cancel()
        expiryTask = nil
        storedKey = nil
        expiresAt = nil
        errorMessage = nil
        isAuthenticated = false
        Self.deleteKeychain(service: Self.keychainService, account: Self.keychainAccount)
    }

    private func invalidate(message: String) {
        expiryTask?.cancel()
        expiryTask = nil
        storedKey = nil
        expiresAt = nil
        isAuthenticated = false
        errorMessage = message
        Self.deleteKeychain(service: Self.keychainService, account: Self.keychainAccount)
    }

    private func scheduleExpiryCheck() {
        expiryTask?.cancel()
        expiryTask = nil
        guard let expiry = expiresAt else { return }

        let seconds = max(0, expiry.timeIntervalSinceNow)
        let delay = UInt64(min(seconds * 1_000_000_000, Double(UInt64.max)))
        expiryTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled, let self else { return }
            guard let currentExpiry = self.expiresAt, Date() >= currentExpiry else { return }
            self.invalidate(message: "Sua key expirou. Digite uma nova para continuar.")
        }
    }

    private static func deviceIdentifier() throws -> String {
        if let saved = readKeychain(service: deviceService, account: deviceAccount), !saved.isEmpty {
            return saved
        }
        let created = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard writeKeychain(created, service: deviceService, account: deviceAccount) else {
            throw URLError(.cannotCreateFile)
        }
        return created
    }

    private static func readKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func writeKeychain(_ value: String, service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteKeychain(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

struct ExternalSystemLoginView: View {
    @ObservedObject var session: ExternalSystemAuthSession
    @State private var key = ""
    @State private var isKeyVisible = false
    @FocusState private var keyFieldFocused: Bool

    private let panel = Color(red: 0.13, green: 0.14, blue: 0.16)

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 52)

                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                        Text("EXTERNAL SYSTEM")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .tracking(1.8)
                            .foregroundStyle(.white)
                    }
                    .padding(.bottom, 44)

                    Text("Acesso autorizado")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Insira sua key para continuar.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .padding(.top, 8)
                        .padding(.bottom, 28)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("CHAVE DE ACESSO")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.15)
                            .foregroundStyle(Color.white.opacity(0.64))

                        HStack(spacing: 10) {
                            Group {
                                if isKeyVisible {
                                    TextField("Cole sua key", text: $key)
                                } else {
                                    SecureField("Cole sua key", text: $key)
                                }
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($keyFieldFocused)
                            .onSubmit(submit)

                            Button {
                                isKeyVisible.toggle()
                                keyFieldFocused = true
                            } label: {
                                Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.58))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isKeyVisible ? "Ocultar key" : "Mostrar key")
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 54)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(Color.white.opacity(0.09), lineWidth: 1)
                        }

                        if let error = session.errorMessage {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 13))
                                Text(error)
                                    .font(.system(size: 12, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(Color(red: 1, green: 0.47, blue: 0.43))
                            .padding(.top, 2)
                        }

                        Button(action: submit) {
                            HStack(spacing: 9) {
                                if session.isChecking {
                                    ProgressView().tint(Color.black)
                                }
                                Text(session.isChecking ? "Validando key…" : "Validar chave")
                                    .font(.system(size: 15, weight: .bold))
                                if !session.isChecking {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 13, weight: .bold))
                                }
                            }
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(.plain)
                        .disabled(trimmedKey.isEmpty || session.isChecking)
                        .opacity(trimmedKey.isEmpty || session.isChecking ? 0.66 : 1)
                        .padding(.top, 6)
                    }
                    .padding(18)
                    .background(panel, in: RoundedRectangle(cornerRadius: 18))

                    HStack(spacing: 7) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("A key é validada pelo servidor e protegida neste aparelho.")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.42))
                    .padding(.top, 18)

                    Spacer(minLength: 48)
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        keyFieldFocused = false
        session.submit(key)
    }
}
