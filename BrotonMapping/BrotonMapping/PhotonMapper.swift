//
//  PhotonMapper.swift
//  BrotonMapping
//
//  Created by Michael Kelly on 7/25/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders

class PhotonMapper
{
    var device: MTLDevice!
    
    var raysPerRay: Int = 8
    var widthPerLight: Int = 8
    var numPhotonBounces: Int = 3
    
    var largeTexture: MTLTexture!
    var largeRayBuffer: MTLBuffer!
    var largeIntersectionBuffer: MTLBuffer!
    var photonBuffer: MTLBuffer!
    
    var smallWidth: Int!
    var smallHeight: Int!
    
    var triangles: [Triangle]
    var lights: [Light]
    

    
    
    init(device: MTLDevice, smallWidth: Int, smallHeight: Int, triangles: [Triangle], lights: [Light])
    {
        self.device = device
        self.smallWidth = smallWidth
        self.smallHeight = smallHeight
        self.triangles = triangles
        self.lights = lights
        
        createLargeStuff(smallWidth: smallWidth, smallHeight: smallHeight)
        
        let numPhotonsPerLight = numPhotonBounces * widthPerLight * widthPerLight
        photonBuffer = nil
        fillBuffer(device: device, buffer: &photonBuffer, data: [], size: MemoryLayout<Photon>.stride * numPhotonsPerLight)
    }
    
    func createLargeStuff(smallWidth: Int, smallHeight: Int)
    {
        let largeWidth = smallWidth * raysPerRay
        let largeHeight = smallHeight * raysPerRay
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.width = largeWidth
        textureDescriptor.height = largeHeight
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.usage = .init(arrayLiteral: [.shaderRead, .shaderWrite])
        textureDescriptor.storageMode = .managed
        largeTexture = (device.makeTexture(descriptor: textureDescriptor)!)
        
        largeRayBuffer = nil
        fillBuffer(device: device, buffer: &largeRayBuffer, data: [], size: MemoryLayout<Ray>.stride * largeWidth * largeHeight)
        
        largeIntersectionBuffer = nil
        fillBuffer(device: device, buffer: &largeIntersectionBuffer, data: [], size: MemoryLayout<Intersection>.stride * largeWidth * largeHeight)
    }
    
    func generatePhotons(commandBuffer: MTLCommandBuffer)
    {
        
        for light in lights
        {
            var commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            
            
            
            
        }
        
        
    }

    
    
}





/*
 
 
 
 
 let startSize = 4
 let endSize = 1
 
 
 let textureDescriptor1 = MTLTextureDescriptor()
 textureDescriptor1.width = startSize
 textureDescriptor1.height = (startSize)
 textureDescriptor1.pixelFormat = .bgra8Unorm
 textureDescriptor1.usage = .init(arrayLiteral: [.shaderRead, .shaderWrite])
 textureDescriptor1.storageMode = .managed
 let texture1 = (device.makeTexture(descriptor: textureDescriptor1)!)
 
 let textureDescriptor2 = MTLTextureDescriptor()
 textureDescriptor2.width = (endSize)
 textureDescriptor2.height = (endSize)
 textureDescriptor2.pixelFormat = .bgra8Unorm
 textureDescriptor2.usage = .init(arrayLiteral: [.shaderRead, .shaderWrite])
 textureDescriptor2.storageMode = .managed
 let texture2 = (device.makeTexture(descriptor: textureDescriptor2)!)
 
 
 var randomValues: [uint32] = []
 for _ in 0 ..< startSize * startSize
 {
 let rand = uint32(drand48() * (Double(uint32.max)))
 randomValues.append(rand)
 }
 
 
 texture1.replace(region: MTLRegionMake2D(0, 0, startSize, startSize), mipmapLevel: 0, withBytes: &randomValues, bytesPerRow: MemoryLayout<uint32>.stride * startSize)
 
 let textureReducer = TextureReducer(device: device)
 textureReducer.prepare(startingWidth: startSize, startingHeight: startSize, timesToReduce: (Int(log2(Double(startSize / endSize)))))
 textureReducer.reduceTexture(commandBuffer: commandBuffer, startTexture: texture1, endTexture: texture2)
 */
