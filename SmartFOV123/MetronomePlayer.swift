import AVFoundation
import Foundation

final class MetronomePlayer {
    private final class AudioState: @unchecked Sendable {
        var tickPlayer: AVAudioPlayer?
        var tockPlayer: AVAudioPlayer?
        var gongPlayer: AVAudioPlayer?
        var generation: UInt64 = 0
    }

    private let audioQueue = DispatchQueue(
        label: "SmartFOV123.MetronomeAudio",
        qos: .userInteractive
    )
    private let audioState = AudioState()

    func start(
        startSeconds: [Int],
        beatsPerMinute: [Int],
        volume: Float,
        durationSeconds: Int
    ) {
        let audioState = audioState
        audioQueue.async { [weak self] in
            guard let self else { return }
            audioState.generation &+= 1
            let generation = audioState.generation
            audioState.tickPlayer = audioState.tickPlayer ?? Self.loadPlayer(named: "tick")
            audioState.tockPlayer = audioState.tockPlayer ?? Self.loadPlayer(named: "tock")
            audioState.gongPlayer = audioState.gongPlayer ?? Self.loadPlayer(named: "gong")
            guard audioState.tickPlayer != nil, audioState.tockPlayer != nil else { return }
            audioState.tickPlayer?.volume = volume
            audioState.tockPlayer?.volume = volume
            let start = DispatchTime.now().uptimeNanoseconds
            self.scheduleBeat(
                generation: generation,
                sessionStart: start,
                stageIndex: 0,
                beatIndex: 0,
                startSeconds: startSeconds,
                beatsPerMinute: beatsPerMinute,
                durationSeconds: durationSeconds
            )
        }
    }

    func finishSession() {
        let audioState = audioState
        audioQueue.async {
            audioState.generation &+= 1
            audioState.tickPlayer?.stop()
            audioState.tockPlayer?.stop()
        }
    }

    func playGong() {
        let audioState = audioState
        audioQueue.async {
            audioState.gongPlayer?.currentTime = 0
            if audioState.gongPlayer?.play() != true {
                print("SmartFOV123 audio error: gong playback couldn't start.")
            }
        }
    }

    func stop() {
        let audioState = audioState
        audioQueue.async {
            audioState.generation &+= 1
            audioState.tickPlayer?.stop()
            audioState.tockPlayer?.stop()
            audioState.gongPlayer?.stop()
        }
    }

    private func scheduleBeat(
        generation: UInt64,
        sessionStart: UInt64,
        stageIndex: Int,
        beatIndex: Int,
        startSeconds: [Int],
        beatsPerMinute: [Int],
        durationSeconds: Int
    ) {
        guard startSeconds.indices.contains(stageIndex),
              beatsPerMinute.indices.contains(stageIndex) else { return }
        let stageStartSeconds = startSeconds[stageIndex]
        guard stageStartSeconds >= 0 else {
            scheduleBeat(
                generation: generation,
                sessionStart: sessionStart,
                stageIndex: stageIndex + 1,
                beatIndex: 0,
                startSeconds: startSeconds,
                beatsPerMinute: beatsPerMinute,
                durationSeconds: durationSeconds
            )
            return
        }
        guard stageStartSeconds < durationSeconds else { return }
        let nextEnabledStart = startSeconds.dropFirst(stageIndex + 1).first {
            $0 >= 0
        }
        let stageEndSeconds = min(nextEnabledStart ?? durationSeconds, durationSeconds)
        let beatOffsetSeconds = Double(beatIndex) * 60 / Double(beatsPerMinute[stageIndex])
        let beatTimeSeconds = Double(stageStartSeconds) + beatOffsetSeconds
        guard beatTimeSeconds < Double(stageEndSeconds) - 0.000_001 else {
            scheduleBeat(
                generation: generation,
                sessionStart: sessionStart,
                stageIndex: stageIndex + 1,
                beatIndex: 0,
                startSeconds: startSeconds,
                beatsPerMinute: beatsPerMinute,
                durationSeconds: durationSeconds
            )
            return
        }

        let beatNanoseconds = UInt64((beatTimeSeconds * 1_000_000_000).rounded())
        let deadline = DispatchTime(uptimeNanoseconds: sessionStart + beatNanoseconds)
        audioQueue.asyncAfter(deadline: deadline) { [weak self] in
            guard let self, self.audioState.generation == generation else { return }
            let player = beatIndex.isMultiple(of: 4)
                ? self.audioState.tickPlayer
                : self.audioState.tockPlayer
            player?.currentTime = 0
            if player?.play() != true {
                print("SmartFOV123 audio error: metronome playback couldn't start.")
            }
            self.scheduleBeat(
                generation: generation,
                sessionStart: sessionStart,
                stageIndex: stageIndex,
                beatIndex: beatIndex + 1,
                startSeconds: startSeconds,
                beatsPerMinute: beatsPerMinute,
                durationSeconds: durationSeconds
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
