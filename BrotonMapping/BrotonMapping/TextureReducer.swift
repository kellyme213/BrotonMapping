//
//  TextureReducer.swift
//  BrotonMapping
//
//  Created by Michael Kelly on 7/22/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

import Foundation
import MetalPerformanceShaders

struct TextureUniforms
{
    var width: uint
    var height: uint
}

struct PhotonTextureUniforms
{
    var width: uint
    var height: uint
    var area: Float = patchSize
    var intensity: Float = 0.01
    var patchWidth: uint
}

struct Color
{
    var r: uint32
    var g: uint32
    var b: uint32
}

class TextureReducer
{
    var device: MTLDevice!
    var colorBuffers: [MTLBuffer] = []
    var countBuffers: [MTLBuffer] = []
    var reductionFactor: Int!
    var timesToReduce: Int!
    var pipelineState: MTLComputePipelineState
    var encodeState: MTLComputePipelineState
    var decodeState: MTLComputePipelineState
    
    
    init(device: MTLDevice)
    {
        self.device = device
        let defaultLibrary = self.device.makeDefaultLibrary()!
        let function = defaultLibrary.makeFunction(name: "reduceTexture")!
        pipelineState = try! device.makeComputePipelineState(function: function)
        let function2 = defaultLibrary.makeFunction(name: "colorToTexture")!
        let function1 = defaultLibrary.makeFunction(name: "textureToColor")!
        
        encodeState = try! device.makeComputePipelineState(function: function1)
        decodeState = try! device.makeComputePipelineState(function: function2)
        
    }
    
    func prepare(startingWidth: Int, startingHeight: Int, timesToReduce: Int)
    {
        colorBuffers.removeAll()
        countBuffers.removeAll()
        self.timesToReduce = timesToReduce
        reductionFactor = Int(pow(2.0, Float(self.timesToReduce)))
        assert(startingWidth % reductionFactor == 0 && startingHeight % reductionFactor == 0)
        
        var width = startingWidth
        var height = startingHeight
        
        for _ in 0 ..< timesToReduce + 1
        {
            let buffer = device.makeBuffer(length: width * height * MemoryLayout<Color>.stride, options: .storageModeShared)!
            colorBuffers.append(buffer)
            
            let buffer2 = device.makeBuffer(length: width * height * MemoryLayout<uint>.stride, options: .storageModeShared)!
            countBuffers.append(buffer2)
            
            width = width / 2
            height = height / 2
        }
    }
    
    func reduce(commandBuffer: MTLCommandBuffer, startBufferIndex: Int, endBufferIndex: Int, endWidth: Int, endHeight: Int)
    {
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setBuffer(colorBuffers[startBufferIndex], offset: 0, index: 0)
        commandEncoder.setBuffer(colorBuffers[endBufferIndex], offset: 0, index: 1)
        
        var uniform = TextureUniforms(width: uint(endWidth), height: uint(endHeight))
        commandEncoder.setBytes(&uniform, length: MemoryLayout<TextureUniforms>.stride, index: 2)
        
        commandEncoder.setBuffer(countBuffers[startBufferIndex], offset: 0, index: 3)
        commandEncoder.setBuffer(countBuffers[endBufferIndex], offset: 0, index: 4)
        
        let threadGroupSize = MTLSizeMake(1, 1, 1)
        
        var threadCountGroup = MTLSize()
        threadCountGroup.width = (endWidth + threadGroupSize.width - 1) / threadGroupSize.width
        threadCountGroup.height = (endHeight + threadGroupSize.height - 1) / threadGroupSize.height
        threadCountGroup.depth = 1
        
        commandEncoder.dispatchThreads(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
        commandEncoder.endEncoding()
    }
    
    
    func reduceTexture(commandBuffer: MTLCommandBuffer, startTexture: MTLTexture, endTexture: MTLTexture)
    {
        assert(endTexture.width * reductionFactor == startTexture.width)
        assert(endTexture.height * reductionFactor == startTexture.height)
        
        
        var width = startTexture.width
        var height = startTexture.height
        
        
        var commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(encodeState)
        commandEncoder.setBuffer(colorBuffers[0], offset: 0, index: 0)
        commandEncoder.setTexture(startTexture, index: 0)
        
        var uniform = TextureUniforms(width: uint(width), height: uint(height))
        commandEncoder.setBytes(&uniform, length: MemoryLayout<TextureUniforms>.stride, index: 1)
        
        commandEncoder.setBuffer(countBuffers[0], offset: 0, index: 2)

        
        let threadGroupSize = MTLSizeMake(1, 1, 1)
        
        var threadCountGroup = MTLSize()
        threadCountGroup.width = (width + threadGroupSize.width - 1) / threadGroupSize.width
        threadCountGroup.height = (height + threadGroupSize.height - 1) / threadGroupSize.height
        threadCountGroup.depth = 1
        
        commandEncoder.dispatchThreads(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
        commandEncoder.endEncoding()
        
        for x in 0 ..< colorBuffers.count - 1
        {
            reduce(commandBuffer: commandBuffer, startBufferIndex: x, endBufferIndex: x + 1, endWidth: width / 2, endHeight: height / 2)
            width = width / 2
            height = height / 2
        }
        
        commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(decodeState)
        commandEncoder.setBuffer(colorBuffers[colorBuffers.count - 1], offset: 0, index: 0)
        commandEncoder.setTexture(endTexture, index: 0)
        
        //NOT CORRECT should be PhotonTextureUniforms
        var photonUniform = PhotonTextureUniforms(width: uint(endTexture.width), height: uint(endTexture.height), patchWidth: uint(reductionFactor))
        
        //uniform = TextureUniforms(width: uint(width), height: uint(height))
        commandEncoder.setBytes(&photonUniform, length: MemoryLayout<PhotonTextureUniforms>.stride, index: 1)
        
        commandEncoder.setBuffer(countBuffers[colorBuffers.count - 1], offset: 0, index: 2)

        
        threadCountGroup = MTLSize()
        threadCountGroup.width = (width + threadGroupSize.width - 1) / threadGroupSize.width
        threadCountGroup.height = (height + threadGroupSize.height - 1) / threadGroupSize.height
        threadCountGroup.depth = 1
        
        commandEncoder.dispatchThreads(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
        
        commandEncoder.endEncoding()
    }
}
