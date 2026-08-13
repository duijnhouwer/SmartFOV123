import SwiftUI

@MainActor
@Observable
final class EyeTestAppModel {
    enum ImmersiveSpaceState: Equatable {
        case closed
        case inTransition
        case open
    }

    let immersiveSpaceID = "EyeTestSpace"
    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var statusMessage: String?
}
