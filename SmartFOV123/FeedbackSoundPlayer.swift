import AVFoundation
import Foundation

final class FeedbackSoundPlayer {
    private enum Sound: Sendable {
        case correct
        case wrong
        case pop
    }

    private final class AudioState: @unchecked Sendable {
        var correctPlayer: AVAudioPlayer?
        var wrongPlayer: AVAudioPlayer?
        var popPlayer: AVAudioPlayer?
        var configurationKey: String?
    }

    private let audioQueue = DispatchQueue(label: "SmartFOV123.FeedbackAudio")
    private let audioState = AudioState()

    func prepare(configuration: StimulusConfiguration) async {
        let audioState = audioState
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            audioQueue.async {
                defer { continuation.resume() }
                let configurationKey = [
                    configuration.correctFeedbackFile,
                    String(configuration.correctFeedbackVolume),
                    configuration.wrongFeedbackFile,
                    String(configuration.wrongFeedbackVolume)
                ].joined(separator: "|")
                guard audioState.configurationKey != configurationKey else { return }

                // The session-level setting is a fallback for visionOS versions before
                // per-player spatial experiences became available.
                Self.configureHeadLockedAudio()
                audioState.correctPlayer = Self.loadPlayer(file: configuration.correctFeedbackFile)
                audioState.correctPlayer?.volume = Self.playbackVolume(
                    for: configuration.correctFeedbackVolume
                )
                audioState.wrongPlayer = Self.loadPlayer(file: configuration.wrongFeedbackFile)
                audioState.wrongPlayer?.volume = Self.playbackVolume(
                    for: configuration.wrongFeedbackVolume
                )
                audioState.popPlayer = audioState.popPlayer ?? Self.loadPlayer(file: "pop.caf")
                audioState.configurationKey = configurationKey
            }
        }
    }

    func playCorrect() {
        play(.correct)
    }

    func playWrong() {
        play(.wrong)
    }

    func playPop() {
        play(.pop)
    }

    private func play(_ sound: Sound) {
        let audioState = audioState
        audioQueue.async {
            let player = switch sound {
            case .correct: audioState.correctPlayer
            case .wrong: audioState.wrongPlayer
            case .pop: audioState.popPlayer
            }
            guard let player else { return }
            player.currentTime = 0
            guard player.play() else {
                print("SmartFOV123 audio error: AVAudioPlayer refused to start playback.")
                return
            }
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

    private static func loadPlayer(file: String) -> AVAudioPlayer? {
        let fileName = file as NSString
        let name = fileName.deletingPathExtension
        let fileExtension = fileName.pathExtension.isEmpty ? "caf" : fileName.pathExtension
        let url = Bundle.main.url(forResource: name, withExtension: fileExtension)
            ?? Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Audio")
        guard let url else {
            print("SmartFOV123 audio error: \(file) is missing from the app bundle.")
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
                "SmartFOV123 audio error: couldn't load \(file) "
                    + "(\(error.localizedDescription))."
            )
            return nil
        }
    }

    private static func playbackVolume(for configuredVolume: Float) -> Float {
        let clamped = min(max(configuredVolume, 0), 1)
        return clamped * clamped
    }
}
