import SwiftUI

struct WinnerCelebrationOverlay: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String
    let lines: [String]
    let useGifs: Bool
    let onNext: () -> Void
    let onClose: () -> Void

    // Lightweight “reaction” placeholder.
    // When you wire GIFs, replace this with a random GIF view.
    @State private var emoji = ["🎉", "🏆", "✨", "👏"].randomElement() ?? "🎉"

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()

            VStack(spacing: 14) {
                Text(useGifs ? emoji : "🏆")
                    .font(.system(size: 56))

                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                HStack(spacing: 12) {
                    Button("Close") { onClose() }
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.85))

                    Button("Next") { onNext() }
                        .buttonStyle(.borderedProminent)
                        .tint(themeManager.primary)
                }
                .padding(.top, 10)
            }
            .padding(.vertical, 26)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .padding(24)
        }
    }
}
