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



constant int8_t DIRECTIONAL_LIGHT = 0;
constant int8_t SPOT_LIGHT = 1;
constant int8_t POINT_LIGHT = 2;


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

typedef struct
{
    float3 position;
    float3 forward;
    float3 right;
    float3 up;
    int32_t width;
    int32_t height;
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

constant int intersectionStride = sizeof(Intersection);


#endif /* ShaderStructs_h */
