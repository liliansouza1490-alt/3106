import SwiftUI

private enum ExternalPanelCategory: String, CaseIterable, Identifiable {
    case cache = "Cache"
    case avatar = "Avatar"
    case skin = "Skin"
    case external = "External"
    case misc = "Misc"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .cache: return "internaldrive.fill"
        case .avatar: return "person.crop.circle.fill"
        case .skin: return "tshirt.fill"
        case .external: return "square.stack.3d.up.fill"
        case .misc: return "ellipsis.circle.fill"
        }
    }

    var portugueseDescription: String {
        switch self {
        case .cache: return "Área de cache"
        case .avatar: return "Área de avatar"
        case .skin: return "Área de skins"
        case .external: return "Pacotes e projetos externos"
        case .misc: return "Outras opções"
        }
    }
}

struct ExternalIOSPanelView: View {
    @ObservedObject var authSession: ExternalSystemAuthSession
    @Environment(\.appLanguage) private var language
    @Environment(\.externalGameSelection) private var selectedGame
    @State private var selectedCategory: ExternalPanelCategory = .external
    @State private var isDrawerOpen = false
    @State private var showSettings = false

    private let background = Color(red: 0.035, green: 0.039, blue: 0.052)
    private let surface = Color(red: 0.075, green: 0.082, blue: 0.105)
    private let accent = Color(red: 0.63, green: 0.43, blue: 0.98)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Color.clear.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    categoryContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if isDrawerOpen {
                    Color.black.opacity(0.62)
                        .ignoresSafeArea()
                        .onTapGesture { isDrawerOpen = false }
                        .transition(.opacity)
                        .accessibilityLabel("Fechar menu")

                    drawer(width: min(geometry.size.width * 0.82, 310))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .leading))
                        .zIndex(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: isDrawerOpen)
        }
        .background(Color.clear.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                isDrawerOpen = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir menu de categorias")

            Spacer(minLength: 8)

            VStack(spacing: 3) {
                Text("EXTERNAL IOS")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(1.45)
                    .foregroundStyle(.white)
                Text(selectedGame.title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.15)
                    .foregroundStyle(accent)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button {
                authSession.requestNewKey()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Trocar key")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background(surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(authSession.isChecking)
            .accessibilityLabel("Trocar key")
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 12)
        .background(background.opacity(0.98))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var categoryContent: some View {
        if selectedCategory == .external {
            PatchProjectsView(
                onOpenSettings: { showSettings = true },
                onOpenLogs: {}
            )
            .environment(\.appLanguage, language)
        } else {
            emptyCategory(selectedCategory)
        }
    }

    private func emptyCategory(_ category: ExternalPanelCategory) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 72, height: 72)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(accent.opacity(0.28), lineWidth: 1)
                    }

                VStack(spacing: 7) {
                    Text(category.rawValue.uppercased())
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.white)
                    Text(category.portugueseDescription)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                    Text(category == .misc
                         ? "Ajustes gerais do app."
                         : "Nenhuma opção configurada nesta categoria.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                    if category == .misc {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Configurações", systemImage: "gearshape.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(accent.opacity(0.20), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(accent.opacity(0.32), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 54)
            .padding(.horizontal, 22)
            .background(surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.075), lineWidth: 1)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    private func drawer(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ABAS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Color.white.opacity(0.52))
                    Text("EXTERNAL IOS")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                }

                Spacer()

                Button {
                    isDrawerOpen = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fechar menu")
            }
            .padding(.horizontal, 19)
            .padding(.top, 60)
            .padding(.bottom, 21)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
                .padding(.horizontal, 18)
                .padding(.bottom, 16)

            VStack(spacing: 7) {
                ForEach(ExternalPanelCategory.allCases) { category in
                    let isSelected = category == selectedCategory
                    Button {
                        selectedCategory = category
                        isDrawerOpen = false
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: category.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(isSelected ? accent : Color.white.opacity(0.56))
                                .frame(width: 23)
                            Text(category.rawValue)
                                .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? .white : Color.white.opacity(0.72))
                            Spacer()
                            if isSelected {
                                Circle()
                                    .fill(accent)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(
                            isSelected ? accent.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(isSelected ? accent.opacity(0.35) : Color.clear, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            Text(selectedGame.title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(accent)
                .padding(.horizontal, 20)
                .padding(.bottom, 38)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.065, green: 0.073, blue: 0.092))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
        .ignoresSafeArea()
    }
}
