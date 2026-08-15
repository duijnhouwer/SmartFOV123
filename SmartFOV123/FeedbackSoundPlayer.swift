import AudioToolbox
import AVFoundation
import Foundation

final class FeedbackSoundPlayer {
    private let correctPlayer: AVAudioPlayer?
    private let wrongPlayer: AVAudioPlayer?
    private let popPlayer: AVAudioPlayer?

    init() {
        // The session-level setting is a fallback for visionOS versions before
        // per-player spatial experiences became available.
        Self.configureHeadLockedAudio()
        correctPlayer = Self.loadPlayer(named: "correct")
        wrongPlayer = Self.loadPlayer(named: "wrong")
        popPlayer = Self.loadPlayer(named: "pop")
    }

    func playCorrect() {
        play(correctPlayer)
    }

    func playWrong() {
        play(wrongPlayer)
    }

    func playPop() {
        play(popPlayer)
    }

    private func play(_ player: AVAudioPlayer?) {
        guard let player else { return }
        player.currentTime = 0
        guard player.play() else {
            print("SmartFOV123 audio error: AVAudioPlayer refused to start playback.")
            return
        }
    }

    private static func configureHeadLockedAudio() {
        do {
            let experience: any AVAudioSessionSpatialExperience = .fixed(
                soundStageSize: .small
            )
            try AVAudioSession.sharedInstance().setIntendedSpatialExperience(experience)
        } catch {
            print(
                "SmartFOV123 audio error: couldn't configure head-locked audio "
                    + "(\(error.localizedDescription))."
            )
        }
    }

    private static func loadPlayer(named name: String) -> AVAudioPlayer? {
        let url = Bundle.main.url(forResource: name, withExtension: "caf")
            ?? Bundle.main.url(forResource: name, withExtension: "caf", subdirectory: "Config")
        guard let url else {
            print("SmartFOV123 audio error: \(name).caf is missing from the app bundle.")
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            if #available(visionOS 26.0, *) {
                // Apply the fixed experience to the actual playback object.
                // Unlike AudioServices system sounds, this prevents visionOS
                // from anchoring feedback to the app's operator window.
                player.intendedSpatialExperience = .fixed(soundStageSize: .small)
            }
            player.prepareToPlay()
            return player
        } catch {
            print(
                "SmartFOV123 audio error: couldn't load \(name).caf "
                    + "(\(error.localizedDescription))."
            )
            return nil
        }
    }
}
