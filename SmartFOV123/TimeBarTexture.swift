import Metal

struct TimeBarTexture {
    let texture: MTLTexture

    init(device: MTLDevice, configuration: ExperimentConfiguration) throws {
        let color = configuration.stimulus.timeBarFillRGB
        func byte(_ value: Float) -> UInt8 {
            UInt8(min(255, max(0, Int((value * 255).rounded()))))
        }
        var pixel = [byte(color.red), byte(color.green), byte(color.blue), 255]
        StimulusTexture.applyDisplayModel(configuration.display, to: &pixel)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw StimulusTextureError.textureCreationFailed
        }
        pixel.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: 4
            )
        }
        self.texture = texture
    }
}
