import CoreGraphics
import CoreText
import Foundation
import Metal

struct StimulusTexture {
    enum Presentation {
        case masked
        case revealed
        case highlightedCorrect
        case highlightedWrong
    }

    let texture: MTLTexture

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        experiment: Experiment,
        taskMode: TaskMode,
        score: Int,
        trialsRemaining: Int,
        presentation: Presentation
    ) throws {
        let config = experiment.configuration.stimulus
        let display = experiment.configuration.display
        let pixelsPerTile = 128

        let fovWidthMeters = Self.sizeMeters(
            degrees: config.fovWidthDegrees,
            distance: config.distanceMeters
        )
        let fovHeightMeters = Self.sizeMeters(
            degrees: config.fovHeightDegrees,
            distance: config.distanceMeters
        )
        let tileWidthMeters = Self.sizeMeters(
            degrees: config.tileWidthArcmin / 60,
            distance: config.distanceMeters
        )
        let tileHeightMeters = Self.sizeMeters(
            degrees: config.tileHeightArcmin / 60,
            distance: config.distanceMeters
        )
        let gutterMeters = Self.sizeMeters(
            degrees: config.tileGutterArcmin / 60,
            distance: config.distanceMeters
        )
        let surroundInnerMarginMeters = Self.sizeMeters(
            degrees: config.surroundInnerMarginArcmin / 60,
            distance: config.distanceMeters
        )

        let gridWidthMeters = tileWidthMeters * Float(experiment.grid.columns)
            + gutterMeters * Float(experiment.grid.columns - 1) + surroundInnerMarginMeters * 2
        let gridHeightMeters = tileHeightMeters * Float(experiment.grid.rows)
            + gutterMeters * Float(experiment.grid.rows - 1) + surroundInnerMarginMeters * 2
        let width = max(
            1,
            Int(ceil(
                Float(experiment.grid.columns * pixelsPerTile)
                    * fovWidthMeters / gridWidthMeters
                    * config.fovWidthScaleFactor
            ))
        )
        let height = max(
            1,
            Int(ceil(
                Float(experiment.grid.rows * pixelsPerTile)
                    * fovHeightMeters / gridHeightMeters
                    * config.fovHeightScaleFactor
            ))
        )
        let bytesPerRow = width * 4
        var pixels = [UInt8](
            repeating: 0,
            count: bytesPerRow * height
        )
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: RGB.sRGBColorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw StimulusTextureError.contextCreationFailed
            }

            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            // Keep grayscale edge antialiasing, but avoid RGB subpixel font
            // smoothing, which can alter the apparent hue of colored glyphs.
            context.setAllowsFontSmoothing(false)
            context.setShouldSmoothFonts(false)

            let scaleX = CGFloat(width) / CGFloat(fovWidthMeters)
            let scaleY = CGFloat(height) / CGFloat(fovHeightMeters)
            let surroundRect = CGRect(x: 0, y: 0, width: width, height: height)
            let gridCenter = CGPoint(
                x: CGFloat(width) / 2,
                y: CGFloat(height) / 2
            )
            let tileWidth = CGFloat(tileWidthMeters) * scaleX
            let tileHeight = CGFloat(tileHeightMeters) * scaleY
            let gutterWidth = CGFloat(gutterMeters) * scaleX
            let gutterHeight = CGFloat(gutterMeters) * scaleY
            let surroundInnerMarginWidth = CGFloat(surroundInnerMarginMeters) * scaleX
            let surroundInnerMarginHeight = CGFloat(surroundInnerMarginMeters) * scaleY
            let innerMarginRect = CGRect(
                x: gridCenter.x - (tileWidth * CGFloat(experiment.grid.columns)
                    + gutterWidth * CGFloat(experiment.grid.columns - 1)
                    + surroundInnerMarginWidth * 2) / 2,
                y: gridCenter.y - (tileHeight * CGFloat(experiment.grid.rows)
                    + gutterHeight * CGFloat(experiment.grid.rows - 1)
                    + surroundInnerMarginHeight * 2) / 2,
                width: tileWidth * CGFloat(experiment.grid.columns)
                    + gutterWidth * CGFloat(experiment.grid.columns - 1)
                    + surroundInnerMarginWidth * 2,
                height: tileHeight * CGFloat(experiment.grid.rows)
                    + gutterHeight * CGFloat(experiment.grid.rows - 1)
                    + surroundInnerMarginHeight * 2
            )
            let tileFieldRect = innerMarginRect.insetBy(
                dx: surroundInnerMarginWidth,
                dy: surroundInnerMarginHeight
            )

            let timeBarBackHeight = CGFloat(Self.sizeMeters(
                degrees: config.timeBarBackHeightArcmin / 60,
                distance: config.distanceMeters
            )) * scaleY
            let timeBarBackRect = CGRect(
                x: innerMarginRect.minX,
                y: innerMarginRect.minY - timeBarBackHeight,
                width: innerMarginRect.width,
                height: timeBarBackHeight
            )

            let cornerRadiusMeters = Self.sizeMeters(
                degrees: config.tileCornerRadiusArcmin / 60,
                distance: config.distanceMeters
            )
            let cornerRadiusPixels = CGFloat(cornerRadiusMeters) * (scaleX + scaleY) / 2
            let maximumCornerRadius = min(tileWidth, tileHeight) / 2
            let cornerRadius = min(cornerRadiusPixels, maximumCornerRadius)
            let surroundInnerCornerRadiusMeters = Self.sizeMeters(
                degrees: config.surroundInnerCornerRadiusArcmin / 60,
                distance: config.distanceMeters
            )
            let surroundInnerCornerRadius = min(
                CGFloat(surroundInnerCornerRadiusMeters) * (scaleX + scaleY) / 2,
                min(innerMarginRect.width, innerMarginRect.height) / 2
            )
            let surroundOuterCornerRadiusMeters = Self.sizeMeters(
                degrees: config.surroundOuterCornerRadiusArcmin / 60,
                distance: config.distanceMeters
            )
            let surroundOuterCornerRadius = min(
                CGFloat(surroundOuterCornerRadiusMeters) * (scaleX + scaleY) / 2,
                min(surroundRect.width, surroundRect.height) / 2
            )
            let surroundPath = CGPath(
                roundedRect: surroundRect,
                cornerWidth: surroundOuterCornerRadius,
                cornerHeight: surroundOuterCornerRadius,
                transform: nil
            )
            context.setFillColor(config.surroundFillRGB.cgColor)
            context.addPath(surroundPath)
            context.fillPath()
            context.saveGState()
            context.addPath(surroundPath)
            context.clip()
            context.setFillColor(config.surroundInnerMarginRGB.cgColor)
            context.addPath(CGPath(
                roundedRect: innerMarginRect,
                cornerWidth: surroundInnerCornerRadius,
                cornerHeight: surroundInnerCornerRadius,
                transform: nil
            ))
            context.fillPath()
            context.setFillColor(config.tileFillRGB.cgColor)
            for row in 0..<experiment.grid.rows {
                for column in 0..<experiment.grid.columns {
                    let tileRect = CGRect(
                        x: tileFieldRect.minX + CGFloat(column) * (tileWidth + gutterWidth),
                        y: tileFieldRect.minY + CGFloat(row) * (tileHeight + gutterHeight),
                        width: tileWidth,
                        height: tileHeight
                    )
                    context.addPath(CGPath(roundedRect: tileRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
                    context.fillPath()
                }
            }
            context.restoreGState()

            if case .loopTrials = taskMode {
                let backCornerRadius = min(
                    CGFloat(Self.sizeMeters(
                        degrees: config.timeBarBackCornerRadiusArcmin / 60,
                        distance: config.distanceMeters
                    )) * (scaleX + scaleY) / 2,
                    min(timeBarBackRect.width, timeBarBackRect.height) / 2
                )
                context.setFillColor(config.timeBarBackRGB.cgColor)
                context.addPath(CGPath(
                    roundedRect: timeBarBackRect,
                    cornerWidth: backCornerRadius,
                    cornerHeight: backCornerRadius,
                    transform: nil
                ))
                context.fillPath()
            }

            let desiredDigitCapHeight = CGFloat(
                Self.sizeMeters(
                    degrees: config.digitHeightArcmin / 60,
                    distance: config.distanceMeters
                )
            ) * scaleY
            let desiredAnnotationCapHeight = CGFloat(
                Self.sizeMeters(
                    degrees: config.annotationHeightArcmin / 60,
                    distance: config.distanceMeters
                )
            ) * scaleY
            let digitFont = try Self.font(
                named: config.digitFontName,
                capHeight: desiredDigitCapHeight
            )
            let highlightDigitFont = try Self.font(
                named: config.digitHighlightFontName,
                capHeight: desiredDigitCapHeight
            )
            let annotationFont = try Self.font(
                named: config.annotationFontName,
                capHeight: desiredAnnotationCapHeight
            )
            let digitAttributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): digitFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    config.digitRGB.cgColor
            ]
            let highlightDigitAttributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): highlightDigitFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    (presentation == .highlightedCorrect
                        ? config.digitHighlightCorrectRGB
                        : config.digitHighlightWrongRGB).cgColor
            ]
            let annotationAttributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): annotationFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    config.annotationFontRGB.cgColor
            ]

            let headingY = innerMarginRect.maxY + desiredAnnotationCapHeight
            let targetHeading = "Target: \(experiment.grid.targetNumber)"
            if case .loopTrials = taskMode {
                let scoreHeading = String(format: "Score: %03d", max(0, score))
                Self.drawText(
                    scoreHeading,
                    centeredAt: CGPoint(
                        x: innerMarginRect.maxX - Self.textWidth(
                            scoreHeading,
                            attributes: annotationAttributes
                        ) / 2,
                        y: headingY
                    ),
                    attributes: annotationAttributes,
                    in: context
                )
            }
            Self.drawText(
                targetHeading,
                centeredAt: CGPoint(
                    x: innerMarginRect.minX + Self.textWidth(
                        targetHeading,
                        attributes: annotationAttributes
                    ) / 2,
                    y: headingY
                ),
                attributes: annotationAttributes,
                in: context
            )

            let highlightedIndices = presentation == .highlightedCorrect
                || presentation == .highlightedWrong
                ? Self.solutionIndices(in: experiment.grid)
                : []
            for index in experiment.grid.digits.indices {
                let row = index / experiment.grid.columns
                let column = index % experiment.grid.columns
                let center = CGPoint(
                    x: tileFieldRect.minX + CGFloat(column) * (tileWidth + gutterWidth)
                        + tileWidth / 2,
                    y: tileFieldRect.maxY - CGFloat(row) * (tileHeight + gutterHeight)
                        - tileHeight / 2
                )
                let glyph = presentation == .masked
                    ? config.maskingCharacter
                    : String(experiment.grid.digit(at: index))
                Self.drawText(
                    glyph,
                    centeredAt: center,
                    attributes: highlightedIndices.contains(index)
                        ? highlightDigitAttributes
                        : digitAttributes,
                    in: context
                )
            }

            if taskMode == .fixedNumberOfTrials {
                Self.drawText(
                    String(format: "%03d trials remain", max(0, trialsRemaining)),
                    centeredAt: CGPoint(
                        x: innerMarginRect.midX,
                        y: innerMarginRect.minY - desiredAnnotationCapHeight
                    ),
                    attributes: annotationAttributes,
                    in: context
                )
            }

        }

        Self.applyDisplayModel(display, to: &pixels)

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
        let presentationLabel: String
        switch presentation {
        case .masked: presentationLabel = "masked"
        case .revealed: presentationLabel = "revealed"
        case .highlightedCorrect: presentationLabel = "highlighted-correct"
        case .highlightedWrong: presentationLabel = "highlighted-wrong"
        }
        texture.label = "Precomposed SmartFOV123 stimulus (\(display.mode.rawValue), \(presentationLabel))"
        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: width * 4
            )
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw StimulusTextureError.mipmapEncodingFailed
        }
        blitEncoder.label = "SmartFOV123 stimulus mipmap generation"
        blitEncoder.generateMipmaps(for: texture)
        blitEncoder.endEncoding()
        commandBuffer.commit()

        self.texture = texture
    }

    private static func drawText(
        _ string: String,
        centeredAt center: CGPoint,
        attributes: [NSAttributedString.Key: Any],
        in context: CGContext
    ) {
        drawText(
            NSAttributedString(string: string, attributes: attributes),
            centeredAt: center,
            in: context
        )
    }

    private static func solutionIndices(in grid: NumberGrid) -> Set<Int> {
        let placement = grid.targetPlacement
        var cells = Set<Int>()
        for offset in 0..<3 {
            let row = placement.orientation == .horizontal
                ? placement.row
                : placement.row + offset
            let column = placement.orientation == .horizontal
                ? placement.column + offset
                : placement.column
            cells.insert(row * grid.columns + column)
        }

        let middleRow = placement.row
            + (placement.orientation == .vertical ? 1 : 0)
        let middleColumn = placement.column
            + (placement.orientation == .horizontal ? 1 : 0)
        for offset in -1...1 {
            let row = placement.orientation == .horizontal
                ? middleRow + offset
                : middleRow
            let column = placement.orientation == .horizontal
                ? middleColumn
                : middleColumn + offset
            cells.insert(row * grid.columns + column)
        }
        return cells
    }

    private static func drawText(
        _ attributed: NSAttributedString,
        centeredAt center: CGPoint,
        in context: CGContext
    ) {
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        )
        context.textPosition = CGPoint(
            x: center.x - lineWidth / 2,
            y: center.y - (ascent + descent) / 2 + descent
        )
        CTLineDraw(line, context)
    }

    private static func textWidth(
        _ string: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes)
        )
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func font(named name: String, capHeight: CGFloat) throws -> CTFont {
        let trialFont = CTFontCreateWithName(name as CFString, 100, nil)
        let trialCapHeight = CTFontGetCapHeight(trialFont)
        guard trialCapHeight > 0 else {
            throw StimulusTextureError.invalidFont(name)
        }
        return CTFontCreateWithName(
            name as CFString,
            100 * capHeight / trialCapHeight,
            nil
        )
    }

    static func applyDisplayModel(
        _ display: DisplayConfiguration,
        to pixels: inout [UInt8]
    ) {
        let peakOpacity = display.peakOpacity
        let linearBySRGBByte = (0...255).map {
            sRGBToLinear(Float($0) / 255)
        }
        let premultipliedSRGBByByte = linearBySRGBByte.map {
            byte(linearToSRGB($0 * peakOpacity))
        }
        let opticalAlphaByByte = linearBySRGBByte.map {
            byte($0 * peakOpacity)
        }
        let videoPassthroughAlpha = byte(peakOpacity)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])

            // Core Graphics supplies sRGB-encoded bytes, while Metal decodes
            // RGB from an sRGB texture to linear light during sampling. Apply
            // display scaling and premultiplication in linear light, then
            // encode RGB back to sRGB storage. Alpha is always stored linearly.
            pixels[index] = premultipliedSRGBByByte[red]
            pixels[index + 1] = premultipliedSRGBByByte[green]
            pixels[index + 2] = premultipliedSRGBByByte[blue]
            switch display.mode {
            case .videoPassthrough:
                pixels[index + 3] = videoPassthroughAlpha
            case .opticalSeeThroughSimulation:
                pixels[index + 3] = opticalAlphaByByte[max(red, green, blue)]
            }
        }
    }

    private static func sRGBToLinear(_ value: Float) -> Float {
        value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func linearToSRGB(_ value: Float) -> Float {
        value <= 0.0031308
            ? value * 12.92
            : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    private static func byte(_ value: Float) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded())
    }

    private static func sizeMeters(degrees: Float, distance: Float) -> Float {
        2 * distance * tan(degrees * .pi / 360)
    }

}

private extension RGB {
    static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    var cgColor: CGColor {
        CGColor(
            colorSpace: Self.sRGBColorSpace,
            components: [CGFloat(red), CGFloat(green), CGFloat(blue), 1]
        )!
    }
}

enum StimulusTextureError: LocalizedError {
    case invalidFont(String)
    case contextCreationFailed
    case textureCreationFailed
    case mipmapEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidFont(let name):
            return "The configured font ‘\(name)’ doesn't provide usable uppercase metrics."
        case .contextCreationFailed:
            return "The app couldn't create the precomposed stimulus drawing context."
        case .textureCreationFailed:
            return "Metal couldn't create the precomposed stimulus texture."
        case .mipmapEncodingFailed:
            return "Metal couldn't generate the stimulus texture mipmaps."
        }
    }
}
