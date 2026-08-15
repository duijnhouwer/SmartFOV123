import RealityKit
import SwiftUI

struct ParticipantPromptView: View {
    let appModel: AppModel

    var body: some View {
        RealityView { content, attachments in
            let headAnchor = AnchorEntity(.head, trackingMode: .continuous)
            headAnchor.name = "ParticipantPromptHeadAnchor"
            headAnchor.position = [0, 0, -1.5]
            if let attachment = attachments.entity(for: "ParticipantPrompt") {
                headAnchor.addChild(attachment)
            }
            content.add(headAnchor)
        } update: { _, _ in
        } attachments: {
            Attachment(id: "ParticipantPrompt") {
                if let prompt = appModel.participantPrompt {
                    VStack(spacing: 24) {
                        Text(prompt.title)
                            .font(.largeTitle.bold())

                        if let emphasizedText = prompt.emphasizedText {
                            Text(emphasizedText)
                                .font(.system(size: 64, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }

                        Text(prompt.message)
                            .font(.title2)
                            .lineSpacing(7)
                            .multilineTextAlignment(
                                appModel.trialPhase == .instructions ? .leading : .center
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: appModel.trialPhase == .instructions
                                    ? .leading
                                    : .center
                            )
                    }
                    .multilineTextAlignment(.center)
                    .padding(48)
                    .frame(width: 620)
                    .glassBackgroundEffect()
                }
            }
        }
    }
}
