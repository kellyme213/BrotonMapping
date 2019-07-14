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
    float4 kAmbient;
    float4 kDiffuse;
    float4 kSpecular;
    float shininess;
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

typedef struct
{
    float3 cameraPosition;
    float3 cameraDirection;
    int8_t numLights;
    float4 ambientLight;
} FragmentUniforms;


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
                               const device FragmentUniforms& fragmentUniforms [[buffer(0)]],
                               const device array<Material, 8>& materials [[buffer(1)]],
                               const device array<Light, 8>& lights [[buffer(9)]])
{
    float4 diffuseMaterialColor = materials[in.materialNum].kDiffuse;
    float4 specularMaterialColor = materials[in.materialNum].kSpecular;
    float4 ambientMaterialColor = materials[in.materialNum].kAmbient;
    float shininess = materials[in.materialNum].shininess;
    
    float4 diffuseLightColor = float4(0.0, 0.0, 0.0, 1.0);
    float4 specularLightColor = float4(0.0, 0.0, 0.0, 1.0);
    for (int x = 0; x < fragmentUniforms.numLights; x++)
    {
    
        Light light = lights[x];
        float3 lightToPoint = in.absolutePosition.xyz - light.position;
        float3 lightNorm = normalize(lightToPoint);
        
        float degree = dot(lightNorm, normalize(light.direction));
        
        bool shouldBeLitBySpotLight = (degree >= 0.0f) && ((1.0f - degree) <= (light.coneAngle));
        
        bool isSpotLight = (light.lightType == SPOT_LIGHT);
        bool isDirectionalLight = (light.lightType == DIRECTIONAL_LIGHT);

        
        float diffuseConstant = max(0.0f, -dot(normalize(in.normal), normalize(light.direction)));
        float specularConstant = pow(max(0.0f, dot(reflect(-lightNorm, in.normal), -fragmentUniforms.cameraDirection)), shininess);
        
        float spotlightConstant = isSpotLight * shouldBeLitBySpotLight;
        float directionalLightConstant = isDirectionalLight;
        
        float lightConstant = spotlightConstant + directionalLightConstant;
        
        
        //float4 spotLightColor = spotlightConstant * light.color;
        //float4 directionalColor = directionalLightConstant * light.color;

        //diffuseLightColor += ((directionalColor + spotLightColor));
        
        
        diffuseLightColor += lightConstant * diffuseConstant * light.color;
        specularLightColor += lightConstant * specularConstant * light.color;
    }
    


    float4 finalColor = diffuseLightColor * diffuseMaterialColor +
                        specularLightColor * specularMaterialColor +
                        fragmentUniforms.ambientLight * ambientMaterialColor;
    return finalColor;
}


