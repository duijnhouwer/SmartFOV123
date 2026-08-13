import Accelerate
import CoreGraphics
import CoreText
import Foundation
import Metal

struct StimulusTexture {
    let texture: MTLTexture

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        experiment: Experiment
    ) throws {
        let config = experiment.configuration.stimulus
        let display = experiment.configuration.display
        let supersamplingFactor = 8
        let pixelsPerBox = 64

        let fovWidthMeters = Self.sizeMeters(
            degrees: config.fovWidthDegrees,
            distance: config.distanceMeters
        )
        let fovHeightMeters = Self.sizeMeters(
            degrees: config.fovHeightDegrees,
            distance: config.distanceMeters
        )
        let boxWidthMeters = Self.sizeMeters(
            degrees: config.letterBoxWidthArcmin / 60,
            distance: config.distanceMeters
        )
        let boxHeightMeters = Self.sizeMeters(
            degrees: config.letterBoxHeightArcmin / 60,
            distance: config.distanceMeters
        )

        let gridWidthMeters = boxWidthMeters * Float(experiment.grid.columns)
        let gridHeightMeters = boxHeightMeters * Float(experiment.grid.rows)
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
        let sourceWidth = width * supersamplingFactor
        let sourceHeight = height * supersamplingFactor
        let sourceBytesPerRow = sourceWidth * 4

        var sourcePixels = [UInt8](
            repeating: 0,
            count: sourceBytesPerRow * sourceHeight
        )
        try sourcePixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: sourceWidth,
                height: sourceHeight,
                bitsPerComponent: 8,
                bytesPerRow: sourceBytesPerRow,
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

            let scaleX = CGFloat(sourceWidth) / CGFloat(fovWidthMeters)
            let scaleY = CGFloat(sourceHeight) / CGFloat(fovHeightMeters)
            let fovRect = CGRect(
                x: 0,
                y: 0,
                width: sourceWidth,
                height: sourceHeight
            )
            context.setFillColor(config.fovBackgroundRGB.cgColor)
            context.fill(fovRect)

            let gridDeltaX = Self.offsetMeters(
                degrees: config.letterGridHorizontalDeltaDegrees,
                distance: config.distanceMeters
            )
            let gridDeltaY = Self.offsetMeters(
                degrees: config.letterGridVerticalDeltaDegrees,
                distance: config.distanceMeters
            )
            let gridCenter = CGPoint(
                x: CGFloat(sourceWidth) / 2 + CGFloat(gridDeltaX) * scaleX,
                y: CGFloat(sourceHeight) / 2 + CGFloat(gridDeltaY) * scaleY
            )
            let boxWidth = CGFloat(boxWidthMeters) * scaleX
            let boxHeight = CGFloat(boxHeightMeters) * scaleY
            let gridRect = CGRect(
                x: gridCenter.x - boxWidth * CGFloat(experiment.grid.columns) / 2,
                y: gridCenter.y - boxHeight * CGFloat(experiment.grid.rows) / 2,
                width: boxWidth * CGFloat(experiment.grid.columns),
                height: boxHeight * CGFloat(experiment.grid.rows)
            )

            context.setFillColor(config.letterBoxFillRGB.cgColor)
            context.fill(gridRect)

            let boxStrokeMeters = Self.sizeMeters(
                degrees: config.letterBoxStrokeArcmin / 60,
                distance: config.distanceMeters
            )
            let boxStrokePixels = max(
                0.01,
                CGFloat(boxStrokeMeters) * (scaleX + scaleY) / 2
            )
            context.setStrokeColor(config.letterBoxStrokeRGB.cgColor)
            context.setLineWidth(boxStrokePixels)
            context.setLineCap(.butt)
            for column in 0...experiment.grid.columns {
                let x = gridRect.minX + CGFloat(column) * boxWidth
                context.move(to: CGPoint(x: x, y: gridRect.minY))
                context.addLine(to: CGPoint(x: x, y: gridRect.maxY))
            }
            for row in 0...experiment.grid.rows {
                let y = gridRect.minY + CGFloat(row) * boxHeight
                context.move(to: CGPoint(x: gridRect.minX, y: y))
                context.addLine(to: CGPoint(x: gridRect.maxX, y: y))
            }
            context.strokePath()

            let desiredCapHeight = CGFloat(
                Self.sizeMeters(
                    degrees: config.letterHeightArcmin / 60,
                    distance: config.distanceMeters
                )
            ) * scaleY
            let trialFont = CTFontCreateWithName(config.letterFontName as CFString, 100, nil)
            let trialCapHeight = CTFontGetCapHeight(trialFont)
            guard trialCapHeight > 0 else {
                throw StimulusTextureError.invalidFont(config.letterFontName)
            }
            let font = CTFontCreateWithName(
                config.letterFontName as CFString,
                100 * desiredCapHeight / trialCapHeight,
                nil
            )
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    config.letterRGB.cgColor
            ]

            for index in experiment.grid.letters.indices {
                let row = index / experiment.grid.columns
                let column = index % experiment.grid.columns
                let center = CGPoint(
                    x: gridRect.minX + (CGFloat(column) + 0.5) * boxWidth,
                    y: gridRect.maxY - (CGFloat(row) + 0.5) * boxHeight
                )
                let string = String(experiment.grid.letter(at: index)) as CFString
                let attributed = CFAttributedStringCreate(
                    nil,
                    string,
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

            let fovStrokeMeters = Self.sizeMeters(
                degrees: config.fovBorderStrokeArcmin / 60,
                distance: config.distanceMeters
            )
            let fovStrokePixels = max(
                0.01,
                CGFloat(fovStrokeMeters) * (scaleX + scaleY) / 2
            )
            context.setStrokeColor(config.fovBorderRGB.cgColor)
            context.setLineWidth(fovStrokePixels)
            context.stroke(fovRect.insetBy(dx: fovStrokePixels / 2, dy: fovStrokePixels / 2))
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let scaleError = sourcePixels.withUnsafeMutableBytes { sourceBytes in
            pixels.withUnsafeMutableBytes { destinationBytes in
                var source = vImage_Buffer(
                    data: sourceBytes.baseAddress!,
                    height: vImagePixelCount(sourceHeight),
                    width: vImagePixelCount(sourceWidth),
                    rowBytes: sourceBytesPerRow
                )
                var destination = vImage_Buffer(
                    data: destinationBytes.baseAddress!,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * 4
                )
                return vImageScale_ARGB8888(
                    &source,
                    &destination,
                    nil,
                    vImage_Flags(kvImageHighQualityResampling)
                )
            }
        }
        guard scaleError == kvImageNoError else {
            throw StimulusTextureError.resamplingFailed(scaleError)
        }

        Self.applyDisplayModel(display, to: &pixels)

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
        texture.label = "Precomposed WordFinder FOV (\(display.mode.rawValue))"
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
        blitEncoder.label = "WordFinder FOV mipmap generation"
        blitEncoder.generateMipmaps(for: texture)
        blitEncoder.endEncoding()
        commandBuffer.commit()

        self.texture = texture
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
    var cgColor: CGColor {
        CGColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1)
    }
}

enum StimulusTextureError: LocalizedError {
    case invalidFont(String)
    case contextCreationFailed
    case resamplingFailed(vImage_Error)
    case textureCreationFailed
    case mipmapEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidFont(let name):
            return "The configured font ‘\(name)’ doesn't provide usable uppercase metrics."
        case .contextCreationFailed:
            return "The app couldn't create the precomposed FOV drawing context."
        case .resamplingFailed(let error):
            return "The app couldn't downsample the FOV texture (vImage error \(error))."
        case .textureCreationFailed:
            return "Metal couldn't create the precomposed FOV texture."
        case .mipmapEncodingFailed:
            return "Metal couldn't generate the FOV texture mipmaps."
        }
    }
}
