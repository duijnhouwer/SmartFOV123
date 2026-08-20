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
        minimumBeatsPerMinute: Int,
        maximumBeatsPerMinute: Int,
        incrementIntervalBeats: Int,
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
            let playbackVolume = Self.playbackVolume(for: volume)
            audioState.tickPlayer?.volume = playbackVolume
            audioState.tockPlayer?.volume = playbackVolume
            let start = DispatchTime.now().uptimeNanoseconds
            let tempos = Self.tempoProgression(
                minimumBeatsPerMinute: minimumBeatsPerMinute,
                maximumBeatsPerMinute: maximumBeatsPerMinute,
                incrementIntervalBeats: incrementIntervalBeats,
                durationSeconds: durationSeconds
            )
            self.scheduleBeat(
                generation: generation,
                sessionStart: start,
                stageIndex: 0,
                beatIndex: 0,
                totalBeatIndex: 0,
                beatTimeSeconds: 0,
                tempos: tempos,
                incrementIntervalBeats: incrementIntervalBeats,
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

    func playGong(volume: Float) {
        let audioState = audioState
        audioQueue.async {
            audioState.gongPlayer?.volume = Self.playbackVolume(for: volume)
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
        totalBeatIndex: Int,
        beatTimeSeconds: Double,
        tempos: [Double],
        incrementIntervalBeats: Int,
        durationSeconds: Int
    ) {
        guard tempos.indices.contains(stageIndex),
              beatTimeSeconds < Double(durationSeconds) - 0.000_001 else { return }

        let beatNanoseconds = UInt64((beatTimeSeconds * 1_000_000_000).rounded())
        let deadline = DispatchTime(uptimeNanoseconds: sessionStart + beatNanoseconds)
        audioQueue.asyncAfter(deadline: deadline) { [weak self] in
            guard let self, self.audioState.generation == generation else { return }
            let player = totalBeatIndex.isMultiple(of: 4)
                ? self.audioState.tickPlayer
                : self.audioState.tockPlayer
            player?.currentTime = 0
            if player?.play() != true {
                print("SmartFOV123 audio error: metronome playback couldn't start.")
            }
            self.scheduleBeat(
                generation: generation,
                sessionStart: sessionStart,
                stageIndex: beatIndex + 1 == incrementIntervalBeats
                    ? min(stageIndex + 1, tempos.count - 1)
                    : stageIndex,
                beatIndex: (beatIndex + 1) % incrementIntervalBeats,
                totalBeatIndex: totalBeatIndex + 1,
                beatTimeSeconds: beatTimeSeconds + 60 / tempos[stageIndex],
                tempos: tempos,
                incrementIntervalBeats: incrementIntervalBeats,
                durationSeconds: durationSeconds
            )
        }
    }

    /// Selects the integer number of full beat intervals whose geometric tempo
    /// progression is closest to the session duration. Every step therefore
    /// uses the same percentage increase, and the last tempo is exactly max.
    private static func tempoProgression(
        minimumBeatsPerMinute: Int,
        maximumBeatsPerMinute: Int,
        incrementIntervalBeats: Int,
        durationSeconds: Int
    ) -> [Double] {
        let minimum = Double(minimumBeatsPerMinute)
        let maximum = Double(maximumBeatsPerMinute)
        guard maximum > minimum else { return [minimum] }

        let maximumCandidateCount = max(
            2,
            Int(ceil(Double(durationSeconds) * maximum / (60 * Double(incrementIntervalBeats)))) + 2
        )
        var bestTempos: [Double] = [minimum, maximum]
        var smallestDurationError = Double.greatestFiniteMagnitude

        for stageCount in 2...maximumCandidateCount {
            let multiplier = pow(maximum / minimum, 1 / Double(stageCount - 1))
            let tempos = (0..<stageCount).map { stageIndex in
                stageIndex == stageCount - 1
                    ? maximum
                    : minimum * pow(multiplier, Double(stageIndex))
            }
            let progressionDuration = tempos.reduce(0) {
                $0 + Double(incrementIntervalBeats) * 60 / $1
            }
            let error = abs(progressionDuration - Double(durationSeconds))
            if error < smallestDurationError {
                smallestDurationError = error
                bestTempos = tempos
            }
        }
        return bestTempos
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

    /// AVAudioPlayer volume is linear amplitude, which bunches perceived
    /// loudness changes near the top of a 0...1 control. A squared fader curve
    /// keeps exact silence/full scale while making intermediate settings sound
    /// closer to evenly spaced.
    private static func playbackVolume(for configuredVolume: Float) -> Float {
        let clamped = min(max(configuredVolume, 0), 1)
        return clamped * clamped
    }
}
