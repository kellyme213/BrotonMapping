//
//  File.metal
//  BrotonMapping
//
//  Created by Michael Kelly on 7/27/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

#include <metal_stdlib>
#include "ShaderStructs.h"
using namespace metal;


typedef struct
{
    uint widthPerRay;
    uint heightPerRay;
    uint textureWidth;
    uint textureHeight;
    float heightAbovePlane;
    float sizeOfPatch;
} PhotonUniforms;

typedef struct
{
    uint width;
    uint height;
    float radius;
} PhotonTriangleUniforms;


kernel void
photonRaysFromLight(constant Light&                light       [[buffer(0)]],
                    constant PhotonUniforms&       uniforms    [[buffer(1)]],
                    device   Ray*                  rays        [[buffer(2)]],
                    texture2d<float, access::read> randTex     [[texture(0)]],
                    uint2                          tid         [[thread_position_in_grid]])
{
        if (tid.x < uniforms.textureWidth && tid.y < uniforms.textureHeight) {

            unsigned int rayIdx = index(tid, uniforms.textureWidth);
            device Ray & ray = rays[rayIdx];
            float2 pixel = (float2)tid;
            float2 rand = randTex.read(tid).xy;
            pixel += (rand * 2.0f - 1.0f);
            float2 uv = (float2)pixel / float2(uniforms.textureWidth, uniforms.textureHeight);
            uv = uv * 2.0f - 1.0f;
            
            float2 rand2 = randTex.read(tid).yz;
            rand2 = 0.1 * (rand2 * 2.0f - 1.0f);
            
            ray.origin = light.position + (uv.x * light.right + uv.y * light.up);
            ray.direction = normalize(light.direction + (rand2.x * light.right + rand2.y * light.up));
            ray.mask = RAY_MASK_PRIMARY;
            ray.maxDistance = INFINITY;
            ray.color = light.color.xyz;
        }
}

kernel void
photonToTriangle(
                 device   Photon*          photons              [[buffer(0)]],
                 device   PhotonVertex*    vertices             [[buffer(1)]],
                 constant PhotonTriangleUniforms&  uniforms     [[buffer(2)]],
                 device   float3*          vertexPositions      [[buffer(3)]],
                          uint2            tid                  [[thread_position_in_grid]])
{
    if (tid.x < uniforms.width && tid.y < uniforms.height)
    {
        int photonIndex = index(tid, uniforms.width);
        device Photon& photon = photons[photonIndex];
        float3 forward = normalize(photon.surfaceNormal);
        float3 right = normalize(cross(forward, float3(0.003f, 1.001f, 0.003f)));
        float3 up = normalize(cross(right, forward));
        
        float3 p0 = photon.position + uniforms.radius * (sin(0.0f * M_PI_F / 3.0f) * right +
                                                         cos(0.0f * M_PI_F / 3.0f) * up);
        
        float3 p1 = photon.position + uniforms.radius * (sin(2.0f * M_PI_F / 3.0f) * right +
                                                         cos(2.0f * M_PI_F / 3.0f) * up);
        
        float3 p2 = photon.position + uniforms.radius * (sin(4.0f * M_PI_F / 3.0f) * right +
                                                         cos(4.0f * M_PI_F / 3.0f) * up);

        device PhotonVertex& v0 = vertices[3 * photonIndex + 0];
        device PhotonVertex& v1 = vertices[3 * photonIndex + 1];
        device PhotonVertex& v2 = vertices[3 * photonIndex + 2];
        
        
        float shouldDraw = (length(photon.incomingDirection) > 0.001f);
        
        p0 = (1.0 - shouldDraw) * float3(-10, -10, -10) + shouldDraw * p0;
        p1 = (1.0 - shouldDraw) * float3(-10, -10, -10) + shouldDraw * p1;
        p2 = (1.0 - shouldDraw) * float3(-10, -10, -10) + shouldDraw * p2;

        
        v0.position = float4(p2, 1.0);
        v0.color = photon.color;
        
        v1.position = float4(p1, 1.0);
        v1.color = photon.color;

        v2.position = float4(p0, 1.0);
        v2.color = photon.color;
        
        vertexPositions[3 * photonIndex + 0] = p2;
        vertexPositions[3 * photonIndex + 1] = p1;
        vertexPositions[3 * photonIndex + 2] = p0;
    }
}


