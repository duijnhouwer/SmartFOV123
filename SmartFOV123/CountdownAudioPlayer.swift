import AVFoundation
import Foundation

final class CountdownAudioPlayer {
    private var stopwatchPlayer: AVAudioPlayer?
    private var gongPlayer: AVAudioPlayer?

    func start(volume: Float) {
        stopwatchPlayer = stopwatchPlayer ?? Self.loadPlayer(named: "stopwatch")
        guard let stopwatchPlayer else { return }
        stopwatchPlayer.numberOfLoops = -1
        stopwatchPlayer.volume = Self.playbackVolume(for: volume)
        if !stopwatchPlayer.play() {
            print("SmartFOV123 audio error: stopwatch playback couldn't start.")
        }
    }

    func pause() {
        stopwatchPlayer?.pause()
    }

    func playGong(volume: Float) {
        gongPlayer = gongPlayer ?? Self.loadPlayer(named: "gong")
        gongPlayer?.volume = Self.playbackVolume(for: volume)
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

    private static func loadPlayer(named name: String) -> AVAudioPlayer? {
        let url = Bundle.main.url(forResource: name, withExtension: "caf")
            ?? Bundle.main.url(forResource: name, withExtension: "caf", subdirectory: "Audio")
        guard let url else {
            print("SmartFOV123 audio error: \(name).caf is missing from the app bundle.")
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
                "SmartFOV123 audio error: couldn't load \(name).caf "
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
