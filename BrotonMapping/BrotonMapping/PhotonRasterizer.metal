//
//  PhotonRasterizer.metal
//  BrotonMapping
//
//  Created by Michael Kelly on 8/1/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

#include <metal_stdlib>
#include "ShaderStructs.h"
using namespace metal;

typedef struct
{
    float4 position [[position]];
    float3 color;
} PhotonOutVertex;

vertex PhotonOutVertex photonVertexShader(const device PhotonVertex* vertices [[buffer(0)]],
                                          const device Uniforms& uniforms [[buffer(1)]],
                                          uint vid [[vertex_id]])
{
    matrix_float4x4 mvp = uniforms.projectionMatrix * uniforms.modelViewMatrix;
    PhotonOutVertex v;
    v.position = mvp * vertices[vid].position;
    v.color = vertices[vid].color;
    return v;
}

fragment float4 photonFragmentShader(PhotonOutVertex in [[stage_in]])
{
    return float4(in.color, 1.0);
}



