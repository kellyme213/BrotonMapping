//
//  Compute.metal
//  BrotonMapping
//
//  Created by Michael Kelly on 7/14/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

#include <metal_stdlib>
#include "ShaderStructs.h"


using namespace metal;

template<typename T>
inline T interpolateVertexAttribute(device T *attributes, Intersection intersection) {
    float3 uvw;
    uvw.xy = intersection.coordinates;
    uvw.z = 1.0f - uvw.x - uvw.y;
    unsigned int triangleIndex = intersection.primitiveIndex;
    T T0 = attributes[triangleIndex * 3 + 0];
    T T1 = attributes[triangleIndex * 3 + 1];
    T T2 = attributes[triangleIndex * 3 + 2];
    return uvw.x * T0 + uvw.y * T1 + uvw.z * T2;
}




inline void sampleAreaLight(constant Light & light,
                            float2 u,
                            float3 position,
                            thread float3 & lightDirection,
                            thread float3 & lightColor,
                            thread float & lightDistance)
{
    u = u * 2.0f - 1.0f;
    float3 samplePosition = light.position +
    light.right * u.x +
    light.up * u.y;
    lightDirection = samplePosition - position;
    lightDistance = length(lightDirection);
    float inverseLightDistance = 1.0f / max(lightDistance, 1e-3f);
    lightDirection *= inverseLightDistance;
    lightColor = light.color.xyz;
    //lightColor *= (inverseLightDistance * inverseLightDistance);
    lightColor *= max(dot(-lightDirection, light.direction), 0.0f);
    
}






kernel void
rayKernel(constant RayKernelUniforms&    uniforms    [[buffer(0)]],
          device   Ray*                  rays        [[buffer(1)]],
          texture2d<float, access::read> randTex     [[texture(0)]],
          texture2d<float, access::write> dstTex     [[texture(1)]],
          texture2d<float, access::write> dstTex2     [[texture(2)]],
          uint2                          tid         [[thread_position_in_grid]]) {
    
    
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        // Compute linear ray index from 2D position
        unsigned int rayIdx = tid.y * uniforms.width + tid.x;
        
        // Ray we will produce
        device Ray & ray = rays[rayIdx];
        
        // Pixel coordinates for this thread
        float2 pixel = (float2)tid;

        
        float2 rand = randTex.read(tid).xy;
        
        pixel += (rand * 2.0f - 1.0f);
        
        // Map pixel coordinates to -1..1
        float2 uv = (float2)pixel / float2(uniforms.width, uniforms.height);
        uv = uv * 2.0f - 1.0f;
        
        

        
        
        // Rays start at the camera position
        ray.origin = uniforms.position;
        
        // Map normalized pixel coordinates into camera's coordinate system
        ray.direction = normalize(1.0 * uv.x * uniforms.right +
                                  1.0 * uv.y * uniforms.up +
                                  uniforms.forward);
        // The camera emits primary rays
        ray.mask = RAY_MASK_PRIMARY;
        
        // Don't limit intersection distance
        ray.maxDistance = INFINITY;
        
        // Start with a fully white color. Each bounce will scale the color as light
        // is absorbed into surfaces.
        ray.color = float3(1.0f, 1.0f, 1.0f);
        
        dstTex.write(float4(0.0f, 0.0f, 0.0f, 1.0f), tid);
        dstTex2.write(float4(0.0f, 0.0f, 0.0f, 1.0f), tid);
    }
}


