import CoreGraphics
import CoreText
import Foundation
import Metal

/// Produces a high-resolution binocular instruction panel for the windowless
/// compositor space. This is independent of the low-resolution experimental
/// digit glyphs and uses Core Text with antialiasing and font smoothing.
struct ParticipantPromptTexture {
    let texture: MTLTexture
    let halfSizeMeters: SIMD2<Float>

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        prompt: StimulusPresentationState.Prompt
    ) throws {
        let layout = Self.makeLayout(for: prompt)
        let width = Int(layout.canvasSize.width)
        let height = Int(layout.canvasSize.height)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
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
                roundedRect: layout.panelRect,
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
                in: layout.titleRect,
                fontSize: 58,
                weight: .bold,
                alignment: .center,
                in: context
            )

            if let emphasizedText = prompt.emphasizedText,
               let emphasizedRect = layout.emphasizedRect {
                Self.draw(
                    emphasizedText,
                    in: emphasizedRect,
                    fontSize: 84,
                    weight: .semibold,
                    alignment: .center,
                    in: context
                )
            }

            Self.draw(
                prompt.message,
                in: layout.messageRect,
                fontSize: 37,
                weight: .regular,
                alignment: prompt.usesLeadingAlignment ? .left : .center,
                in: context
            )
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb,
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
        let pixelsPerMeter: Float = 1_500
        halfSizeMeters = SIMD2<Float>(
            Float(width) / pixelsPerMeter / 2,
            Float(height) / pixelsPerMeter / 2
        )
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

    private struct Layout {
        let canvasSize: CGSize
        let panelRect: CGRect
        let titleRect: CGRect
        let emphasizedRect: CGRect?
        let messageRect: CGRect
    }

    private static func makeLayout(for prompt: StimulusPresentationState.Prompt) -> Layout {
        let outerMargin: CGFloat = 50
        let panelPadding: CGFloat = 80
        let maxContentWidth: CGFloat = 1_100
        let minContentWidth: CGFloat = 560
        let titleFontSize: CGFloat = 58
        let emphasizedFontSize: CGFloat = 84
        let messageFontSize: CGFloat = 37
        let sectionSpacing: CGFloat = 24

        let titleSize = measure(
            prompt.title,
            maxWidth: maxContentWidth,
            fontSize: titleFontSize,
            weight: .bold,
            alignment: .center
        )
        let emphasizedSize = prompt.emphasizedText.map {
            measure(
                $0,
                maxWidth: maxContentWidth,
                fontSize: emphasizedFontSize,
                weight: .semibold,
                alignment: .center
            )
        }
        let preliminaryMessageSize = measure(
            prompt.message,
            maxWidth: maxContentWidth,
            fontSize: messageFontSize,
            weight: .regular,
            alignment: prompt.usesLeadingAlignment ? .left : .center
        )
        let contentWidth = min(
            maxContentWidth,
            [minContentWidth, titleSize.width, emphasizedSize?.width ?? 0, preliminaryMessageSize.width].max()!
        )
        let messageSize = measure(
            prompt.message,
            maxWidth: contentWidth,
            fontSize: messageFontSize,
            weight: .regular,
            alignment: prompt.usesLeadingAlignment ? .left : .center
        )

        let contentHeight = titleSize.height
            + sectionSpacing
            + (emphasizedSize.map { $0.height + sectionSpacing } ?? 0)
            + messageSize.height
        let panelSize = CGSize(
            width: contentWidth + panelPadding * 2,
            height: max(360, contentHeight + panelPadding * 2)
        )
        let panelRect = CGRect(origin: CGPoint(x: outerMargin, y: outerMargin), size: panelSize)
        let contentX = panelRect.minX + panelPadding
        var cursorY = panelRect.maxY - panelPadding - titleSize.height
        let titleRect = CGRect(x: contentX, y: cursorY, width: contentWidth, height: titleSize.height)
        cursorY -= sectionSpacing
        var emphasizedRect: CGRect?
        if let emphasizedSize {
            cursorY -= emphasizedSize.height
            emphasizedRect = CGRect(
                x: contentX,
                y: cursorY,
                width: contentWidth,
                height: emphasizedSize.height
            )
            cursorY -= sectionSpacing
        }
        cursorY -= messageSize.height
        let messageRect = CGRect(
            x: contentX,
            y: cursorY,
            width: contentWidth,
            height: messageSize.height
        )

        return Layout(
            canvasSize: CGSize(
                width: ceil(panelSize.width + outerMargin * 2),
                height: ceil(panelSize.height + outerMargin * 2)
            ),
            panelRect: panelRect,
            titleRect: titleRect,
            emphasizedRect: emphasizedRect,
            messageRect: messageRect
        )
    }

    private static func measure(
        _ text: String,
        maxWidth: CGFloat,
        fontSize: CGFloat,
        weight: FontWeight,
        alignment: CTTextAlignment
    ) -> CGSize {
        let attributed = NSAttributedString(
            string: text,
            attributes: attributes(fontSize: fontSize, weight: weight, alignment: alignment)
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        return CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            nil
        )
    }

    private static func attributes(
        fontSize: CGFloat,
        weight: FontWeight,
        alignment: CTTextAlignment
    ) -> [NSAttributedString.Key: Any] {
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
        return [
            NSAttributedString.Key(kCTFontAttributeName as String):
                CTFontCreateWithName(weight.name, fontSize, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
        ]
    }

    private static func draw(
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        weight: FontWeight,
        alignment: CTTextAlignment,
        in context: CGContext
    ) {
        let attributed = NSAttributedString(
            string: text,
            attributes: attributes(fontSize: fontSize, weight: weight, alignment: alignment)
        )
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
