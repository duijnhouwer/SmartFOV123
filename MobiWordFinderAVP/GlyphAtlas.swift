import Accelerate
import CoreGraphics
import CoreText
import Foundation
import Metal

struct GlyphAtlas {
    struct Glyph {
        let uvOrigin: SIMD2<Float>
        let uvSize: SIMD2<Float>
    }

    let texture: MTLTexture
    let glyphs: [UInt8: Glyph]
    let quadScaleForConfiguredCapHeight: Float

    init(device: MTLDevice, commandQueue: MTLCommandQueue, fontName: String) throws {
        // Rasterize each glyph at 8 times its final linear resolution, then
        // reduce it once with Accelerate's high-quality area resampler. This
        // gives the small bitmap atlas stable antialiased coverage without the
        // expensive runtime distance transform required by an SDF atlas.
        let cellSize = 64
        let supersamplingFactor = 8
        let supersampledCellSize = cellSize * supersamplingFactor
        let columns = 8
        let rows = 4
        let atlasWidth = columns * cellSize
        let atlasHeight = rows * cellSize
        let desiredCapHeight = CGFloat(48)
        let supersampledCapHeight = desiredCapHeight * CGFloat(supersamplingFactor)

        let trialFont = CTFontCreateWithName(fontName as CFString, 100, nil)
        let trialCapHeight = CTFontGetCapHeight(trialFont)
        guard trialCapHeight > 0 else {
            throw GlyphAtlasError.invalidFont(fontName)
        }
        let font = CTFontCreateWithName(
            fontName as CFString,
            100 * supersampledCapHeight / trialCapHeight,
            nil
        )
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                red: 1,
                green: 1,
                blue: 1,
                alpha: 1
            )
        ]

        var atlasPixels = [UInt8](repeating: 0, count: atlasWidth * atlasHeight)
        var glyphs: [UInt8: Glyph] = [:]

        for (index, ascii) in (UInt8(65)...UInt8(90)).enumerated() {
            var supersampledCoverage = [UInt8](
                repeating: 0,
                count: supersampledCellSize * supersampledCellSize
            )
            try supersampledCoverage.withUnsafeMutableBytes { rawBuffer in
                guard let context = CGContext(
                    data: rawBuffer.baseAddress,
                    width: supersampledCellSize,
                    height: supersampledCellSize,
                    bitsPerComponent: 8,
                    bytesPerRow: supersampledCellSize,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                ) else {
                    throw GlyphAtlasError.contextCreationFailed
                }

                context.setAllowsAntialiasing(true)
                context.setShouldAntialias(true)
                context.setAllowsFontSmoothing(true)
                context.setShouldSmoothFonts(true)

                let string = String(UnicodeScalar(ascii)) as CFString
                let attributedString = CFAttributedStringCreate(
                    nil,
                    string,
                    attributes as CFDictionary
                )!
                let line = CTLineCreateWithAttributedString(attributedString)

                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                var leading: CGFloat = 0
                let width = CGFloat(
                    CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
                )
                let baselineX = (CGFloat(supersampledCellSize) - width) / 2
                let baselineY = (
                    CGFloat(supersampledCellSize) - ascent - descent
                ) / 2 + descent

                context.textPosition = CGPoint(x: baselineX, y: baselineY)
                CTLineDraw(line, context)
            }

            var coveragePixels = [UInt8](repeating: 0, count: cellSize * cellSize)
            let scaleError = supersampledCoverage.withUnsafeMutableBytes { sourceBytes in
                coveragePixels.withUnsafeMutableBytes { destinationBytes in
                    var source = vImage_Buffer(
                        data: sourceBytes.baseAddress!,
                        height: vImagePixelCount(supersampledCellSize),
                        width: vImagePixelCount(supersampledCellSize),
                        rowBytes: supersampledCellSize
                    )
                    var destination = vImage_Buffer(
                        data: destinationBytes.baseAddress!,
                        height: vImagePixelCount(cellSize),
                        width: vImagePixelCount(cellSize),
                        rowBytes: cellSize
                    )
                    return vImageScale_Planar8(
                        &source,
                        &destination,
                        nil,
                        vImage_Flags(kvImageHighQualityResampling)
                    )
                }
            }
            guard scaleError == kvImageNoError else {
                throw GlyphAtlasError.resamplingFailed(scaleError)
            }

            let column = index % columns
            let row = index / columns
            for y in 0..<cellSize {
                let atlasStart = (row * cellSize + y) * atlasWidth + column * cellSize
                let cellStart = y * cellSize
                atlasPixels.replaceSubrange(
                    atlasStart..<(atlasStart + cellSize),
                    with: coveragePixels[cellStart..<(cellStart + cellSize)]
                )
            }

            // Quartz's bitmap rows and Metal's normalized texture coordinates
            // have opposite vertical conventions. Start at the cell's lower
            // texture edge and use a negative V extent so glyphs render upright.
            glyphs[ascii] = Glyph(
                uvOrigin: SIMD2(
                    Float(column * cellSize) / Float(atlasWidth),
                    Float((row + 1) * cellSize) / Float(atlasHeight)
                ),
                uvSize: SIMD2(
                    Float(cellSize) / Float(atlasWidth),
                    -Float(cellSize) / Float(atlasHeight)
                )
            )
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: true
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw GlyphAtlasError.textureCreationFailed
        }
        texture.label = "WordFinder 8x-supersampled uppercase glyph atlas (\(fontName))"
        atlasPixels.withUnsafeBytes { rawBuffer in
            texture.replace(
                region: MTLRegionMake2D(0, 0, atlasWidth, atlasHeight),
                mipmapLevel: 0,
                withBytes: rawBuffer.baseAddress!,
                bytesPerRow: atlasWidth
            )
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw GlyphAtlasError.mipmapEncodingFailed
        }
        blitEncoder.label = "WordFinder glyph-atlas mipmap generation"
        blitEncoder.generateMipmaps(for: texture)
        blitEncoder.endEncoding()
        commandBuffer.commit()

        self.texture = texture
        self.glyphs = glyphs
        self.quadScaleForConfiguredCapHeight = Float(cellSize) / Float(desiredCapHeight)
    }
}

enum GlyphAtlasError: LocalizedError {
    case invalidFont(String)
    case contextCreationFailed
    case resamplingFailed(vImage_Error)
    case mipmapEncodingFailed
    case textureCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidFont(let name):
            return "The configured font ‘\(name)’ doesn't provide usable uppercase metrics."
        case .contextCreationFailed:
            return "The app couldn't create the letter-atlas drawing context."
        case .resamplingFailed(let error):
            return "The app couldn't downsample the letter atlas (vImage error \(error))."
        case .mipmapEncodingFailed:
            return "Metal couldn't generate the letter-atlas mipmaps."
        case .textureCreationFailed:
            return "Metal couldn't create the letter-atlas texture."
        }
    }
}
