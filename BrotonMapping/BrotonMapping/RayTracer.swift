//
//  RayTracer.swift
//  BrotonMapping
//
//  Created by Michael Kelly on 7/14/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders
import simd

class RayTracer
{
    
    var rayPipelineState: MTLComputePipelineState!
    var shadePipelineState: MTLComputePipelineState!
    var aggregatePipelineState: MTLComputePipelineState!
    var combinePipelineState: MTLComputePipelineState!
    var copyPipelineState: MTLComputePipelineState!

    var computeCommandEncoder: MTLComputeCommandEncoder!
    var intersector: MPSRayIntersector!
    var accelerationStructure: MPSTriangleAccelerationStructure!
    var vertexPositionBuffer: MTLBuffer!
    var vertexBuffer: MTLBuffer!
    var materialBuffer: MTLBuffer!
    var lightBuffer: MTLBuffer!
    var rayUniformBuffer: MTLBuffer!
    var rayBuffer: MTLBuffer!
    var shadowRayBuffer: MTLBuffer!
    var intersectionBuffer: MTLBuffer!
    var shadowIntersectionBuffer: MTLBuffer!
    var energyBuffer: MTLBuffer!
    var numBuffer: MTLBuffer!
    var device: MTLDevice!
    var lights: [Light] = []
    var materials: [Material] = []
    var shadowRenderTextures: [MTLTexture] = []
    let NUM_BOUNCES = 5;
    var numRenders: Int32 = 1;
    var cachedRender: MTLTexture!
    
    init(device: MTLDevice) {
        self.device = device
        setup()
        numRenders = 0
    }
    
    func generateAccelerationStructure(triangles: [Triangle], lights: [Light])
    {
        self.lights = lights
        
        intersector = MPSRayIntersector(device: device)
        
        intersector.rayDataType = .originMaskDirectionMaxDistance
        intersector.rayStride = rayStride
        intersector.intersectionDataType = .distancePrimitiveIndexCoordinates

        var vertexPositions: [SIMD3<Float>] = []
        for t in triangles
        {
            vertexPositions.append(t.vertA.position.xyz)
            vertexPositions.append(t.vertB.position.xyz)
            vertexPositions.append(t.vertC.position.xyz)
        }
        
        fillBuffer(device: device, buffer: &vertexPositionBuffer, data: vertexPositions)
        
        
        fillTriangleBuffer(device: device, materialArray: &materials, triangles: triangles, vertexBuffer: &vertexBuffer, materialBuffer: &materialBuffer)
        
        
        accelerationStructure = MPSTriangleAccelerationStructure(device: device)
        accelerationStructure.vertexBuffer = vertexPositionBuffer
        accelerationStructure.triangleCount = vertexPositions.count / 3
        accelerationStructure.rebuild()
    }
    
    func setup()
    {
        let defaultLibrary = device.makeDefaultLibrary()!
        let rayFunction = defaultLibrary.makeFunction(name: "rayKernel")!
        rayPipelineState = try! device.makeComputePipelineState(function: rayFunction)
        
        let shadeFunction = defaultLibrary.makeFunction(name: "shadeKernel")!
        shadePipelineState = try! device.makeComputePipelineState(function: shadeFunction)
        
        let aggregateFunction = defaultLibrary.makeFunction(name: "aggregateKernel")!
        aggregatePipelineState = try! device.makeComputePipelineState(function: aggregateFunction)
        
        let combineFunction = defaultLibrary.makeFunction(name: "combineKernel")!
        combinePipelineState = try! device.makeComputePipelineState(function: combineFunction)
        
        let copyFunction = defaultLibrary.makeFunction(name: "copyKernel")!
        copyPipelineState = try! device.makeComputePipelineState(function: copyFunction)
    }
    
    func createCachedTexture(size: CGSize)
    {
        let width = Int32(size.width)
        let height = Int32(size.height)
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.width = Int(width)
        textureDescriptor.height = Int(height)
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.usage = .unknown
        textureDescriptor.storageMode = .managed
        cachedRender = device.makeTexture(descriptor: textureDescriptor)!
        
        var data: [SIMD4<Float>] = []
        
        for _ in 0 ..< width * height
        {
            data.append(SIMD4<Float>(0.0, 0.0, 0.0, 0.0))
        }
        
        cachedRender.replace(region: MTLRegionMake2D(0, 0, Int(width), Int(height)), mipmapLevel: 0, withBytes: &data, bytesPerRow: MemoryLayout<SIMD4<Float>>.stride * Int(width))
    }
    
