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
    let rayStride = 48;
    let intersectionStride = MemoryLayout<MPSIntersectionDistancePrimitiveIndexCoordinates>.stride
    
    var rayPipelineState: MTLComputePipelineState!
    var shadePipelineState: MTLComputePipelineState!
    var computeCommandEncoder: MTLComputeCommandEncoder!
    var intersector: MPSRayIntersector!
    var accelerationStructure: MPSTriangleAccelerationStructure!
    var vertexPositionBuffer: MTLBuffer!
    var rayUniformBuffer: MTLBuffer!
    var rayBuffer: MTLBuffer!
    var intersectionBuffer: MTLBuffer!
    var device: MTLDevice!
    
    init(device: MTLDevice) {
        self.device = device
        setup()
    }
    
    func generateAccelerationStructure(triangles: [Triangle])
    {
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
        
        let r = RayKernelUniforms(position: position, forward: forward, right: right, up: up, width: width, height: height)
        rayUniformBuffer = nil
        fillBuffer(device: device, buffer: &rayUniformBuffer, data: [r])
    }
    
    func generateRayBuffer(size: CGSize)
    {
        let width = Int(size.width)
        let height = Int(size.height)
        
        rayBuffer = nil
        intersectionBuffer = nil
        fillBuffer(device: device, buffer: &rayBuffer, data: [], size: rayStride * width * height)
        fillBuffer(device: device, buffer: &intersectionBuffer, data: [], size: intersectionStride * width * height)
    }
    
    
    func traceRays(texture: MTLTexture, commandBuffer: MTLCommandBuffer)
    {
        let width = Int(texture.width)
        let height = Int(texture.height)
        
        generateRayBuffer(size: CGSize(width: width, height: height))
        computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()
        computeCommandEncoder.setComputePipelineState(rayPipelineState)
        
        computeCommandEncoder.setBuffer(rayUniformBuffer, offset: 0, index: 0)
        computeCommandEncoder.setBuffer(rayBuffer, offset: 0, index: 1)
        
        let threadGroupSize = MTLSizeMake(8, 8, 1)
        
        var threadCountGroup = MTLSize()
        threadCountGroup.width = (texture.width + threadGroupSize.width - 1) / threadGroupSize.width
        threadCountGroup.height = (texture.height + threadGroupSize.height - 1) / threadGroupSize.height
        threadCountGroup.depth = 1
        
        computeCommandEncoder.dispatchThreadgroups(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
        computeCommandEncoder.endEncoding()
        
        intersector.encodeIntersection(commandBuffer: commandBuffer, intersectionType: .nearest, rayBuffer: rayBuffer, rayBufferOffset: 0, intersectionBuffer: intersectionBuffer, intersectionBufferOffset: 0, rayCount: width * height, accelerationStructure: accelerationStructure)
        
        computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()
        computeCommandEncoder.setComputePipelineState(shadePipelineState)
        computeCommandEncoder.setBuffer(rayUniformBuffer, offset: 0, index: 0)
        computeCommandEncoder.setBuffer(rayBuffer, offset: 0, index: 1)
        computeCommandEncoder.setBuffer(intersectionBuffer, offset: 0, index: 2)
        
        computeCommandEncoder.setTexture(texture, index: 0)
        computeCommandEncoder.dispatchThreadgroups(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
        computeCommandEncoder.endEncoding()
    }
}
