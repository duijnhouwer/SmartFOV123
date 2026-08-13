#include <metal_stdlib>
using namespace metal;

struct PrimitiveUniforms {
    float4x4 clipFromDevice;
    float4 fillColor;
    float4 strokeColor;
    float2 centerMeters;
    float2 halfSizeMeters;
    float2 strokeMeters;
    float2 uvOrigin;
    float2 uvSize;
    float distanceMeters;
    uint mode;
    uint trackingAreaRenderValue;
    uint edgeAntialiasMask;
};

struct VertexOut {
    float4 position [[position]];
    float2 localPosition;
    float2 uv;
};

struct TrackingFragmentOut {
    float4 color [[color(0)]];
    uint16_t trackingAreaRenderValue [[color(1)]];
};

vertex VertexOut stimulusVertex(
    uint vertexID [[vertex_id]],
    constant PrimitiveUniforms &uniforms [[buffer(0)]])
{
    constexpr float2 corners[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2(-1.0,  1.0), float2( 1.0, -1.0), float2( 1.0,  1.0)
    };

    float2 corner = corners[vertexID];
    float2 deviceXY = uniforms.centerMeters + corner * uniforms.halfSizeMeters;

    VertexOut out;
    out.position = uniforms.clipFromDevice * float4(
        deviceXY,
        -uniforms.distanceMeters,
        1.0
    );
    out.localPosition = corner;
    out.uv = uniforms.uvOrigin + ((corner + 1.0) * 0.5) * uniforms.uvSize;
    return out;
}

float4 primitiveColor(
    VertexOut in,
    constant PrimitiveUniforms &uniforms,
    texture2d<float> glyphAtlas)
{
    if (uniforms.mode == 1) {
        constexpr sampler glyphSampler(
            coord::normalized,
            address::clamp_to_edge,
            mag_filter::linear,
            min_filter::linear,
            mip_filter::linear
        );
        float glyphAlpha = glyphAtlas.sample(glyphSampler, in.uv).r;
        if (glyphAlpha < 0.001) {
            discard_fragment();
        }
        return float4(uniforms.fillColor.rgb, uniforms.fillColor.a * glyphAlpha);
    }

    float2 distanceFromEdge = (1.0 - abs(in.localPosition)) * uniforms.halfSizeMeters;
    float signedDistanceFromStroke = min(
        distanceFromEdge.x - uniforms.strokeMeters.x,
        distanceFromEdge.y - uniforms.strokeMeters.y
    );
    float antialiasWidth = max(0.5 * fwidth(signedDistanceFromStroke), 1e-7);
    float fillCoverage = smoothstep(
        -antialiasWidth,
        antialiasWidth,
        signedDistanceFromStroke
    );
    float4 color = mix(uniforms.strokeColor, uniforms.fillColor, fillCoverage);

    float leftDistance = (in.localPosition.x + 1.0) * uniforms.halfSizeMeters.x;
    float rightDistance = (1.0 - in.localPosition.x) * uniforms.halfSizeMeters.x;
    float bottomDistance = (in.localPosition.y + 1.0) * uniforms.halfSizeMeters.y;
    float topDistance = (1.0 - in.localPosition.y) * uniforms.halfSizeMeters.y;
    float outerCoverage = 1.0;
    if ((uniforms.edgeAntialiasMask & 0x1u) != 0u) {
        outerCoverage *= smoothstep(0.0, max(fwidth(leftDistance), 1e-7), leftDistance);
    }
    if ((uniforms.edgeAntialiasMask & 0x2u) != 0u) {
        outerCoverage *= smoothstep(0.0, max(fwidth(rightDistance), 1e-7), rightDistance);
    }
    if ((uniforms.edgeAntialiasMask & 0x4u) != 0u) {
        outerCoverage *= smoothstep(0.0, max(fwidth(bottomDistance), 1e-7), bottomDistance);
    }
    if ((uniforms.edgeAntialiasMask & 0x8u) != 0u) {
        outerCoverage *= smoothstep(0.0, max(fwidth(topDistance), 1e-7), topDistance);
    }
    color.a *= outerCoverage;
    return color;
}

fragment float4 stimulusFragment(
    VertexOut in [[stage_in]],
    constant PrimitiveUniforms &uniforms [[buffer(0)]],
    texture2d<float> glyphAtlas [[texture(0)]])
{
    return primitiveColor(in, uniforms, glyphAtlas);
}

fragment TrackingFragmentOut stimulusTrackingFragment(
    VertexOut in [[stage_in]],
    constant PrimitiveUniforms &uniforms [[buffer(0)]],
    texture2d<float> glyphAtlas [[texture(0)]])
{
    return TrackingFragmentOut {
        primitiveColor(in, uniforms, glyphAtlas),
        uint16_t(uniforms.trackingAreaRenderValue)
    };
}
