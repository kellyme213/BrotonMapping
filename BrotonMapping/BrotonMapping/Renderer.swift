//
//  Renderer.swift
//  BrotonMapping
//
//  Created by Michael Kelly on 7/9/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

import Foundation
import MetalKit
import Metal


class Renderer: NSObject, MTKViewDelegate {
    
    var renderView: RenderView!
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var commandBuffer: MTLCommandBuffer!
    var renderPassDescriptor: MTLRenderPassDescriptor!
    var renderPipelineDescriptor: MTLRenderPipelineDescriptor!
    var renderPipelineState: MTLRenderPipelineState!
    var vertexInBuffer: MTLBuffer!
    var uniformBuffer: MTLBuffer!
    var materialBuffers: [MTLBuffer] = []
    var materialBuffer: MTLBuffer!
    
    var projectionMatrix: simd_float4x4 = simd_float4x4()
    var modelViewMatrix: simd_float4x4 = simd_float4x4()
    var cameraPosition: SIMD3<Float> = SIMD3<Float>(0, 0, -1)
    
    var triangles: [Triangle] = []
    var materialArray: [Material] = []
    
    var v1 = SIMD3<Float>(0.5, 0.0, 0.0)
    var v2 = SIMD3<Float>(-0.5, 0.0, 0.0)
    var v3 = SIMD3<Float>(0.0, 0.5, 0.0)
    
    init?(renderView: RenderView) {
        super.init()
        
        self.renderView = renderView
        setup()
        
        let m = Material(color: SIMD4<Float>(1.0, 1.0, 0.0, 1.0), diffuse: 0.0)
        let t = createTriangleFromPoints(a: v1, b: v2, c: v3, m: m)
        
        triangles.append(t)
        fillTriangleBuffer()
    }
    
    func createShaders()
    {
        let defaultLibrary = device.makeDefaultLibrary()!
        let vertexShader = defaultLibrary.makeFunction(name: "vertexShader")!
        let fragmentShader = defaultLibrary.makeFunction(name: "fragmentShader")!
        
        renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        renderPipelineDescriptor.vertexFunction = vertexShader
        renderPipelineDescriptor.fragmentFunction = fragmentShader
        
        renderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
    }
    
    func setup()
    {
        device = renderView.device!
        commandQueue = device.makeCommandQueue()!

        createCommandBuffer()
        createRenderPassDescriptor(texture: renderView.currentDrawable!.texture)
        createShaders()
    }
    
    func createCommandBuffer()
    {
        commandBuffer = commandQueue.makeCommandBuffer()!
    }
    
    func createRenderPassDescriptor(texture: MTLTexture)
    {
        renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    }
    
    func fillBuffer<T>(data: [T]) -> MTLBuffer!
    {
        return device.makeBuffer(bytes: data, length: MemoryLayout<T>.stride * data.count, options: .storageModeShared)!
    }
    
    func fillTriangleBuffer()
    {
        materialArray.removeAll()
        var vertices: [Vertex] = []
        
        for t in triangles
        {
            var foundMaterial = false
            var materialIndex = 0
            for x in 0 ..< materialArray.count
            {
                if (materialArray[x] == t.material)
                {
                    foundMaterial = true
                    materialIndex = x
                    break
                }
            }
            
            if (!foundMaterial)
            {
                materialIndex = materialArray.count
                assert(materialIndex < 8)
                materialArray.append(t.material)
            }
            
            var v1 = t.vertA
            var v2 = t.vertB
            var v3 = t.vertC
            
            v1.materialNum = materialIndex
            v2.materialNum = materialIndex
            v3.materialNum = materialIndex

            vertices.append(v1)
            vertices.append(v2)
            vertices.append(v3)
        }
        
        vertexInBuffer = fillBuffer(data: vertices)
        
        materialBuffer = device.makeBuffer(bytes: materialArray, length: MemoryLayout<Material>.stride * 8, options: .storageModeShared)
    }
    
    func fillUniformBuffer()
    {
        let uniforms = Uniforms(modelViewMatrix: modelViewMatrix, projectionMatrix: projectionMatrix)
        
        let list2 = [uniforms]
        
        uniformBuffer = fillBuffer(data: list2)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
        modelViewMatrix = look_at_matrix(from: cameraPosition, to: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
    }
    
    func draw(in view: MTKView) {

        modelViewMatrix = look_at_matrix(from: cameraPosition, to: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        
        fillUniformBuffer()
        //fillTriangleBuffer()
        createRenderPassDescriptor(texture: renderView.currentDrawable!.texture)
        createCommandBuffer()

        let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        commandEncoder.setRenderPipelineState(renderPipelineState)
        commandEncoder.setVertexBuffer(vertexInBuffer, offset: 0, index: 0)
        commandEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        
        commandEncoder.setFragmentBuffer(materialBuffer, offset: 0, index: 0)
        commandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: triangles.count * 3)
        commandEncoder.endEncoding()
        
        commandBuffer.present(renderView.currentDrawable!)
        commandBuffer.commit()
    }
    
    func keyDown(with theEvent: NSEvent) {

    }
    
    func keyUp(with theEvent: NSEvent) {
        
    }
}
