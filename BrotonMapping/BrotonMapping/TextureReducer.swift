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
    var area: Float
    var scale: uint
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
    var buffers: [MTLBuffer] = []
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
        buffers.removeAll()
        self.timesToReduce = timesToReduce
        reductionFactor = Int(pow(2.0, Float(self.timesToReduce)))
        assert(startingWidth % reductionFactor == 0 && startingHeight % reductionFactor == 0)
        
        var width = startingWidth
        var height = startingHeight
        
        for _ in 0 ..< timesToReduce + 1
        {
            
            //let textureDescriptor = MTLTextureDescriptor()
            //textureDescriptor.width = (width)
            //textureDescriptor.height = (height)
            //textureDescriptor.pixelFormat = .bgra8Unorm
            //textureDescriptor.usage = .init(arrayLiteral: [.shaderRead, .shaderWrite])
            //textureDescriptor.storageMode = .managed
            //buffers.append(device.makeTexture(descriptor: textureDescriptor)!)
            
            
            let buffer = device.makeBuffer(length: width * height * MemoryLayout<Color>.stride, options: .storageModeShared)!
            buffers.append(buffer)
            
            width = width / 2
            height = height / 2
        }
    }
    
    func reduce(commandBuffer: MTLCommandBuffer, startBuffer: MTLBuffer, endBuffer: MTLBuffer, endWidth: Int, endHeight: Int)
    {
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setBuffer(startBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(endBuffer, offset: 0, index: 1)
        
        var uniform = TextureUniforms(width: uint(endWidth), height: uint(endHeight))
        commandEncoder.setBytes(&uniform, length: MemoryLayout<TextureUniforms>.stride, index: 2)
        
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
        commandEncoder.setBuffer(buffers[0], offset: 0, index: 0)
        commandEncoder.setTexture(startTexture, index: 0)
        
        var uniform = TextureUniforms(width: uint(width), height: uint(height))
        commandEncoder.setBytes(&uniform, length: MemoryLayout<TextureUniforms>.stride, index: 1)
        
        let threadGroupSize = MTLSizeMake(1, 1, 1)
        
        var threadCountGroup = MTLSize()
        threadCountGroup.width = (width + threadGroupSize.width - 1) / threadGroupSize.width
        threadCountGroup.height = (height + threadGroupSize.height - 1) / threadGroupSize.height
        threadCountGroup.depth = 1
        
        commandEncoder.dispatchThreads(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
        commandEncoder.endEncoding()
        
        for x in 0 ..< buffers.count - 1
        {
            reduce(commandBuffer: commandBuffer, startBuffer: buffers[x], endBuffer: buffers[x + 1], endWidth: width / 2, endHeight: height / 2)
            width = width / 2
            height = height / 2
        }
        
        commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(decodeState)
        commandEncoder.setBuffer(buffers[buffers.count - 1], offset: 0, index: 0)
        commandEncoder.setTexture(endTexture, index: 0)
        
        uniform = TextureUniforms(width: uint(width), height: uint(height))
        commandEncoder.setBytes(&uniform, length: MemoryLayout<TextureUniforms>.stride, index: 1)
        
        threadCountGroup = MTLSize()
        threadCountGroup.width = (width + threadGroupSize.width - 1) / threadGroupSize.width
        threadCountGroup.height = (height + threadGroupSize.height - 1) / threadGroupSize.height
        threadCountGroup.depth = 1
        
        commandEncoder.dispatchThreads(threadCountGroup, threadsPerThreadgroup: threadGroupSize)
        
        commandEncoder.endEncoding()
        
        
        /*
         
         
         if (timesToReduce == 1)
         {
         reduce(commandBuffer: commandBuffer, startBuffer: startBuffer, endBuffer: endBuffer)
         }
         else
         {
         reduce(commandBuffer: commandBuffer, startBuffer: startBuffer, endBuffer: buffers[0])
         
         for x in 0 ..< buffers.count - 1
         {
         reduce(commandBuffer: commandBuffer, startBuffer: buffers[x], endBuffer: buffers[x + 1])
         }
         
         reduce(commandBuffer: commandBuffer, startBuffer: buffers[buffers.count - 1], endBuffer: endBuffer)
         }
         */
    }
}
