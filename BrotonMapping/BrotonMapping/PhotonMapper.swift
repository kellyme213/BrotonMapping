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
    
    var collectionRaysPerShadeRayWidth: Int = 4
    var photonsPerLightWidth: Int = 1024
    var numPhotonBounces: Int = 2
    
    var largeTexture: MTLTexture!
    var largeRayBuffer: MTLBuffer!
    var largeIntersectionBuffer: MTLBuffer!
    
    var photonBuffer: MTLBuffer!
    
    var smallWidth: Int!
    var smallHeight: Int!
    
    var triangles: [Triangle]
    var lights: [Light]
    
    var photonVertices: [PhotonVertex] = []
    var photonGeneratorAccelerationStructure: MPSTriangleAccelerationStructure!
    var photonGeneratorVertexPositionBuffer: MTLBuffer!
    var photonGeneratorIntersectionBuffer: MTLBuffer!
    var photonGeneratorRayBuffer: MTLBuffer!
    var photonGeneratorIntersector: MPSRayIntersector!
    var photonGeneratorPipelineState: MTLComputePipelineState!
    
    var photonGathererAccelerationStructure: MPSTriangleAccelerationStructure!
    var photonGathererVertexPositionBuffer: MTLBuffer!
    var photonGathererIntersectionBuffer: MTLBuffer!
    var photonGathererIntersector: MPSRayIntersector!
    
    var photonVertexBuffer: MTLBuffer!
    
    var prflPipelineState: MTLComputePipelineState!
    var pttPipelineState: MTLComputePipelineState!
    var gpgrPipelineState: MTLComputePipelineState!
    var ggtPipelineState: MTLComputePipelineState!

    var materials: [Material] = []
    var materialBuffer: MTLBuffer!
    var vertexBuffer: MTLBuffer!
    
    var energyBuffer: MTLBuffer!
    
    
    var numPhotons: Int!
    
    var textureReducer: TextureReducer!

    
    
    init(device: MTLDevice, smallWidth: Int, smallHeight: Int, triangles: [Triangle], lights: [Light])
    {
        self.device = device
        self.smallWidth = smallWidth
        self.smallHeight = smallHeight
        self.triangles = triangles
        self.lights = lights
        
        textureReducer = TextureReducer(device: device)
        
        createLargeStuff(smallWidth: smallWidth, smallHeight: smallHeight)
        
        numPhotons = self.lights.count * numPhotonBounces * photonsPerLightWidth * photonsPerLightWidth
        photonBuffer = nil
        fillBuffer(device: device, buffer: &photonBuffer, data: [], size: MemoryLayout<Photon>.stride * numPhotons)
        
        photonGathererVertexPositionBuffer = nil
        fillBuffer(device: device, buffer: &photonGathererVertexPositionBuffer, data: [], size: MemoryLayout<SIMD3<Float>>.stride * numPhotons * 3)
        
        generatePhotonGeneratorAccelerationStructure()
        
        fillTriangleBuffer(device: device, materialArray: &materials, triangles: triangles, vertexBuffer: &vertexBuffer, materialBuffer: &materialBuffer)
        
        
        photonGeneratorRayBuffer = nil
        photonGeneratorIntersectionBuffer = nil
        fillBuffer(device: device, buffer: &photonGeneratorRayBuffer, data: [], size: rayStride * photonsPerLightWidth * photonsPerLightWidth)
        fillBuffer(device: device, buffer: &photonGeneratorIntersectionBuffer, data: [], size: intersectionStride * photonsPerLightWidth * photonsPerLightWidth)

        
        fillBuffer(device: device, buffer: &photonVertexBuffer, data: [], size: MemoryLayout<PhotonVertex>.stride * numPhotons * 3)
 
        let defaultLibrary = device.makeDefaultLibrary()!
        let prflFunction = defaultLibrary.makeFunction(name: "photonRaysFromLight")!
        prflPipelineState = try! device.makeComputePipelineState(function: prflFunction)
        
        let gpFunction = defaultLibrary.makeFunction(name: "generatePhotons")!
        photonGeneratorPipelineState = try! device.makeComputePipelineState(function: gpFunction)
 
        let pttFunction = defaultLibrary.makeFunction(name: "photonToTriangle")!
        pttPipelineState = try! device.makeComputePipelineState(function: pttFunction)
        
        let gpgrFunction = defaultLibrary.makeFunction(name: "generatePhotonGatherRays")!
        gpgrPipelineState = try! device.makeComputePipelineState(function: gpgrFunction)
     
        let ggtFunction = defaultLibrary.makeFunction(name: "generateGatherTexture")!
        ggtPipelineState = try! device.makeComputePipelineState(function: ggtFunction)
        
        
    }
    
    
    func generatePhotonGeneratorAccelerationStructure()
    {
        photonGeneratorIntersector = MPSRayIntersector(device: device)
        
        photonGeneratorIntersector.rayDataType = .originMaskDirectionMaxDistance
        photonGeneratorIntersector.rayStride = rayStride
        photonGeneratorIntersector.intersectionDataType = .distancePrimitiveIndexCoordinates
        
        var vertexPositions: [SIMD3<Float>] = []
        for t in triangles
        {
            vertexPositions.append(t.vertA.position.xyz)
            vertexPositions.append(t.vertB.position.xyz)
            vertexPositions.append(t.vertC.position.xyz)
        }
        
        fillBuffer(device: device, buffer: &photonGeneratorVertexPositionBuffer, data: vertexPositions)
        
        
        photonGeneratorAccelerationStructure = MPSTriangleAccelerationStructure(device: device)
        photonGeneratorAccelerationStructure.vertexBuffer = photonGeneratorVertexPositionBuffer
        photonGeneratorAccelerationStructure.triangleCount = vertexPositions.count / 3
        photonGeneratorAccelerationStructure.rebuild()
    }
    
    
    func generatePhotonGathererAccelerationStructure()
    {
        photonGathererIntersector = MPSRayIntersector(device: device)
        photonGathererIntersector.rayDataType = .originMaskDirectionMaxDistance
        photonGathererIntersector.rayStride = rayStride
        photonGathererIntersector.intersectionDataType = .distancePrimitiveIndexCoordinates
        
        photonGathererAccelerationStructure = MPSTriangleAccelerationStructure(device: device)
        photonGathererAccelerationStructure.vertexBuffer = photonGathererVertexPositionBuffer
        photonGathererAccelerationStructure.triangleCount = numPhotons
        photonGathererAccelerationStructure.rebuild()
        
        print("Photon map created with " + String(numPhotons) + " photons.")
    }
    
    func createLargeStuff(smallWidth: Int, smallHeight: Int)
    {
        let largeWidth = smallWidth * collectionRaysPerShadeRayWidth
        let largeHeight = smallHeight * collectionRaysPerShadeRayWidth
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.width = largeWidth
        textureDescriptor.height = largeHeight
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.usage = .init(arrayLiteral: [.shaderRead, .shaderWrite])
        textureDescriptor.storageMode = .managed
        largeTexture = (device.makeTexture(descriptor: textureDescriptor)!)
        
        largeRayBuffer = nil
        fillBuffer(device: device, buffer: &largeRayBuffer, data: [], size: rayStride * largeWidth * largeHeight)
        
        largeIntersectionBuffer = nil
        fillBuffer(device: device, buffer: &largeIntersectionBuffer, data: [], size: intersectionStride * largeWidth * largeHeight)
        
        textureReducer.prepare(startingWidth: largeWidth, startingHeight: largeHeight, timesToReduce: Int(log2(Double(collectionRaysPerShadeRayWidth))))
    }
    
    func generatePhotons()
    {
        let commandQueue = device.makeCommandQueue()!
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        let lightPhotonStride = MemoryLayout<Photon>.stride * numPhotonBounces * photonsPerLightWidth * photonsPerLightWidth
        
        let threadGroupSize = MTLSizeMake(8, 8, 1)
        
        var threadCountGroup = MTLSize()
        threadCountGroup.width = (photonsPerLightWidth + threadGroupSize.width - 1) / threadGroupSize.width
        threadCountGroup.height = (photonsPerLightWidth + threadGroupSize.height - 1) / threadGroupSize.height
        threadCountGroup.depth = 1
        
        var commandEncoder: MTLComputeCommandEncoder!
        
        for x in 0 ..< lights.count
        {
            commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            
            commandEncoder.setComputePipelineState(prflPipelineState)
            commandEncoder.setBytes(&(lights[x]), length: MemoryLayout<Light>.stride, index: 0)
            var photonUniforms = PhotonUniforms(widthPerRay: 0, heightPerRay: 0, textureWidth: uint(photonsPerLightWidth), textureHeight: uint(photonsPerLightWidth), heightAbovePlane: 0, sizeOfPatch: 0)
            commandEncoder.setBytes(&photonUniforms, length: MemoryLayout<PhotonUniforms>.stride, index: 1)
            commandEncoder.setBuffer(photonGeneratorRayBuffer, offset: 0, index: 2)

            let randomTexture = createRandomTexture(device: device, width: photonsPerLightWidth, height: photonsPerLightWidth)
            commandEncoder.setTexture(randomTexture, index: 0)
            commandEncoder.dispatchThreadgroups(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
            commandEncoder.endEncoding()
            
            
            let energyData = Array<Float>.init(repeating: 1.0, count: photonsPerLightWidth * photonsPerLightWidth)
            fillBuffer(device: device, buffer: &energyBuffer, data: energyData)
            
            for y in 0 ..< numPhotonBounces
            {
                photonGeneratorIntersector.intersectionDataType = .distancePrimitiveIndexCoordinates
                photonGeneratorIntersector.encodeIntersection(commandBuffer: commandBuffer, intersectionType: .nearest, rayBuffer: photonGeneratorRayBuffer, rayBufferOffset: 0, intersectionBuffer: photonGeneratorIntersectionBuffer, intersectionBufferOffset: 0, rayCount: photonsPerLightWidth * photonsPerLightWidth, accelerationStructure: photonGeneratorAccelerationStructure)
                
                
                commandEncoder = commandBuffer.makeComputeCommandEncoder()!
                commandEncoder.setComputePipelineState(photonGeneratorPipelineState)
                commandEncoder.setBuffer(photonGeneratorRayBuffer, offset: 0, index: 0)
                commandEncoder.setBuffer(photonGeneratorIntersectionBuffer, offset: 0, index: 1)
                commandEncoder.setBuffer(vertexBuffer, offset: 0, index: 2)
                
                let offset = x * lightPhotonStride + (MemoryLayout<Photon>.stride * y * photonsPerLightWidth * photonsPerLightWidth)
                
                var offsetNum: uint = 0//uint(offset / MemoryLayout<Photon>.stride)
                
                
                commandEncoder.setBuffer(photonBuffer, offset: offset, index: 3)
                commandEncoder.setBuffer(materialBuffer, offset: 0, index: 4)
                commandEncoder.setBuffer(energyBuffer, offset: 0, index: 5)
                commandEncoder.setBytes(&photonUniforms, length: MemoryLayout<PhotonUniforms>.stride, index: 6)
                commandEncoder.setBytes(&offsetNum, length: MemoryLayout<uint>.stride, index: 7)
                commandEncoder.setTexture(randomTexture, index: 0)
                commandEncoder.dispatchThreadgroups(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
                commandEncoder.endEncoding()
            }
        }
        
        commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(pttPipelineState)
        commandEncoder.setBuffer(photonBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(photonVertexBuffer, offset: 0, index: 1)
        commandEncoder.setBuffer(photonGathererVertexPositionBuffer, offset: 0, index: 3)
        
        threadCountGroup = MTLSize()
        
        let w = numPhotonBounces * photonsPerLightWidth
        let h = lights.count * photonsPerLightWidth
        
        threadCountGroup.width = (w + threadGroupSize.width - 1) / threadGroupSize.width
        threadCountGroup.height = (h + threadGroupSize.height - 1) / threadGroupSize.height
        threadCountGroup.depth = 1
        
        
        var photonVertexUniforms = PhotonTriangleUniforms(width: uint(w), height: uint(h), radius: 0.001)
        
        commandEncoder.setBytes(&photonVertexUniforms, length: MemoryLayout<PhotonTriangleUniforms>.stride, index: 2)
        commandEncoder.dispatchThreadgroups(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
        commandEncoder.endEncoding()
        
        commandBuffer.addCompletedHandler({_ in
            self.generatePhotonGathererAccelerationStructure()
            })
        commandBuffer.commit()
    }
    
    func gatherPhotons(commandBuffer: MTLCommandBuffer, inputRayBuffer: MTLBuffer, inputIntersectionBuffer: MTLBuffer, causticTexture: MTLTexture)
    {
        var commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(gpgrPipelineState)
        commandEncoder.setBuffer(inputRayBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(inputIntersectionBuffer, offset: 0, index: 1)
        commandEncoder.setBuffer(vertexBuffer, offset: 0, index: 2)
        commandEncoder.setBuffer(largeRayBuffer, offset: 0, index: 3)
        
        
        let largeWidth = causticTexture.width * collectionRaysPerShadeRayWidth
        let largeHeight = causticTexture.height * collectionRaysPerShadeRayWidth
        var photonUniforms = PhotonUniforms(
            widthPerRay: uint(collectionRaysPerShadeRayWidth),
            heightPerRay: uint(collectionRaysPerShadeRayWidth),
            textureWidth: uint(largeWidth),
            textureHeight: uint(largeHeight))
        
        commandEncoder.setBytes(&photonUniforms, length: MemoryLayout<PhotonUniforms>.stride, index: 4)
        
        
        let threadGroupSize = MTLSizeMake(8, 8, 1)
        
        var threadCountGroup = MTLSize()
        threadCountGroup.width = (largeWidth + threadGroupSize.width - 1) / threadGroupSize.width
        threadCountGroup.height = (largeHeight + threadGroupSize.height - 1) / threadGroupSize.height
        threadCountGroup.depth = 1
        commandEncoder.dispatchThreadgroups(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
        commandEncoder.endEncoding()
        
        
        photonGathererIntersector.intersectionDataType = .distancePrimitiveIndexCoordinates
        photonGathererIntersector.encodeIntersection(commandBuffer: commandBuffer, intersectionType: .nearest, rayBuffer: largeRayBuffer, rayBufferOffset: 0, intersectionBuffer: largeIntersectionBuffer, intersectionBufferOffset: 0, rayCount: largeHeight * largeWidth, accelerationStructure: photonGathererAccelerationStructure)
        
        
        commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(ggtPipelineState)
        commandEncoder.setBuffer(largeRayBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(largeIntersectionBuffer, offset: 0, index: 1)
        commandEncoder.setBuffer(photonVertexBuffer, offset: 0, index: 2)
        commandEncoder.setTexture(largeTexture, index: 0)
        commandEncoder.dispatchThreadgroups(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
        commandEncoder.endEncoding()
        
        textureReducer.reduceTexture(commandBuffer: commandBuffer, startTexture: largeTexture, endTexture: causticTexture)
        
        
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