    func regenerateUniformBuffer(size: CGSize, cameraPosition: SIMD3<Float>, cameraDirection: SIMD3<Float>)
    {
        let width = Int32(size.width)
        let height = Int32(size.height)
        let forward = normalize(cameraDirection)
        let position = cameraPosition
        var right = normalize(cross(forward, SIMD3<Float>(0, 1, 0)))
        var up = -normalize(cross(right, forward))
        
        
        let fieldOfView: Float = 65.0 * (.pi / 180.0);
        let aspectRatio = Float(width) / Float(height);
        let imagePlaneHeight = tanf(fieldOfView / 2.0);
        let imagePlaneWidth = aspectRatio * imagePlaneHeight;
        right *= imagePlaneWidth;
        up *= imagePlaneHeight;
        
        let r = RayKernelUniforms(position: position, forward: forward, right: right, up: up, width: width, height: height, numLights: Int8(lights.count))
        rayUniformBuffer = nil
        fillBuffer(device: device, buffer: &rayUniformBuffer, data: [r])
        //numRenders = 0


        
    }
    
    func generateOtherBuffers(size: CGSize)
    {
        let width = Int(size.width)
        let height = Int(size.height)
        
        shadowRenderTextures.removeAll()
        
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.width = width
        textureDescriptor.height = height
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.usage = .unknown
        textureDescriptor.storageMode = .managed
        
        
        let tex1 = device.makeTexture(descriptor: textureDescriptor)!
        let tex2 = device.makeTexture(descriptor: textureDescriptor)!
        
        
        shadowRenderTextures.append(tex1)
        shadowRenderTextures.append(tex2)
        
        
        createCachedTexture(size: size)
        
        lightBuffer = nil
        fillBuffer(device: device, buffer: &lightBuffer, data: lights, size: MemoryLayout<Light>.stride * MAX_LIGHTS)
        numRenders = 0
    }
    
