//
//  shader.metal
//  BrotonMapping
//
//  Created by Michael Kelly on 7/9/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

typedef struct
{
    float4 position [[position]];
    float3 normal;
    int materialNum;
} Vertex;

typedef struct
{
    matrix_float4x4 modelViewMatrix;
    matrix_float4x4 projectionMatrix;
} Uniforms;

typedef struct
{
    float4 color;
    float diffuse;
} Material;


vertex Vertex vertexShader(const device Vertex* vertArray [[buffer(0)]],
                              const device Uniforms& uniforms [[buffer(1)]],
                              uint vid [[vertex_id]])
{
    matrix_float4x4 mvp = uniforms.projectionMatrix * uniforms.modelViewMatrix;
    Vertex v;
    v.position = mvp * vertArray[vid].position;
    v.normal = (mvp * float4(vertArray[vid].normal, 0.0)).xyz;
    v.materialNum = vertArray[vid].materialNum;
    return v;
}

fragment float4 fragmentShader(Vertex in [[stage_in]],
                               const device array<Material, 8>& materials [[buffer(0)]])
{
    return materials[in.materialNum].color;
}


