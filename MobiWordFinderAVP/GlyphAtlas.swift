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

    init(device: MTLDevice, fontName: String) throws {
        // The atlas stores signed distance instead of coverage. The fragment
        // shader reconstructs coverage at the drawable's actual pixel scale,
        // avoiding the softness caused by selecting a prefiltered mip level.
        // Two source samples per eventual display pixel are already ample for
        // an SDF edge; using the former 512-pixel cell made debug launches wait
        // roughly twelve seconds for data the shader never needed.
        let cellSize = 256
        let columns = 8
        let rows = 4
        let atlasWidth = columns * cellSize
        let atlasHeight = rows * cellSize
        let desiredCapHeight = CGFloat(192)
        let distanceFieldSpread = 24.0

        let trialFont = CTFontCreateWithName(fontName as CFString, 100, nil)
        let trialCapHeight = CTFontGetCapHeight(trialFont)
        guard trialCapHeight > 0 else {
            throw GlyphAtlasError.invalidFont(fontName)
        }
        let font = CTFontCreateWithName(
            fontName as CFString,
            100 * desiredCapHeight / trialCapHeight,
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
            var coveragePixels = [UInt8](repeating: 0, count: cellSize * cellSize * 4)
            try coveragePixels.withUnsafeMutableBytes { rawBuffer in
                guard let context = CGContext(
                    data: rawBuffer.baseAddress,
                    width: cellSize,
                    height: cellSize,
                    bitsPerComponent: 8,
                    bytesPerRow: cellSize * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
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
                let baselineX = (CGFloat(cellSize) - width) / 2
                let baselineY = (CGFloat(cellSize) - ascent - descent) / 2 + descent

                context.textPosition = CGPoint(x: baselineX, y: baselineY)
                CTLineDraw(line, context)
            }

            let distanceField = SignedDistanceField.make(
                fromRGBA: coveragePixels,
                width: cellSize,
                height: cellSize,
                spread: distanceFieldSpread
            )
            let column = index % columns
            let row = index / columns
            for y in 0..<cellSize {
                let atlasStart = (row * cellSize + y) * atlasWidth + column * cellSize
                let cellStart = y * cellSize
                atlasPixels.replaceSubrange(
                    atlasStart..<(atlasStart + cellSize),
                    with: distanceField[cellStart..<(cellStart + cellSize)]
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
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw GlyphAtlasError.textureCreationFailed
        }
        texture.label = "WordFinder uppercase signed-distance glyph atlas (\(fontName))"
        atlasPixels.withUnsafeBytes { rawBuffer in
            texture.replace(
                region: MTLRegionMake2D(0, 0, atlasWidth, atlasHeight),
                mipmapLevel: 0,
                withBytes: rawBuffer.baseAddress!,
                bytesPerRow: atlasWidth
            )
        }

        self.texture = texture
        self.glyphs = glyphs
        self.quadScaleForConfiguredCapHeight = Float(cellSize) / Float(desiredCapHeight)
    }
}

private enum SignedDistanceField {
    static func make(
        fromRGBA pixels: [UInt8],
        width: Int,
        height: Int,
        spread: Double
    ) -> [UInt8] {
        let pixelCount = width * height
        var inside = [Bool](repeating: false, count: pixelCount)
        for index in 0..<pixelCount {
            inside[index] = pixels[index * 4 + 3] >= 128
        }

        let distanceToInside = squaredDistance(to: inside, width: width, height: height)
        let distanceToOutside = squaredDistance(
            to: inside.map { !$0 },
            width: width,
            height: height
        )

        var result = [UInt8](repeating: 0, count: pixelCount)
        for index in 0..<pixelCount {
            let signedDistance = sqrt(distanceToOutside[index]) - sqrt(distanceToInside[index])
            let normalized = min(max(0.5 + signedDistance / (2 * spread), 0), 1)
            result[index] = UInt8((normalized * 255).rounded())
        }
        return result
    }

    // Exact squared Euclidean distance transform, using the separable
    // lower-envelope algorithm by Felzenszwalb and Huttenlocher.
    private static func squaredDistance(
        to features: [Bool],
        width: Int,
        height: Int
    ) -> [Double] {
        let infinity = 1.0e12
        let maximumDimension = max(width, height)
        var source = [Double](repeating: 0, count: maximumDimension)
        var transformed = [Double](repeating: 0, count: maximumDimension)
        var locations = [Int](repeating: 0, count: maximumDimension)
        var boundaries = [Double](repeating: 0, count: maximumDimension + 1)
        var rowPass = [Double](repeating: 0, count: width * height)
        var result = [Double](repeating: 0, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                source[x] = features[y * width + x] ? 0 : infinity
            }
            transformLine(
                source: source,
                count: width,
                result: &transformed,
                locations: &locations,
                boundaries: &boundaries
            )
            for x in 0..<width {
                rowPass[y * width + x] = transformed[x]
            }
        }

        for x in 0..<width {
            for y in 0..<height {
                source[y] = rowPass[y * width + x]
            }
            transformLine(
                source: source,
                count: height,
                result: &transformed,
                locations: &locations,
                boundaries: &boundaries
            )
            for y in 0..<height {
                result[y * width + x] = transformed[y]
            }
        }
        return result
    }

    private static func transformLine(
        source: [Double],
        count: Int,
        result: inout [Double],
        locations: inout [Int],
        boundaries: inout [Double]
    ) {
        var envelopeIndex = 0
        locations[0] = 0
        boundaries[0] = -.infinity
        boundaries[1] = .infinity

        if count > 1 {
            for q in 1..<count {
                var previous = locations[envelopeIndex]
                var intersection = (
                    (source[q] + Double(q * q))
                        - (source[previous] + Double(previous * previous))
                ) / Double(2 * q - 2 * previous)

                while intersection <= boundaries[envelopeIndex] {
                    envelopeIndex -= 1
                    previous = locations[envelopeIndex]
                    intersection = (
                        (source[q] + Double(q * q))
                            - (source[previous] + Double(previous * previous))
                    ) / Double(2 * q - 2 * previous)
                }

                envelopeIndex += 1
                locations[envelopeIndex] = q
                boundaries[envelopeIndex] = intersection
                boundaries[envelopeIndex + 1] = .infinity
            }
        }

        envelopeIndex = 0
        for q in 0..<count {
            while boundaries[envelopeIndex + 1] < Double(q) {
                envelopeIndex += 1
            }
            let offset = q - locations[envelopeIndex]
            result[q] = Double(offset * offset) + source[locations[envelopeIndex]]
        }
    }
}

enum GlyphAtlasError: LocalizedError {
    case invalidFont(String)
    case contextCreationFailed
    case textureCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidFont(let name):
            return "The configured font ‘\(name)’ doesn't provide usable uppercase metrics."
        case .contextCreationFailed:
            return "The app couldn't create the letter-atlas drawing context."
        case .textureCreationFailed:
            return "Metal couldn't create the letter-atlas texture."
        }
    }
}