    func generateRayBuffer(size: CGSize)
    {
        let width = Int(size.width)
        let height = Int(size.height)
        
        rayBuffer = nil
        intersectionBuffer = nil
        energyBuffer = nil
        shadowRayBuffer = nil
        shadowIntersectionBuffer = nil
        fillBuffer(device: device, buffer: &rayBuffer, data: [], size: rayStride * width * height)
        fillBuffer(device: device, buffer: &intersectionBuffer, data: [], size: intersectionStride * width * height)
        
        fillBuffer(device: device, buffer: &shadowRayBuffer, data: [], size: rayStride * width * height * lights.count)
        fillBuffer(device: device, buffer: &shadowIntersectionBuffer, data: [], size: intersectionStride * width * height * lights.count)
        

        
        let energyData = Array<Float>.init(repeating: 1.0, count: width * height)
        fillBuffer(device: device, buffer: &energyBuffer, data: energyData)
    }
    
    
    func traceRays(texture: MTLTexture, commandBuffer: MTLCommandBuffer)
    {


        let width = Int(texture.width)
        let height = Int(texture.height)
        
        generateRayBuffer(size: CGSize(width: width, height: height))
        //generateOtherBuffers(size: CGSize(width: width, height: height))
        numRenders += 1
        //print(numRenders)
        fillBuffer(device: device, buffer: &numBuffer, data: [numRenders])
        
        var randomTexture = createRandomTexture(device: device, width: width, height: height)
        computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()
        computeCommandEncoder.setComputePipelineState(rayPipelineState)
        
        computeCommandEncoder.setBuffer(rayUniformBuffer, offset: 0, index: 0)
        computeCommandEncoder.setBuffer(rayBuffer, offset: 0, index: 1)
        computeCommandEncoder.setTexture(randomTexture, index: 0)
        computeCommandEncoder.setTexture(shadowRenderTextures[0], index: 1)
        //computeCommandEncoder.setTexture(cachedRender, index: 2)

        
        let threadGroupSize = MTLSizeMake(8, 8, 1)
        
        var threadCountGroup = MTLSize()
        threadCountGroup.width = (texture.width + threadGroupSize.width - 1) / threadGroupSize.width
        threadCountGroup.height = (texture.height + threadGroupSize.height - 1) / threadGroupSize.height
        threadCountGroup.depth = 1
        
        computeCommandEncoder.dispatchThreadgroups(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
        computeCommandEncoder.endEncoding()
        
        
        
        for x in 0 ..< NUM_BOUNCES
        {
            //randomTexture = createRandomTexture(device: device, width: width, height: height)
            intersector.intersectionDataType = .distancePrimitiveIndexCoordinates
            intersector.encodeIntersection(commandBuffer: commandBuffer, intersectionType: .nearest, rayBuffer: rayBuffer, rayBufferOffset: 0, intersectionBuffer: intersectionBuffer, intersectionBufferOffset: 0, rayCount: width * height, accelerationStructure: accelerationStructure)
            
            computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()
            computeCommandEncoder.setComputePipelineState(shadePipelineState)
            computeCommandEncoder.setBuffer(rayUniformBuffer, offset: 0, index: 0)
            computeCommandEncoder.setBuffer(rayBuffer, offset: 0, index: 1)
            computeCommandEncoder.setBuffer(intersectionBuffer, offset: 0, index: 2)
            computeCommandEncoder.setBuffer(vertexBuffer, offset: 0, index: 3)
            computeCommandEncoder.setBuffer(materialBuffer, offset: 0, index: 4)
            computeCommandEncoder.setBuffer(energyBuffer, offset: 0, index: 5)
            computeCommandEncoder.setBuffer(shadowRayBuffer, offset: 0, index: 6)
            computeCommandEncoder.setBuffer(lightBuffer, offset: 0, index: 7)
            
            //computeCommandEncoder.setTexture(texture, index: 0)
            //need to deal with adding randomness on different bounces
            computeCommandEncoder.setTexture(randomTexture, index: 0)
            computeCommandEncoder.dispatchThreadgroups(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
            computeCommandEncoder.endEncoding()
            
            //intersector.intersectionDataType = .distance
            intersector.encodeIntersection(commandBuffer: commandBuffer, intersectionType: .any, rayBuffer: shadowRayBuffer, rayBufferOffset: 0, intersectionBuffer: shadowIntersectionBuffer, intersectionBufferOffset: 0, rayCount: lights.count * width * height, accelerationStructure: accelerationStructure)
            
            computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()
            computeCommandEncoder.setComputePipelineState(aggregatePipelineState)
            computeCommandEncoder.setBuffer(rayUniformBuffer, offset: 0, index: 0)
            computeCommandEncoder.setBuffer(shadowRayBuffer, offset: 0, index: 1)
            computeCommandEncoder.setBuffer(shadowIntersectionBuffer, offset: 0, index: 2)
            computeCommandEncoder.setTexture(shadowRenderTextures[x % 2], index: 0)
            computeCommandEncoder.setTexture(shadowRenderTextures[(x + 1) % 2], index: 1)
            
            computeCommandEncoder.dispatchThreadgroups(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
            computeCommandEncoder.endEncoding()

            
            
        }
        
        computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()
        computeCommandEncoder.setComputePipelineState(combinePipelineState)
        
        computeCommandEncoder.setBuffer(numBuffer, offset: 0, index: 0)
        computeCommandEncoder.setTexture(cachedRender, index: 0)
        computeCommandEncoder.setTexture(shadowRenderTextures[(NUM_BOUNCES) % 2], index: 1)
        computeCommandEncoder.setTexture(texture, index: 2)

        computeCommandEncoder.dispatchThreadgroups(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
        computeCommandEncoder.endEncoding()
        
        
        
        computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()
        computeCommandEncoder.setComputePipelineState(copyPipelineState)
        
        
        computeCommandEncoder.setTexture(texture, index: 0)
        computeCommandEncoder.setTexture(cachedRender, index: 1)

        computeCommandEncoder.dispatchThreadgroups(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
        computeCommandEncoder.endEncoding()

    }
}
