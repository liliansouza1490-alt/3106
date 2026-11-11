import SwiftUI

struct ExternalGame: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String

    static let normal = ExternalGame(
        id: "ff_normal",
        title: "FF NORMAL",
        subtitle: "Free Fire"
    )
    static let max = ExternalGame(
        id: "ff_max",
        title: "FF MAX",
        subtitle: "Free Fire MAX"
    )

    static let all: [ExternalGame] = [.normal, .max]
}

private struct ExternalGameSelectionEnvironmentKey: EnvironmentKey {
    static let defaultValue = ExternalGame.normal
}

extension EnvironmentValues {
    var externalGameSelection: ExternalGame {
        get { self[ExternalGameSelectionEnvironmentKey.self] }
        set { self[ExternalGameSelectionEnvironmentKey.self] = newValue }
    }
}

struct GameSelectionView: View {
    let onContinue: (ExternalGame) -> Void

    @State private var selectedGame: ExternalGame?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let background = Color(red: 0.035, green: 0.043, blue: 0.055)
    private let panel = Color(red: 0.075, green: 0.085, blue: 0.105)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

                    Text("EXTERNAL SYSTEM")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(1.55)
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 34)

                Text("Selecione o jogo")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Escolha a versão que você quer acessar.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                VStack(spacing: 12) {
                    ForEach(ExternalGame.all) { game in
                        gameCard(game)
                    }
                }

                Button {
                    guard let selectedGame else { return }
                    onContinue(selectedGame)
                } label: {
                    HStack(spacing: 9) {
                        Text("Selecionar")
                            .font(.system(size: 15, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(selectedGame == nil)
                .opacity(selectedGame == nil ? 0.5 : 1)
                .padding(.top, 22)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .preferredColorScheme(.dark)
    }

    private func gameCard(_ game: ExternalGame) -> some View {
        let isSelected = selectedGame == game

        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78)) {
                selectedGame = game
            }
        } label: {
            HStack(spacing: 15) {
                Image("FreeFireGameIcon")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.30), radius: 9, y: 5)

                VStack(alignment: .leading, spacing: 5) {
                    Text(game.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                    Text(game.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.56))
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(isSelected ? AppTheme.accent : Color.white.opacity(0.25))
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppTheme.accent.opacity(0.10) : panel, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.85) : Color.white.opacity(0.075), lineWidth: isSelected ? 1.5 : 1)
            }
            .scaleEffect(isSelected ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.title), \(game.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
