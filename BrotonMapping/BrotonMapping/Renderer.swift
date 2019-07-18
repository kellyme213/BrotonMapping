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
    var depthStencilState: MTLDepthStencilState!
    var depthStencilDescriptor: MTLDepthStencilDescriptor!
    var vertexInBuffer: MTLBuffer!
    var uniformBuffer: MTLBuffer!
    var materialBuffer: MTLBuffer!
    var lightBuffer: MTLBuffer!
    var fragmentUniformBuffer: MTLBuffer!
    
    var projectionMatrix: simd_float4x4 = simd_float4x4()
    var modelViewMatrix: simd_float4x4 = simd_float4x4()
    var cameraPosition: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, -1.0)
    var cameraDirection: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 1.0)
    
    var triangles: [Triangle] = []
    var materialArray: [Material] = []
    var lights: [Light] = []
    
    let defaultCameraPosition: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, -1.0)
    let defaultCameraDirection: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 1.0)
    
    var v1 = SIMD3<Float>(0.6, -0.2, 0.0)
    var v2 = SIMD3<Float>(-0.6, -0.2, 0.0)
    var v3 = SIMD3<Float>(0.0, 0.2, 0.0)
    
    var renderMode = RASTERIZATION_MODE
    var rayTracer: RayTracer!
    
    
    init?(renderView: RenderView) {
        super.init()
        
        self.renderView = renderView
        setup()
        createRingStuff()
        
        rayTracer = RayTracer(device: device)
        rayTracer.generateRayBuffer(size: renderView.frame.size)
        rayTracer.generateAccelerationStructure(triangles: triangles)
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
        renderPipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        
        renderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
    }
    
    func setup()
    {
        device = renderView.device!
        commandQueue = device.makeCommandQueue()!

        createCommandBuffer()
        createRenderPassDescriptor(texture: renderView.currentDrawable!.texture)
        createShaders()
        createDepthStencilDescriptor()
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
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.usage = .renderTarget
        textureDescriptor.height = texture.height
        textureDescriptor.width = texture.width
        textureDescriptor.pixelFormat = .depth32Float
        textureDescriptor.storageMode = .private
        renderPassDescriptor.depthAttachment.texture = device.makeTexture(descriptor: textureDescriptor)
    }
    
    func createDepthStencilDescriptor()
    {
        depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)
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
                assert(materialIndex < MAX_MATERIALS)
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
        
        fillBuffer(device: device, buffer: &vertexInBuffer, data: vertices)
        
        fillBuffer(device: device, buffer: &materialBuffer, data: materialArray, size: MemoryLayout<Material>.stride * MAX_MATERIALS)
    }
    
    func fillUniformBuffer()
    {
        let uniforms = Uniforms(modelViewMatrix: modelViewMatrix, projectionMatrix: projectionMatrix)
        
        let list = [uniforms]
        
        fillBuffer(device: device, buffer: &uniformBuffer, data: list)
        
        let fragmentUniforms = FragmentUniforms(cameraPosition: cameraPosition, cameraDirection: cameraDirection, numLights: Int8(lights.count), ambientLight: SIMD4<Float>(0.1, 0.1, 0.1, 0.0))
        
        fillBuffer(device: device, buffer: &fragmentUniformBuffer, data: [fragmentUniforms])
        
        let size = CGSize(width: renderView.currentDrawable!.texture.width, height: renderView.currentDrawable!.texture.height)
        
        rayTracer.regenerateUniformBuffer(size: size, cameraPosition: cameraPosition, cameraDirection: cameraDirection)
    }
    
    func fillLightBuffer()
    {
        assert(Int8(lights.count) < MAX_LIGHTS)
        
        fillBuffer(device: device, buffer: &lightBuffer, data: lights, size: MemoryLayout<Light>.stride * MAX_LIGHTS)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
        updateUniformMatrices()        
        
        rayTracer.generateRayBuffer(size: size)
    }
    
    func draw(in view: MTKView) {
        
        fillUniformBuffer()
        createCommandBuffer()
        
        if (renderMode == RASTERIZATION_MODE)
        {
            createRenderPassDescriptor(texture: renderView.currentDrawable!.texture)
            let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            commandEncoder.setRenderPipelineState(renderPipelineState)
            commandEncoder.setDepthStencilState(depthStencilState)
            commandEncoder.setCullMode(.back)
            commandEncoder.setVertexBuffer(vertexInBuffer, offset: 0, index: 0)
            commandEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            
            commandEncoder.setFragmentBuffer(fragmentUniformBuffer, offset: 0, index: 0)
            commandEncoder.setFragmentBuffer(materialBuffer, offset: 0, index: 1)
            commandEncoder.setFragmentBuffer(lightBuffer, offset: 0, index: 9)
            commandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: triangles.count * 3)
            commandEncoder.endEncoding()
        }
        if (renderMode == RAY_TRACING_MODE || renderMode == PHOTON_MAPPING_MODE)
        {
            rayTracer.traceRays(texture: renderView.currentDrawable!.texture, commandBuffer: commandBuffer)
        }
        
        commandBuffer.present(renderView.currentDrawable!)
        commandBuffer.commit()
    }
    
    func keyDown(with theEvent: NSEvent) {
        
        let z = normalize(cameraDirection)
        let x = normalize(cross(SIMD3<Float>(0, 1, 0), z))
        let y = normalize(cross(z, x))
        let speed: Float = 0.05
        
        if (theEvent.keyCode == KEY_W)
        {
            cameraPosition += speed * z;
        }
        else if (theEvent.keyCode == KEY_S)
        {
            cameraPosition -= speed * z;
        }
        else if (theEvent.keyCode == KEY_A)
        {
            cameraPosition += speed * x;
        }
        else if (theEvent.keyCode == KEY_D)
        {
            cameraPosition -= speed * x;
        }
        else if (theEvent.keyCode == KEY_Q)
        {
            cameraPosition += speed * y;
        }
        else if (theEvent.keyCode == KEY_E)
        {
            cameraPosition -= speed * y;
        }
        else if (theEvent.keyCode == KEY_SPACE)
        {
            cameraPosition = defaultCameraPosition
            cameraDirection = defaultCameraDirection
        }
        else if (theEvent.keyCode == KEY_1)
        {
            createRingStuff()
        }
        else if (theEvent.keyCode == KEY_2)
        {
            createBoxStuff()
        }
        else if (theEvent.keyCode == KEY_I)
        {
            renderMode = RASTERIZATION_MODE
        }
        else if (theEvent.keyCode == KEY_O)
        {
            renderMode = RAY_TRACING_MODE
        }
        else if (theEvent.keyCode == KEY_P)
        {
            renderMode = PHOTON_MAPPING_MODE
        }
        
        updateUniformMatrices()
    }
    
    func updateUniformMatrices()
    {
        modelViewMatrix = look_at_matrix(eye: cameraPosition, target: cameraPosition + cameraDirection)
        fillUniformBuffer()
    }
    
    var mousePress = CGPoint(x: 0, y: 0)
    var oldCameraDirection = SIMD3<Float>(0, 0, 0)
    var cachedCameraDirction = SIMD3<Float>(0, 0, 0)
    
    func keyUp(with theEvent: NSEvent) {
        
    }
    
    func mouseUp(with event: NSEvent) {
        let size = CGSize(width: renderView.frame.width, height: renderView.frame.height)
        rayTracer.regenerateUniformBuffer(size: size, cameraPosition: cameraPosition, cameraDirection: cameraDirection)
    }
    
    func mouseDown(with event: NSEvent) {
        mousePress = event.locationInWindow
        
        var x = -(mousePress.x - (event.window!.frame.width / 2.0))
        var y = -(mousePress.y - (event.window!.frame.height / 2.0))
        
        x = x / event.window!.frame.width
        y = y / event.window!.frame.height

        oldCameraDirection = createArcballCameraDirection(x: Float(x), y: Float(y))
        cachedCameraDirction = cameraDirection
    }
    
    func mouseDragged(with event: NSEvent) {
        
        let x = -(event.locationInWindow.x - (event.window!.frame.width / 2.0))
        let y = -(event.locationInWindow.y - (event.window!.frame.height / 2.0))
        
        let dx = x / event.window!.frame.width
        let dy = y / event.window!.frame.height
        
        let newCameraDirection = createArcballCameraDirection(x: Float(dx), y: Float(dy))
        
        let rotationMatrix = matrix4x4_rotation(radians: -acos(dot(oldCameraDirection, newCameraDirection)), axis: cross(oldCameraDirection, newCameraDirection))
        
        let cam4 = (rotationMatrix * SIMD4<Float>(cachedCameraDirction, 0.0))

        cameraDirection = normalize(SIMD3<Float>(cam4.x, cam4.y, cam4.z))
        updateUniformMatrices()
    }
    
}
