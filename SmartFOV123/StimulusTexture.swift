import CoreGraphics
import CoreText
import Foundation
import Metal

struct StimulusTexture {
    enum Presentation {
        case masked
        case revealed
    }

    let texture: MTLTexture

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        experiment: Experiment,
        trialsRemaining: Int,
        presentation: Presentation
    ) throws {
        let config = experiment.configuration.stimulus
        let display = experiment.configuration.display
        // Core Graphics antialiases glyph edges directly at the final texture
        // resolution, so no separate CPU resampling pass is needed.
        let pixelsPerBox = 128

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
                Float(experiment.grid.columns * pixelsPerBox)
                    * fovWidthMeters / gridWidthMeters
            ))
        )
        let height = max(
            1,
            Int(ceil(
                Float(experiment.grid.rows * pixelsPerBox)
                    * fovHeightMeters / gridHeightMeters
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

            let desiredCapHeight = CGFloat(
                Self.sizeMeters(
                    degrees: config.digitHeightArcmin / 60,
                    distance: config.distanceMeters
                )
            ) * scaleY
            let trialFont = CTFontCreateWithName(config.digitFontName as CFString, 100, nil)
            let trialCapHeight = CTFontGetCapHeight(trialFont)
            guard trialCapHeight > 0 else {
                throw StimulusTextureError.invalidFont(config.digitFontName)
            }
            let font = CTFontCreateWithName(
                config.digitFontName as CFString,
                100 * desiredCapHeight / trialCapHeight,
                nil
            )
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    config.digitRGB.cgColor
            ]

            Self.drawText(
                "Find \(experiment.grid.targetNumber)",
                centeredAt: CGPoint(
                    x: innerMarginRect.midX,
                    y: innerMarginRect.maxY + desiredCapHeight
                ),
                attributes: attributes,
                in: context
            )

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
                    ? "X"
                    : String(experiment.grid.digit(at: index))
                Self.drawText(
                    glyph,
                    centeredAt: center,
                    attributes: attributes,
                    in: context
                )
            }

            Self.drawText(
                String(format: "%03d trials remain", max(0, trialsRemaining)),
                centeredAt: CGPoint(
                    x: innerMarginRect.midX,
                    y: innerMarginRect.minY - desiredCapHeight
                ),
                attributes: attributes,
                in: context
            )

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
        let presentationLabel = presentation == .masked ? "masked" : "revealed"
        texture.label = "Precomposed NumberFinder FOV (\(display.mode.rawValue), \(presentationLabel))"
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
        blitEncoder.label = "SmartFOV123 FOV mipmap generation"
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
        let attributed = CFAttributedStringCreate(
            nil,
            string as CFString,
            attributes as CFDictionary
        )!
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

    private static func applyDisplayModel(
        _ display: DisplayConfiguration,
        to pixels: inout [UInt8]
    ) {
        let peakOpacity = display.peakOpacity
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Float(pixels[index]) / 255
            let green = Float(pixels[index + 1]) / 255
            let blue = Float(pixels[index + 2]) / 255
            let alpha: Float
            switch display.mode {
            case .videoPassthrough:
                alpha = peakOpacity
            case .opticalSeeThroughSimulation:
                alpha = max(red, green, blue) * peakOpacity
            }

            // Compositor Services requires premultiplied-alpha color. For the
            // optical simulation, RGB*peakOpacity is equivalent to normalizing
            // hue by intensity and then premultiplying by intensity*opacity.
            pixels[index] = byte(red * peakOpacity)
            pixels[index + 1] = byte(green * peakOpacity)
            pixels[index + 2] = byte(blue * peakOpacity)
            pixels[index + 3] = byte(alpha)
        }
    }

    private static func byte(_ value: Float) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded())
    }

    private static func sizeMeters(degrees: Float, distance: Float) -> Float {
        2 * distance * tan(degrees * .pi / 360)
    }

    private static func offsetMeters(degrees: Float, distance: Float) -> Float {
        distance * tan(degrees * .pi / 180)
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
            return "The app couldn't create the precomposed FOV drawing context."
        case .textureCreationFailed:
            return "Metal couldn't create the precomposed FOV texture."
        case .mipmapEncodingFailed:
            return "Metal couldn't generate the FOV texture mipmaps."
        }
    }
}
