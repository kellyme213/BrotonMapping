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



kernel void
rayKernel(constant RayKernelUniforms&    uniforms    [[buffer(0)]],
          device   Ray*                  rays        [[buffer(1)]],
          uint2                          tid         [[thread_position_in_grid]]) {
    
    
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        // Compute linear ray index from 2D position
        unsigned int rayIdx = tid.y * uniforms.width + tid.x;
        
        // Ray we will produce
        device Ray & ray = rays[rayIdx];
        
        // Pixel coordinates for this thread
        float2 pixel = (float2)tid;

        
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
    }
}


kernel void
shadeKernel(constant RayKernelUniforms&     uniforms      [[buffer(0)]],
            device   Ray*                   rays          [[buffer(1)]],
            device   Intersection*          intersections [[buffer(2)]],
            texture2d<float, access::write> dstTex        [[texture(0)]],
            uint2                           tid           [[thread_position_in_grid]])
{
    //dstTex.write(float4(1.0, 0.0, 0.0, 1.0), tid);

   if (tid.x < uniforms.width && tid.y < uniforms.height) {

        unsigned int rayIdx = tid.y * uniforms.width + tid.x;
        
        device Ray & ray = rays[rayIdx];
        device Intersection & intersection = intersections[rayIdx];
        
        float color = (intersection.distance >= 0.0f);
        dstTex.write(float4(color, 0.0, 0.0, 1.0), tid);
    
    }
}

