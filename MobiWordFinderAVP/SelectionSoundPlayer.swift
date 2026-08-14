import AudioToolbox
import Foundation

final class SelectionSoundPlayer {
    private var correctSoundID: SystemSoundID?
    private var wrongSoundID: SystemSoundID?

    init() {
        correctSoundID = Self.loadSound(named: "correct")
        wrongSoundID = Self.loadSound(named: "wrong")
    }

    deinit {
        if let correctSoundID {
            AudioServicesDisposeSystemSoundID(correctSoundID)
        }
        if let wrongSoundID {
            AudioServicesDisposeSystemSoundID(wrongSoundID)
        }
    }

    func playCorrect() {
        play(correctSoundID)
    }

    func playWrong() {
        play(wrongSoundID)
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
