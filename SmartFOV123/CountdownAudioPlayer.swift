import AVFoundation
import Foundation

final class CountdownAudioPlayer {
    private var stopwatchPlayer: AVAudioPlayer?
    private var gongPlayer: AVAudioPlayer?

    func start(sound: SoundEffectConfiguration) {
        stopwatchPlayer = Self.loadPlayer(file: sound.file)
        guard let stopwatchPlayer else { return }
        stopwatchPlayer.numberOfLoops = -1
        stopwatchPlayer.volume = Self.playbackVolume(for: sound.volume)
        if !stopwatchPlayer.play() {
            print("SmartFOV123 audio error: stopwatch playback couldn't start.")
        }
    }

    func pause() {
        stopwatchPlayer?.pause()
    }

    func playGong(sound: SoundEffectConfiguration) {
        gongPlayer = Self.loadPlayer(file: sound.file)
        gongPlayer?.volume = Self.playbackVolume(for: sound.volume)
        gongPlayer?.currentTime = 0
        if gongPlayer?.play() != true {
            print("SmartFOV123 audio error: gong playback couldn't start.")
        }
    }

    func stop() {
        stopwatchPlayer?.stop()
        stopwatchPlayer?.currentTime = 0
        gongPlayer?.stop()
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
