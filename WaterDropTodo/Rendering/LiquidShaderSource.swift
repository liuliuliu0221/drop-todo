import Foundation

enum LiquidShaderSource {
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct LiquidVertexOutput {
        float4 position [[position]];
    };

    struct LiquidUniforms {
        float2 resolution;
        float time;
        uint dropletCount;
        float threshold;
        float perturbation;
        float colorProgress;
        float padding;
        float surfaceY;
        float surfaceDepth;
        float dropletY;
        float opacity;
        float4 clearBlue;
        float4 deepBlue;
        float4 asphalt;
        float4 progress0To3;
        float4 progress4To7;
        float4 ball0;
        float4 ball1;
        float4 ball2;
        float4 ball3;
        float4 ball4;
        float4 ball5;
        float4 ball6;
        float4 ball7;
    };

    vertex LiquidVertexOutput liquidVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        LiquidVertexOutput output;
        output.position = float4(positions[vertexID], 0.0, 1.0);
        return output;
    }

    float metaballContribution(float2 point, float4 ball) {
        float2 delta = point - ball.xy;
        float2 normalizedDelta = delta / max(ball.zw, float2(0.001));
        return 1.0 / max(dot(normalizedDelta, normalizedDelta), 0.01);
    }

    fragment half4 liquidFragment(
        LiquidVertexOutput input [[stage_in]],
        constant LiquidUniforms &uniforms [[buffer(0)]]
    ) {
        if (uniforms.dropletCount == 0) {
            return half4(0.0);
        }

        float2 point = input.position.xy / max(uniforms.resolution, float2(1.0));
        point.y *= uniforms.resolution.y / max(uniforms.resolution.x, 1.0);

        float field = 1.35 - smoothstep(
            uniforms.surfaceY,
            uniforms.surfaceY + uniforms.surfaceDepth,
            point.y
        );
        float4 balls[8] = {
            uniforms.ball0, uniforms.ball1, uniforms.ball2, uniforms.ball3,
            uniforms.ball4, uniforms.ball5, uniforms.ball6, uniforms.ball7
        };
        for (uint index = 0; index < min(uniforms.dropletCount, 8u); ++index) {
            field += metaballContribution(point, balls[index]);
        }

        float ripple = sin(point.x * 55.0 + uniforms.time * 1.4) * uniforms.perturbation;
        float alpha = smoothstep(
            uniforms.threshold - 0.075,
            uniforms.threshold + 0.075,
            field + ripple
        );

        float progressWeights = 0.0;
        float weightedProgress = 0.0;
        float progresses[8] = {
            uniforms.progress0To3.x, uniforms.progress0To3.y,
            uniforms.progress0To3.z, uniforms.progress0To3.w,
            uniforms.progress4To7.x, uniforms.progress4To7.y,
            uniforms.progress4To7.z, uniforms.progress4To7.w
        };
        for (uint index = 0; index < min(uniforms.dropletCount, 8u); ++index) {
            float contribution = metaballContribution(point, balls[index]);
            progressWeights += contribution;
            weightedProgress += contribution * progresses[index];
        }
        float progress = clamp(
            progressWeights > 0.001 ? weightedProgress / progressWeights : uniforms.colorProgress,
            0.0,
            1.0
        );
        float3 color = progress < 0.7
            ? mix(uniforms.clearBlue.xyz, uniforms.deepBlue.xyz, progress / 0.7)
            : mix(uniforms.deepBlue.xyz, uniforms.asphalt.xyz, (progress - 0.7) / 0.3);
        float highlight = smoothstep(0.15, 0.0, point.y) * 0.16;

        return half4(half3(min(color + highlight, 1.0)), half(alpha * uniforms.opacity));
    }
    """#
}
