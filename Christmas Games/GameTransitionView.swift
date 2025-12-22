import SwiftUI
import AVFoundation
import AudioToolbox

/// Animated transition view shown between games
struct GameTransitionView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @AppStorage("gameTransitionSound") private var soundEnabled: Bool = true
    @AppStorage("transitionSoundName") private var transitionSoundName: String = "random"


    let onComplete: () -> Void

    @State private var dotCount = 0
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        ZStack {
            themeManager.background
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "hourglass.circle.fill")
                    .font(.system(size: 86))
                    .foregroundColor(themeManager.primary)
                    .rotationEffect(.degrees(dotCount % 2 == 0 ? -10 : 10))

                Text("Selecting next game\(String(repeating: ".", count: dotCount % 4))")
                    .font(.title2)
                    .foregroundColor(themeManager.text)
            }
        }
        .onAppear {
            if soundEnabled { playSound() }
            startDotAnimation()

            // Keep this short so the app feels responsive.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                onComplete()
            }
        }
    }

    private func playSound() {
        // Allow user to disable
        if transitionSoundName == "off" { return }

        let baseName: String
        if transitionSoundName == "random" {
            baseName = ["jeopardy1", "jeopardy2", "jeopardy3"].randomElement() ?? "jeopardy1"
        } else {
            baseName = transitionSoundName
        }

        guard let url = Bundle.main.url(forResource: baseName, withExtension: "m4a") else {
            // Fallback: try mp3 if you ever swap formats
            if let url2 = Bundle.main.url(forResource: baseName, withExtension: "mp3") {
                audioPlayer = try? AVAudioPlayer(contentsOf: url2)
                audioPlayer?.volume = 1.0
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
            }
            return
        }

        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.volume = 1.0
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
    }



    private func startDotAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { timer in
            dotCount += 1
            if dotCount > 40 { timer.invalidate() }
        }
    }
}
