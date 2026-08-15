import CoreGraphics
import CoreText
import Foundation
import Metal

/// Produces a high-resolution binocular instruction panel for the windowless
/// compositor space. This is independent of the low-resolution experimental
/// digit glyphs and uses Core Text with antialiasing and font smoothing.
struct ParticipantPromptTexture {
    let texture: MTLTexture

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        prompt: StimulusPresentationState.Prompt
    ) throws {
        let width = 1_400
        let height = 1_000
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw StimulusTextureError.contextCreationFailed
            }

            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setAllowsFontSmoothing(true)
            context.setShouldSmoothFonts(true)
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))

            let panel = CGPath(
                roundedRect: CGRect(x: 70, y: 70, width: 1_260, height: 860),
                cornerWidth: 64,
                cornerHeight: 64,
                transform: nil
            )
            context.addPath(panel)
            context.setFillColor(CGColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 0.88))
            context.fillPath()
            context.addPath(panel)
            context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.24))
            context.setLineWidth(3)
            context.strokePath()

            Self.draw(
                prompt.title,
                in: CGRect(x: 150, y: 760, width: 1_100, height: 105),
                fontSize: 58,
                weight: .bold,
                alignment: .center,
                in: context
            )

            var messageTop: CGFloat = 700
            if let emphasizedText = prompt.emphasizedText {
                Self.draw(
                    emphasizedText,
                    in: CGRect(x: 150, y: 625, width: 1_100, height: 105),
                    fontSize: 84,
                    weight: .semibold,
                    alignment: .center,
                    in: context
                )
                messageTop = 590
            }

            Self.draw(
                prompt.message,
                in: CGRect(x: 150, y: 145, width: 1_100, height: messageTop - 145),
                fontSize: 37,
                weight: .regular,
                alignment: prompt.usesLeadingAlignment ? .left : .center,
                in: context
            )
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: true
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw StimulusTextureError.textureCreationFailed
        }
        texture.label = "SmartFOV123 participant prompt"
        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: bytesPerRow
            )
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw StimulusTextureError.mipmapEncodingFailed
        }
        blitEncoder.generateMipmaps(for: texture)
        blitEncoder.endEncoding()
        commandBuffer.commit()
        self.texture = texture
    }

    private enum FontWeight {
        case regular
        case semibold
        case bold

        var name: CFString {
            switch self {
            case .regular: return "HelveticaNeue" as CFString
            case .semibold: return "HelveticaNeue-Medium" as CFString
            case .bold: return "HelveticaNeue-Bold" as CFString
            }
        }
    }

    private static func draw(
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        weight: FontWeight,
        alignment: CTTextAlignment,
        in context: CGContext
    ) {
        var textAlignment = alignment
        var lineSpacing: CGFloat = 10
        let paragraphStyle = withUnsafePointer(to: &textAlignment) { alignmentPointer in
            withUnsafePointer(to: &lineSpacing) { lineSpacingPointer in
                let settings: [CTParagraphStyleSetting] = [
                    CTParagraphStyleSetting(
                        spec: .alignment,
                        valueSize: MemoryLayout<CTTextAlignment>.size,
                        value: alignmentPointer
                    ),
                    CTParagraphStyleSetting(
                        spec: .lineSpacingAdjustment,
                        valueSize: MemoryLayout<CGFloat>.size,
                        value: lineSpacingPointer
                    )
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String):
                CTFontCreateWithName(weight.name, fontSize, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)
    }
}
