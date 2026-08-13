import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum ImmersiveSpaceState: Equatable {
        case closed
        case inTransition
        case open
    }

    let immersiveSpaceID = "MobiWordFinderSpace"
    let experiment: Experiment?
    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var statusMessage: String?

    init() {
        do {
            experiment = try Experiment.loadBundled()
        } catch {
            experiment = nil
            statusMessage = error.localizedDescription
        }
    }

    var trialDescription: String {
        guard let experiment else { return "No valid experiment is loaded." }
        let config = experiment.configuration.stimulus
        return "Find \(config.targetWord) in the \(experiment.grid.columns) × \(experiment.grid.rows) grid. Look at its middle letter and pinch to select it."
    }

    func handleSelection(identifier: UInt64) {
        guard let experiment else { return }
        let index = Int(identifier) - 1
        guard experiment.grid.letters.indices.contains(index) else { return }

        let row = index / experiment.grid.columns
        let column = index % experiment.grid.columns
        let letter = experiment.grid.letter(at: index)
        if index == experiment.grid.targetMiddleIndex {
            statusMessage = "Correct — selected \(letter) at row \(row + 1), column \(column + 1)."
        } else {
            statusMessage = "Selected \(letter) at row \(row + 1), column \(column + 1). Keep looking for \(experiment.grid.targetWord)."
        }
    }
}
