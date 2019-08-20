//
//  TextureReducer.metal
//  BrotonMapping
//
//  Created by Michael Kelly on 7/22/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

#include <metal_stdlib>
#import "ShaderStructs.h"
using namespace metal;


typedef struct
{
    uint r;
    uint g;
    uint b;
} Color;

typedef struct {
    uint width;
    uint height;
} TextureUniforms;

typedef struct {
    uint width;
    uint height;
    float area;
    float intensity;
    uint patchWidth;
} PhotonTextureUniforms;

constant float colorScale = 255.0;

kernel void
textureToColor(
               texture2d<float, access::read> tex           [[texture(0)]],
               device     Color*              colors        [[buffer(0)]],
               constant   TextureUniforms&    uniforms      [[buffer(1)]],
               device     uint*               photonCounts  [[buffer(2)]],
                          uint2               tid           [[thread_position_in_grid]]
               )
{
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        int i = index(tid, uniforms.width);
        device Color& color = colors[i];
        float4 c = tex.read(tid);
        color.r = uint(c.r * colorScale);
        color.g = uint(c.g * colorScale);
        color.b = uint(c.b * colorScale);
        photonCounts[i] = length(c.xyz) > 0.01;
        
    }
}

kernel void
colorToTexture(
               texture2d<float, access::write>      tex           [[texture(0)]],
               device     Color*                    colors        [[buffer(0)]],
               constant   PhotonTextureUniforms&    uniforms      [[buffer(1)]],
               device     uint*                     inCount       [[buffer(2)]],
               //device     uint*                     outCount      [[buffer(3)]],
                          uint2                     tid           [[thread_position_in_grid]]
               )
{
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        int i = index(tid, uniforms.width);
        device Color& color = colors[i];
        
        float scaleFactor = colorScale;
        //scaleFactor *= (uniforms.area * uniforms.area);
        //scaleFactor *- uniforms.area;
        scaleFactor /= uniforms.intensity;
        
        //float percentPhotonsGathered = float(inCount[i]) / float(uniforms.patchWidth * uniforms.patchWidth);
        
        //percentPhotonsGathered = pow(percentPhotonsGathered, 5.0);
        
        //scaleFactor /= percentPhotonsGathered;
        
        float r = min(float(color.r) / scaleFactor, 1.0);
        float g = min(float(color.g) / scaleFactor, 1.0);
        float b = min(float(color.b) / scaleFactor, 1.0);

        float4 c = float4(r, g, b, 1.0);
        tex.write(c, tid);
        
        //outCount[i] = inCount[i];
    }
}


kernel void
reduceTexture(
              //texture2d<float, access::read>  inTex  [[texture(0)]],
              //texture2d<float, access::write> outTex [[texture(1)]],
              device     Color*              inColor       [[buffer(0)]],
              device     Color*              outColor      [[buffer(1)]],
              constant   TextureUniforms&    uniforms      [[buffer(2)]],
              device     uint*               inCount       [[buffer(3)]],
              device     uint*               outCount      [[buffer(4)]],
              uint2               tid           [[thread_position_in_grid]]
              )
{
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        int i1 = index((2 * tid) + uint2(0, 0), 2 * uniforms.width);
        int i2 = index((2 * tid) + uint2(1, 0), 2 * uniforms.width);
        int i3 = index((2 * tid) + uint2(0, 1), 2 * uniforms.width);
        int i4 = index((2 * tid) + uint2(1, 1), 2 * uniforms.width);
        device Color& c1 = inColor[i1];
        device Color& c2 = inColor[i2];
        device Color& c3 = inColor[i3];
        device Color& c4 = inColor[i4];
        
        int o1 = index(tid, uniforms.width);
        device Color& out = outColor[o1];
        
        out.r = (c1.r + c2.r + c3.r + c4.r);// / 4.0;
        out.g = (c1.g + c2.g + c3.g + c4.g);// / 4.0;
        out.b = (c1.b + c2.b + c3.b + c4.b);// / 4.0;
        
        outCount[o1] = inCount[i1] + inCount[i2] + inCount[i3] + inCount[i4];
    }
    /*
     float4 color = inTex.read((2 * tid) + uint2(0, 0)) +
     inTex.read((2 * tid) + uint2(1, 0)) +
     inTex.read((2 * tid) + uint2(0, 1)) +
     inTex.read((2 * tid) + uint2(1, 1));
     
     outTex.write(color / 4.0, tid);
     */
}


