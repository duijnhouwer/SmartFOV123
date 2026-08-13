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
    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var statusMessage: String?
}
