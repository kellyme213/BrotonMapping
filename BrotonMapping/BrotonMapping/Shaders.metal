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

constant int8_t DIRECTIONAL_LIGHT = 0;
constant int8_t SPOT_LIGHT = 1;

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
    float coneAngle;
    int8_t lightType;
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
    float3 lightToPoint = in.absolutePosition.xyz - light.position;
    float3 lightNorm = normalize(lightToPoint);
    
    float degree = dot(lightNorm, normalize(light.direction));
    
    bool shouldBeLitBySpotLight = (degree >= 0.0f) && ((1.0f - degree) <= (light.coneAngle));
    
    bool isSpotLight = (light.lightType == SPOT_LIGHT);
    bool isDirectionalLight = (light.lightType == DIRECTIONAL_LIGHT);

    float spotlightConstant = isSpotLight * shouldBeLitBySpotLight * max(0.0f, -dot(normalize(in.normal), normalize(light.direction)));
    float directionalLightConstant = isDirectionalLight * max(0.0f, -dot(normalize(in.normal), normalize(light.direction)));
    
    float4 ambientLight = float4(0.1f, 0.1f, 0.1f, 0.0f);
    float4 spotLightColor = spotlightConstant * light.color;
    float4 directionalColor = directionalLightConstant * light.color;

    float4 materialColor = materials[in.materialNum].color;
    float4 finalColor = ((directionalColor + spotLightColor) * materialColor) + ambientLight;
    
    return finalColor;
}


