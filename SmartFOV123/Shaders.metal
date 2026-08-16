#include <metal_stdlib>
using namespace metal;

struct StimulusUniforms {
    float4x4 clipFromDevice;
    float2 centerMeters;
    float2 halfSizeMeters;
    float distanceMeters;
    float uvMaxX;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct VisualFragmentOut {
    float4 color [[color(0)]];
    float depth [[depth(any)]];
};

vertex VertexOut stimulusVertex(
    uint vertexID [[vertex_id]],
    constant StimulusUniforms &uniforms [[buffer(0)]])
{
    constexpr float2 corners[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2(-1.0,  1.0), float2( 1.0, -1.0), float2( 1.0,  1.0)
    };

    float2 deviceXY = uniforms.centerMeters
        + corners[vertexID] * uniforms.halfSizeMeters;
    VertexOut out;
    out.position = uniforms.clipFromDevice * float4(
        deviceXY,
        -uniforms.distanceMeters,
        1.0
    );
    // Quartz bitmap rows and Metal texture coordinates use opposite vertical
    // conventions, so invert V while mapping the completed stimulus texture.
    out.uv = float2(corners[vertexID].x, -corners[vertexID].y) * 0.5 + 0.5;
    out.uv.x *= uniforms.uvMaxX;
    return out;
}

float4 sampleStimulus(VertexOut in, texture2d<float> stimulusTexture)
{
    constexpr sampler stimulusSampler(
        coord::normalized,
        address::clamp_to_edge,
        mag_filter::linear,
        min_filter::linear,
        mip_filter::linear
    );
    return stimulusTexture.sample(stimulusSampler, in.uv);
}

float compositorDepth(VertexOut in, float alpha)
{
    // Mixed Compositor Services content requires reverse-Z depth 0 wherever
    // alpha is zero; otherwise transparent pixels can affect passthrough.
    return alpha > 0.0001 ? in.position.z : 0.0;
}

fragment VisualFragmentOut stimulusFragment(
    VertexOut in [[stage_in]],
    texture2d<float> stimulusTexture [[texture(0)]])
{
    float4 color = sampleStimulus(in, stimulusTexture);
    return VisualFragmentOut {
        color,
        compositorDepth(in, color.a)
    };
}
