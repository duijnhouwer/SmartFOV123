import AudioToolbox
import Foundation

final class FeedbackSoundPlayer {
    private var correctSoundID: SystemSoundID?
    private var wrongSoundID: SystemSoundID?
    private var popSoundID: SystemSoundID?

    init() {
        correctSoundID = Self.loadSound(named: "correct")
        wrongSoundID = Self.loadSound(named: "wrong")
        popSoundID = Self.loadSound(named: "pop")
    }

    deinit {
        if let correctSoundID {
            AudioServicesDisposeSystemSoundID(correctSoundID)
        }
        if let wrongSoundID {
            AudioServicesDisposeSystemSoundID(wrongSoundID)
        }
        if let popSoundID {
            AudioServicesDisposeSystemSoundID(popSoundID)
        }
    }

    func playCorrect() {
        play(correctSoundID)
    }

    func playWrong() {
        play(wrongSoundID)
    }

    func playPop() {
        play(popSoundID)
    }

    private func play(_ soundID: SystemSoundID?) {
        guard let soundID else { return }
        AudioServicesPlaySystemSound(soundID)
    }

    private static func loadSound(named name: String) -> SystemSoundID? {
        let url = Bundle.main.url(forResource: name, withExtension: "caf")
            ?? Bundle.main.url(forResource: name, withExtension: "caf", subdirectory: "Config")
        guard let url else {
            print("MobiWordFinder audio error: \(name).caf is missing from the app bundle.")
            return nil
        }

        var soundID = SystemSoundID()
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        guard status == kAudioServicesNoError else {
            print("MobiWordFinder audio error: couldn't load \(name).caf (OSStatus \(status)).")
            return nil
        }
        return soundID
    }
}
