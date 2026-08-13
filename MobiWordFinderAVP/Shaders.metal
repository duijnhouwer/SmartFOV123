#include <metal_stdlib>
using namespace metal;

struct SquareUniforms {
    float4x4 clipFromDevice;
    float4 color;
    float2 halfSizeMeters;
    float distanceMeters;
    float padding;
};

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut stimulusVertex(
    uint vertexID [[vertex_id]],
    constant SquareUniforms &uniforms [[buffer(0)]])
{
    constexpr float2 corners[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2(-1.0,  1.0), float2( 1.0, -1.0), float2( 1.0,  1.0)
    };

    float2 corner = corners[vertexID];
    VertexOut out;
    float4 devicePosition = float4(
        corner * uniforms.halfSizeMeters,
        -uniforms.distanceMeters,
        1.0
    );
    out.position = uniforms.clipFromDevice * devicePosition;
    return out;
}

fragment float4 stimulusFragment(
    VertexOut in [[stage_in]],
    constant SquareUniforms &uniforms [[buffer(0)]])
{
    return uniforms.color;
}
