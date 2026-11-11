import SwiftUI
import UIKit

@main
struct ThreeOneOSSixApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var repositoryStore = PackageRepositoryStore()
    @StateObject private var externalAuthSession = ExternalSystemAuthSession()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var showCalculatorEntry = true
    @State private var hasInitializedAuthorizedApp = false
    @State private var selectedGame: ExternalGame?
    @State private var showAttribution = false
    @State private var updateOffer: AppUpdateChecker.Offer?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        setupLogCapture()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        log("app: 3106 \(appVersion) (\(appBuild)) launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
        SandboxAccess.prepare()
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    private func initializeAuthorizedAppIfNeeded() {
        guard !showCalculatorEntry,
              externalAuthSession.isAuthenticated,
              selectedGame != nil,
              !hasInitializedAuthorizedApp else { return }
        hasInitializedAuthorizedApp = true
        appState.detectSupport()
        checkForUpdate()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !showCalculatorEntry {
                    Color(red: 0.035, green: 0.039, blue: 0.052)
                        .ignoresSafeArea()
                    ParticleConstellationView()
                }

                if showCalculatorEntry {
                    CalculadoraIPhoneView {
                        OnboardingStore.markCompleted()
                        externalAuthSession.passCalculatorGate()
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                            showCalculatorEntry = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(2)
                } else if !externalAuthSession.isAuthenticated {
                    ExternalSystemLoginView(session: externalAuthSession)
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .transition(.opacity)
                } else if let selectedGame {
                    ExternalIOSPanelView(authSession: externalAuthSession)
                        .environmentObject(appState)
                        .environmentObject(patchDraftCoordinator)
                        .environmentObject(fileOperationCoordinator)
                        .environmentObject(patchStore)
                        .environmentObject(repositoryStore)
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .environment(\.externalGameSelection, selectedGame)
                        .transition(.opacity)
                } else {
                    GameSelectionView { game in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                            selectedGame = game
                        }
                    }
                        .environment(\.appLanguage, language)
                        .environment(\.locale, language.locale)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showCalculatorEntry)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: externalAuthSession.isAuthenticated)
            .displayIdentityAttribution(
                isPresented: $showAttribution,
                enabled: !showCalculatorEntry && externalAuthSession.isAuthenticated && selectedGame != nil
            )
            .sheet(isPresented: $showAttribution) {
                DisplayAttributionSheet()
            }
            .alert(item: $updateOffer) { offer in
                Alert(
                    title: Text(language.text("update.title")),
                    message: Text(language.text("update.message", offer.version)),
                    primaryButton: .default(Text(language.text("update.agree"))) {
                        UIApplication.shared.open(offer.url)
                    },
                    secondaryButton: .cancel(Text(language.text("update.dismiss"))) {
                        AppUpdateChecker.dismiss(version: offer.version)
                    }
                )
            }
            .onAppear {
                initializeAuthorizedAppIfNeeded()
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, !showCalculatorEntry else { return }
                Task { await externalAuthSession.refreshStoredSession() }
                if externalAuthSession.isAuthenticated, selectedGame != nil { appState.detectSupport() }
            }
            .onChange(of: showCalculatorEntry) { isShowing in
                if !isShowing { initializeAuthorizedAppIfNeeded() }
            }
            .onChange(of: externalAuthSession.isAuthenticated) { isAuthenticated in
                if isAuthenticated {
                    initializeAuthorizedAppIfNeeded()
                } else {
                    selectedGame = nil
                    hasInitializedAuthorizedApp = false
                }
            }
            .onChange(of: selectedGame) { game in
                if game != nil { initializeAuthorizedAppIfNeeded() }
            }
            .onOpenURL { url in
                patchDraftCoordinator.presentImport(url)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false

    private var autoRunAttempted = false

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild
        )
    }

    var isSupported: Bool { unsupportedMessage == nil }

    func detectSupport() {
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
        guard applicable else { return }

        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }

    private func maybeAutoRunKernelExploit() {
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed,
              !autoRunAttempted else { return }
        autoRunAttempted = true
        log("app: starting kernel exploit automatically")
        runKernelExploitIfNeeded()
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        // iOS < 26: kernel R/W success persists (no sandbox probe)
        // iOS >= 26: verify full sandbox escape is still active
        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: SandboxAccess.backend.displayName)
                    log("app: existing \(SandboxAccess.backend.displayName) access is still active")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded() {
        refreshKernelExploitStatus()
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        let backend = SandboxAccess.backend
        log("app: running \(backend.displayName) access setup on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if ok {
                    self.exploitStatus = .success(method: backend.displayName)
                    if backend == .kernel {
                        log("app: kernel access active")
                    } else {
                        log("app: \(backend.displayName) access active")
                    }
                } else {
                    self.exploitStatus = .failed(method: backend.displayName, code: -1)
                    if backend == .worseQuery && !SandboxAccess.hasAppGroup {
                        log("app: worse_query needs an App Group; re-sign with a tool that provides one")
                    } else {
                        log("app: \(backend.displayName) setup failed — relaunch the app before retrying")
                    }
                }
            }
        }
    }
}
