import CoreGraphics
import Metal

struct TimeBarTexture {
    let texture: MTLTexture

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        configuration: ExperimentConfiguration
    ) throws {
        let stimulus = configuration.stimulus
        let widthMeters = Self.sizeMeters(
            degrees: stimulus.tileWidthArcmin / 60,
            distance: stimulus.distanceMeters
        ) * Float(stimulus.numberOfTilesHorizontal)
            + Self.sizeMeters(
                degrees: stimulus.tileGutterArcmin / 60,
                distance: stimulus.distanceMeters
            ) * Float(stimulus.numberOfTilesHorizontal - 1)
        let heightMeters = Self.sizeMeters(
            degrees: stimulus.timeBarHeightArcmin / 60,
            distance: stimulus.distanceMeters
        )
        let radiusMeters = Self.sizeMeters(
            degrees: stimulus.timeBarCornerRadiusArcmin / 60,
            distance: stimulus.distanceMeters
        )
        let width = max(2, Int((1024 * abs(stimulus.fovWidthScaleFactor)).rounded()))
        let height = max(
            2,
            Int((1024 * heightMeters / widthMeters * abs(stimulus.fovHeightScaleFactor)).rounded())
        )
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        pixels.withUnsafeMutableBytes { bytes in
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            let color = stimulus.timeBarFillRGB
            context.setFillColor(
                red: CGFloat(color.red),
                green: CGFloat(color.green),
                blue: CGFloat(color.blue),
                alpha: 1
            )
            let radiusX = min(
                CGFloat(radiusMeters / widthMeters) * CGFloat(width),
                CGFloat(width) / 2
            )
            let radiusY = min(
                CGFloat(radiusMeters / heightMeters) * CGFloat(height),
                CGFloat(height) / 2
            )
            context.addPath(
                CGPath(
                    roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                    cornerWidth: radiusX,
                    cornerHeight: radiusY,
                    transform: nil
                )
            )
            context.fillPath()
        }

        StimulusTexture.applyDisplayModel(configuration.display, to: &pixels)
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
        texture.label = "Precomposed SmartFOV123 countdown bar"
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

    private static func sizeMeters(degrees: Float, distance: Float) -> Float {
        2 * distance * tan(degrees * .pi / 360)
    }
}
