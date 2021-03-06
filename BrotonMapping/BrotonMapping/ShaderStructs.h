//
//  ShaderStructs.h
//  BrotonMapping
//
//  Created by Michael Kelly on 7/14/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

#ifndef ShaderStructs_h
#define ShaderStructs_h
#include <simd/simd.h>

//using namespace metal;
#define RAY_MASK_PRIMARY   3
#define RAY_MASK_SHADOW    1
#define RAY_MASK_SECONDARY 1
using namespace metal;


constant int8_t DIRECTIONAL_LIGHT = 0;
constant int8_t SPOT_LIGHT = 1;
constant int8_t POINT_LIGHT = 2;
constant int8_t AREA_LIGHT = 3;


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
    float reflectivity;
    float absorbiness;
} Material;

typedef struct
{
    float3 position;
    float3 direction;
    float3 right;
    float3 up;
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

typedef struct
{
    float3 position;
    float3 forward;
    float3 right;
    float3 up;
    int32_t width;
    int32_t height;
    int8_t numLights;
} RayKernelUniforms;

typedef struct
{
    // Starting point
    packed_float3 origin;
    
    // Mask which will be bitwise AND-ed with per-triangle masks to filter out certain
    // intersections. This is used to make the light source visible to the camera but not
    // to shadow or secondary rays.
    uint mask;
    
    // Direction the ray is traveling
    packed_float3 direction;
    
    // Maximum intersection distance to accept. This is used to prevent shadow rays from
    // overshooting the light source when checking for visibility.
    float maxDistance;
    
    // The accumulated color along the ray's path so far
    float3 color;
} Ray;

// Represents an intersection between a ray and the scene, returned by the MPSRayIntersector.
// The intersection type is customized using properties of the MPSRayIntersector.
typedef struct {
    // The distance from the ray origin to the intersection point. Negative if the ray did not
    // intersect the scene.
    float distance;
    
    // The index of the intersected primitive (triangle), if any. Undefined if the ray did not
    // intersect the scene.
    int primitiveIndex;
    
    // The barycentric coordinates of the intersection point, if any. Undefined if the ray did
    // not intersect the scene.
    float2 coordinates;
} Intersection;

typedef struct
{
    float3 position;
    float3 color;
    float3 incomingDirection;
    float3 surfaceNormal;
} Photon;

typedef struct
{
    float4 position;
    float3 color;
} PhotonVertex;

inline uint index(uint2 tid, uint width) {
    return tid.y * width + tid.x;
}

inline float3 sampleCosineWeightedHemisphere(float2 u) {
    float phi = 2.0f * M_PI_F * u.x;
    float cos_phi;
    float sin_phi = sincos(phi, cos_phi);
    float cos_theta = sqrt(u.y);
    float sin_theta = sqrt(1.0f - cos_theta * cos_theta);
    return float3(sin_theta * cos_phi, cos_theta, sin_theta * sin_phi);
}

inline float3 alignHemisphereWithNormal(float3 sample, float3 normal) {
    float3 up = normal;
    float3 right = normalize(cross(normal, float3(0.0072f, 1.0f, 0.0034f)));
    float3 forward = cross(right, up);
    return sample.x * right + sample.y * up + sample.z * forward;
}

inline float3 getNewDirection(float3 surfaceNormal, float2 u,
float3 incomingDirection, float reflectivity) {
    
    float3 randomNormal = sampleCosineWeightedHemisphere(u);
    randomNormal = alignHemisphereWithNormal(randomNormal, surfaceNormal);
    
    float3 reflectedNormal = reflect(incomingDirection, surfaceNormal);
    
    
    return normalize(reflectivity         * reflectedNormal +
                     (1.0 - reflectivity) * randomNormal);
}

#endif /* ShaderStructs_h */