kernel void
shadeKernel(constant RayKernelUniforms&     uniforms      [[buffer(0)]],
            device   Ray*                   rays          [[buffer(1)]],
            device   Intersection*          intersections [[buffer(2)]],
            device   VertexIn*              vertices      [[buffer(3)]],
            device   Material*              materials     [[buffer(4)]],
            device   float*                 energy        [[buffer(5)]],
            device   Ray*                   shadowRays    [[buffer(6)]],
            constant array<Light, 8>&       lights        [[buffer(7)]],
            //texture2d<float, access::write> dstTex        [[texture(0)]],
            texture2d<float, access::read>  randTex       [[texture(0)]],
            uint2                           tid           [[thread_position_in_grid]])
{
    //dstTex.write(float4(1.0, 0.0, 0.0, 1.0), tid);

   if (tid.x < uniforms.width && tid.y < uniforms.height) {
       unsigned int rayIdx = tid.y * uniforms.width + tid.x;
        
       device Ray & ray = rays[rayIdx];
       device Intersection & intersection = intersections[rayIdx];
       
       if (ray.maxDistance >= 0.0f && intersection.distance >= 0.0f)
       {
       
       VertexIn v0 = vertices[3 * intersection.primitiveIndex + 0];
       VertexIn v1 = vertices[3 * intersection.primitiveIndex + 1];
       VertexIn v2 = vertices[3 * intersection.primitiveIndex + 2];
       float3 uvw;
       uvw.x = intersection.coordinates.x;
       uvw.y = intersection.coordinates.y;
       uvw.z = 1.0 - uvw.x - uvw.y;
       
       float3 surfaceNormal = normalize(uvw.x * v0.normal +
                                        uvw.y * v1.normal +
                                        uvw.z * v2.normal);
       float3 intersectionPoint = ray.origin + ray.direction * intersection.distance;
       
       Material material = materials[v0.materialNum];
       float4 rand = randTex.read(tid);

       for (int x = 0; x < uniforms.numLights; x++) {
           
           float3 lightDirection;
           float3 lightColor;
           float lightDistance;
           
           sampleAreaLight(lights[x], rand.yz, intersectionPoint, lightDirection,
                           lightColor, lightDistance);
           lightColor *= max(dot(surfaceNormal, lightDirection), 0.0f);
           
           
           device Ray& shadowRay = shadowRays[uniforms.numLights * rayIdx + x];
           
           //1.0 - absorbiness was a term
           shadowRay.color = (energy[rayIdx]) * ray.color * material.kDiffuse.xyz * lightColor;
           
           
           shadowRay.direction = packed_float3(normalize(lightDirection));
           

           
           shadowRay.origin = packed_float3(intersectionPoint + (0.001 * shadowRay.direction));
           
           shadowRay.maxDistance = lightDistance - 0.001;
           
           shadowRay.mask = RAY_MASK_PRIMARY;
       }
       
       energy[rayIdx] *= material.absorbiness;
       
       ray.direction = packed_float3(getNewDirection(surfaceNormal, rand.xy, ray.direction, material.reflectivity));
        ray.origin = packed_float3(intersectionPoint + (0.001 * ray.direction));
       ray.color = ray.color * material.kDiffuse.xyz;
       }
       else
       {
           ray.maxDistance = -1.0f;
           for (int x = 0; x < uniforms.numLights; x++) {
               device Ray& shadowRay = shadowRays[uniforms.numLights * rayIdx + x];
               shadowRay.maxDistance = -1.0f;
           }
       }
       
       /*
        VertexIn vert = vertices[intersection.primitiveIndex * 3];
        
        
        float4 color = (intersection.distance >= 0.0f) * materials[vert.materialNum].kDiffuse;
        dstTex.write(color, tid);
        */
    }
}



kernel void
aggregateKernel(constant RayKernelUniforms&     uniforms      [[buffer(0)]],
                device   Ray*                   shadowRays    [[buffer(1)]],
                device   Intersection*          intersections [[buffer(2)]],
                texture2d<float, access::read>  srcTex        [[texture(0)]],
                texture2d<float, access::write> dstTex        [[texture(1)]],
                uint2                           tid           [[thread_position_in_grid]])
{
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        unsigned int rayIdx = tid.y * uniforms.width + tid.x;
     
        
        float3 color = srcTex.read(tid).xyz;
        
        for (int x = 0; x < uniforms.numLights; x++) {
            device Ray& shadowRay = shadowRays[uniforms.numLights * rayIdx + x];
            float intersectionDistance = intersections[uniforms.numLights * rayIdx + x].distance;
            
            float shouldAddColor = (shadowRay.maxDistance >= 0.0f && intersectionDistance < 0.0f) || (shadowRay.maxDistance >= 0.0f && shadowRay.maxDistance <= intersectionDistance);
            
            color += shouldAddColor * shadowRay.color;
        }
        
        dstTex.write(float4(color, 1.0), tid);
    }
}

kernel void
combineKernel(
                device int32_t&                 num           [[buffer(0)]],
                texture2d<float, access::read>  oldTex        [[texture(0)]],
                texture2d<float, access::read>  newTex        [[texture(1)]],
                texture2d<float, access::write> dstTex        [[texture(2)]],
                uint2                           tid           [[thread_position_in_grid]])
{
    float ratio = (float(num) - 1.0) / float(num);
    
    float4 oldColor = oldTex.read(tid);
    float4 newColor = newTex.read(tid);
    
    float4 combineColor = ratio * oldColor + (1.0 - ratio) * newColor;
    
    dstTex.write(combineColor, tid);
}


 
kernel void
copyKernel(
           texture2d<float, access::read>  srcTex        [[texture(0)]],
           texture2d<float, access::write> dstTex        [[texture(1)]],
           uint2                           tid           [[thread_position_in_grid]])
{
    
    float4 color = srcTex.read(tid);
    dstTex.write(color, tid);
}




//shadowray.color = energy * (1.0 - absorbiness) * ray.color * material.color * light.color;
//ray.color = ray.color * material.color;
//energy = energy * absorbiness
//abosorbiness - 1.0 = mirror 0.0 - diffuse object