kernel void
generatePhotons(
                device   Ray*             inputRays            [[buffer(0)]],
                device   Intersection*    inputIntersections   [[buffer(1)]],
                device   VertexIn*        inputVertices        [[buffer(2)]],
                device   Photon*          outputPhotons        [[buffer(3)]],
                device   Material*        materials            [[buffer(4)]],
                device   float*           energy               [[buffer(5)]],
                constant PhotonUniforms&  uniforms             [[buffer(6)]],
                constant uint&            offset               [[buffer(7)]],
                texture2d<float, access::read> randTex         [[texture(0)]],
                         uint2            tid                  [[thread_position_in_grid]])
{
    if (tid.x < uniforms.textureWidth && tid.y < uniforms.textureHeight)
    {
        int inputIndex = index(tid, uniforms.textureWidth);
        
        const device Intersection& inputIntersection = inputIntersections[inputIndex];
        device Ray& inputRay = inputRays[inputIndex];
        
        if (inputRay.maxDistance > 0.0f && inputIntersection.distance >= 0.0f)
        {
            float3 uvw = float3(inputIntersection.coordinates.x,
                                inputIntersection.coordinates.y,
                                1.0 - inputIntersection.coordinates.x - inputIntersection.coordinates.y);
            
            float3 n0 = inputVertices[3 * inputIntersection.primitiveIndex + 0].normal;
            float3 n1 = inputVertices[3 * inputIntersection.primitiveIndex + 1].normal;
            float3 n2 = inputVertices[3 * inputIntersection.primitiveIndex + 2].normal;
            
            float3 intersectionNormal = normalize(uvw.x * n0 +
                                                  uvw.y * n1 +
                                                  uvw.z * n2);
            
            float3 intersectionPosition = inputRay.origin + inputIntersection.distance * inputRay.direction;
            
            device Photon& outputPhoton = outputPhotons[inputIndex];
            
            const device VertexIn& inputVertex = inputVertices[3 * inputIntersection.primitiveIndex + 0];
            const device Material& mat = materials[inputVertex.materialNum];
            

            outputPhoton.incomingDirection = inputRay.direction;
            outputPhoton.position = intersectionPosition;
            outputPhoton.color = energy[inputIndex] * inputRay.color * mat.kDiffuse.xyz;
            outputPhoton.surfaceNormal = intersectionNormal;
            
            //energy[inputIndex] *= mat.absorbiness;
            
            
            inputRay.color *= mat.kDiffuse.xyz;
            
            float2 rand = randTex.read(tid).xy;
            
            float3 newDirection = getNewDirection(intersectionNormal, rand,
                                               inputRay.direction, mat.reflectivity);
            
            inputRay.origin = intersectionPosition + 0.001f * newDirection;
            inputRay.direction = newDirection;
        }
        else
        {
            inputRay.maxDistance = -1.0f;
            outputPhotons[inputIndex].incomingDirection = float3(0.0f, 0.0f, 0.0f);
            outputPhotons[inputIndex].color = float3(0.0f);
            outputPhotons[inputIndex].position = float3(-10, -10, -10);
            //handle bad photons
        }
        
    }
}


kernel void
generatePhotonGatherRays(
                             device   Ray*             inputRays            [[buffer(0)]],
                             device   Intersection*    inputIntersections   [[buffer(1)]],
                             device   VertexIn*        inputVertices        [[buffer(2)]],
                             device   Ray*             outputRays           [[buffer(3)]],
                             constant PhotonUniforms&  uniforms             [[buffer(4)]],
                                      uint2            tid                  [[thread_position_in_grid]])
{
    if (tid.x < uniforms.textureWidth && tid.y < uniforms.textureHeight)
    {
        
        uint2 scaledTID = uint2(tid.x / uniforms.widthPerRay, tid.y / uniforms.heightPerRay);
        
        int inputIndex = index(scaledTID, uniforms.textureWidth / uniforms.widthPerRay);
        device Intersection& inputIntersection = inputIntersections[inputIndex];
        device Ray& inputRay = inputRays[inputIndex];
        
        if (inputIntersection.distance > 0.001f)
        {
            float2 localTID = float2(tid.x % uniforms.widthPerRay, tid.y % uniforms.heightPerRay);
            localTID -= float2(uniforms.widthPerRay / 2, uniforms.heightPerRay / 2);
            //localTID *= uniforms.sizeOfPatch;
            localTID /= float2(float(uniforms.widthPerRay), float(uniforms.heightPerRay));
            //localTID = float2(0, 0);
            float3 uvw = float3(inputIntersection.coordinates.x,
                                inputIntersection.coordinates.y,
                                1.0 - inputIntersection.coordinates.x - inputIntersection.coordinates.y);
            
            float3 n0 = inputVertices[3 * inputIntersection.primitiveIndex + 0].normal;
            float3 n1 = inputVertices[3 * inputIntersection.primitiveIndex + 1].normal;
            float3 n2 = inputVertices[3 * inputIntersection.primitiveIndex + 2].normal;

            float3 intersectionNormal = normalize(uvw.x * n0 +
                                                  uvw.y * n1 +
                                                  uvw.z * n2);
            
            float3 intersectionPoint = inputRay.origin + inputIntersection.distance * inputRay.direction;
            
            intersectionPoint += uniforms.heightAbovePlane * intersectionNormal;
            
            float3 newRayForward = -normalize(intersectionNormal);
            //negative because the output ray is casting down onto the surface
            //opposite the intersection normal
            
            float3 newRayRight = normalize(cross(newRayForward, float3(0.003f, 1.001f, 0.003f)));
            float3 newRayUp = normalize(cross(newRayRight, newRayForward));
            
            newRayRight *= uniforms.sizeOfPatch;
            newRayUp *= uniforms.sizeOfPatch;
            
            float3 newRayOrigin = intersectionPoint + localTID.x * newRayRight + localTID.y * newRayUp;
            
            device Ray& outputRay = outputRays[index(tid, uniforms.textureWidth)];
            outputRay.origin = newRayOrigin;
            outputRay.direction = newRayForward;
            outputRay.maxDistance = uniforms.heightAbovePlane * 1.001f;
            outputRay.color = float3(1.0f);
            outputRay.mask = RAY_MASK_PRIMARY;
        }
    }
}



kernel void
generateGatherTexture(
                      device   Ray*             inputRays            [[buffer(0)]],
                      device   Intersection*    inputIntersections   [[buffer(1)]],
                      device   PhotonVertex*    inputVertices        [[buffer(2)]],
                      texture2d<float, access::write> dstTex         [[texture(0)]],
                               uint2            tid                  [[thread_position_in_grid]]
                      )
{
    if (tid.x < dstTex.get_width() && tid.y < dstTex.get_height())
    {
        int rayIndex = index(tid, dstTex.get_width());
        
        device Ray& inputRay = inputRays[rayIndex];
        device Intersection& inputIntersection = inputIntersections[rayIndex];
        
        if (inputIntersection.distance > 0.0f)// && inputIntersection.distance <= inputRay.maxDistance)
        {
            float3 color = inputVertices[3 * inputIntersection.primitiveIndex + 0].color;
            dstTex.write(float4(color, 1.0), tid);
        }
    }
}


