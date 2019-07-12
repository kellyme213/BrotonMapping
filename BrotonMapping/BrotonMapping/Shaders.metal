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
    float4 position;
    float3 normal;
    int materialNum;
} VertexIn;

typedef struct
{
    float4 transformedPosition [[position]];
    float4 absolutePosition;
    float3 normal;
    int materialNum;
} VertexOut;

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

typedef struct
{
    float3 position;
    float3 direction;
    float4 color;
} Light;


vertex VertexOut vertexShader(const device VertexIn* vertArray [[buffer(0)]],
                              const device Uniforms& uniforms [[buffer(1)]],
                              uint vid [[vertex_id]])
{
    matrix_float4x4 mvp = uniforms.projectionMatrix * uniforms.modelViewMatrix;
    VertexOut v;
    v.transformedPosition = mvp * vertArray[vid].position;
    v.absolutePosition = vertArray[vid].position;
    v.normal = vertArray[vid].normal;
    v.materialNum = vertArray[vid].materialNum;
    return v;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               const device array<Material, 8>& materials [[buffer(0)]],
                               const device Light& light [[buffer(8)]])
{
    
    float3 dirToLight = in.absolutePosition.xyz - light.position;
    float3 lightNorm = normalize(dirToLight);
    float4 materialColor = materials[in.materialNum].color;
    float4 finalColor = max(0.0f, dot(in.normal, light.direction)) * light.color * materialColor + float4(0.2, 0.2, 0.2, 0.0);
    
    return finalColor;
}


