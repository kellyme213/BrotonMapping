//
//  shader.metal
//  BrotonMapping
//
//  Created by Michael Kelly on 7/9/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

#include <metal_stdlib>
#include "ShaderStructs.h"

using namespace metal;



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
        bool isPointLight = (light.lightType == POINT_LIGHT);
        
        float diffuseConstant = max(0.0f, -dot(normalize(in.normal), normalize(light.direction)));
        float specularConstant = pow(max(0.0f, dot(reflect(-lightNorm, normalize(in.normal)), fragmentUniforms.cameraDirection)), shininess);
        float pointLightConstant = max(0.0f, -dot(normalize(in.normal), lightNorm));
        
        
        diffuseConstant = ((!isPointLight) * diffuseConstant) + (isPointLight * pointLightConstant);
        
        float spotlightConstant = isSpotLight * shouldBeLitBySpotLight;
        float directionalLightConstant = isDirectionalLight;
        //float pointLightConstant = isPointLight;
        
        float lightConstant = spotlightConstant + directionalLightConstant + (isPointLight);
        
        
        diffuseLightColor += lightConstant * diffuseConstant * light.color;
        specularLightColor += lightConstant * specularConstant * light.color;
    }
    


    float4 finalColor = diffuseLightColor * diffuseMaterialColor +
                        specularLightColor * specularMaterialColor +
                        fragmentUniforms.ambientLight * ambientMaterialColor;
    return finalColor;
}


