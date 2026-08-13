#include <metal_stdlib>
using namespace metal;

struct SquareUniforms {
    float halfWidth;
    float halfHeight;
    float red;
    float green;
    float blue;
    float alpha;
};

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut eyeTestVertex(
    uint vertexID [[vertex_id]],
    constant SquareUniforms &uniforms [[buffer(0)]])
{
    constexpr float2 corners[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2(-1.0,  1.0), float2( 1.0, -1.0), float2( 1.0,  1.0)
    };

    float2 corner = corners[vertexID];
    VertexOut out;
    out.position = float4(
        corner.x * uniforms.halfWidth,
        corner.y * uniforms.halfHeight,
        0.5,
        1.0
    );
    return out;
}

fragment float4 eyeTestFragment(
    VertexOut in [[stage_in]],
    constant SquareUniforms &uniforms [[buffer(0)]])
{
    return float4(uniforms.red, uniforms.green, uniforms.blue, uniforms.alpha);
}
