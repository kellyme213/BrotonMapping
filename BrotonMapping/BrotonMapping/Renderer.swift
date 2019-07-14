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
    
    init?(renderView: RenderView) {
        super.init()
        
        self.renderView = renderView
        setup()
        
        
        let m = Material()
                
        createRing(radius: 0.2, subdivisions: 100, height: 0.3, thiccness: 0.05, material: m)
        
        fillTriangleBuffer()
        fillLightBuffer()
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
    
    func createRing(radius: Float, subdivisions: Int, height: Float, thiccness: Float, material: Material)
    {
        for n in 0..<subdivisions
        {
            let x = cos(2.0 * .pi * Float(n) / Float(subdivisions))
            let y = sin(2.0 * .pi * Float(n) / Float(subdivisions))
            
            let x1 = cos(2.0 * .pi * Float(n + 1) / Float(subdivisions))
            let y1 = sin(2.0 * .pi * Float(n + 1) / Float(subdivisions))
            
            let r1 = radius
            let r2 = radius + thiccness
            
            let p1 = SIMD3<Float>(r1 * x, r1 * y, 0.0)
            let p2 = SIMD3<Float>(r1 * x, r1 * y, height)
            let p3 = SIMD3<Float>(r1 * x1, r1 * y1, 0.0)
            let p4 = SIMD3<Float>(r1 * x1, r1 * y1, height)
            
            let p5 = SIMD3<Float>(r2 * x, r2 * y, 0.0)
            let p6 = SIMD3<Float>(r2 * x, r2 * y, height)
            let p7 = SIMD3<Float>(r2 * x1, r2 * y1, 0.0)
            let p8 = SIMD3<Float>(r2 * x1, r2 * y1, height)
            
            
            let n1 = normalize(SIMD3<Float>(x, y, 0.0))
            let n2 = normalize(SIMD3<Float>(x1, y1, 0.0))

            var t1 = createTriangleFromPoints(a: p1, b: p3, c: p2, m: material)
            var t2 = createTriangleFromPoints(a: p3, b: p4, c: p2, m: material)
            
            var t3 = createTriangleFromPoints(a: p7, b: p5, c: p8, m: material)
            var t4 = createTriangleFromPoints(a: p5, b: p6, c: p8, m: material)
            
 
            t1.vertA.normal = -n1
            t1.vertB.normal = -n2
            t1.vertC.normal = -n1

            t2.vertA.normal = -n2
            t2.vertB.normal = -n2
            t2.vertC.normal = -n1
            
            t3.vertA.normal = n2
            t3.vertB.normal = n1
            t3.vertC.normal = n2
            
            t4.vertA.normal = n1
            t4.vertB.normal = n1
            t4.vertC.normal = n2
            

            let t5 = createTriangleFromPoints(a: p2, b: p4, c: p6, m: material)
            let t6 = createTriangleFromPoints(a: p4, b: p8, c: p6, m: material)

            let t7 = createTriangleFromPoints(a: p5, b: p7, c: p1, m: material)
            let t8 = createTriangleFromPoints(a: p7, b: p3, c: p1, m: material)

            triangles.append(t1)
            triangles.append(t2)
            
            triangles.append(t3)
            triangles.append(t4)
            
            
            triangles.append(t5)
            triangles.append(t6)
            
            triangles.append(t7)
            triangles.append(t8)
        }
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
    
    func fillBuffer<T>(buffer: inout MTLBuffer?, data: [T], size: Int = 0)
    {
        if (buffer == nil)
        {
            buffer = createBuffer(data: data, size: size)
        }
        else
        {
            var bufferSize: Int = size
            
            if (size == 0)
            {
                bufferSize = MemoryLayout<T>.stride * data.count
            }
            
            memcpy(buffer!.contents(), data, bufferSize)
        }
    }
    
    func createBuffer<T>(data: [T], size: Int = 0) -> MTLBuffer!
    {
        var bufferSize: Int = size
        
        if (size == 0)
        {
            bufferSize = MemoryLayout<T>.stride * data.count
        }
        
        return device.makeBuffer(bytes: data, length: bufferSize, options: .storageModeShared)!
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
        
        fillBuffer(buffer: &vertexInBuffer, data: vertices)
        
        fillBuffer(buffer: &materialBuffer, data: materialArray, size: MemoryLayout<Material>.stride * MAX_MATERIALS)
    }
    
    func fillUniformBuffer()
    {
        let uniforms = Uniforms(modelViewMatrix: modelViewMatrix, projectionMatrix: projectionMatrix)
        
        let list = [uniforms]
        
        fillBuffer(buffer: &uniformBuffer, data: list)
        
        
        
        let fragmentUniforms = FragmentUniforms(cameraPosition: cameraPosition, cameraDirection: cameraDirection, numLights: Int8(lights.count), ambientLight: SIMD4<Float>(0.1, 0.1, 0.1, 0.0))
        
        fillBuffer(buffer: &fragmentUniformBuffer, data: [fragmentUniforms])
    }
    
    func fillLightBuffer()
    {
        let light1 = Light(position: SIMD3<Float>(0.0, 0.3, 0.2), direction: SIMD3<Float>(0.0, -1.0, 0.0), color: SIMD4<Float>(1.0, 0.0, 0.0, 1.0), coneAngle: 0.1, lightType: SPOT_LIGHT)
        
        let light2 = Light(position: SIMD3<Float>(0.0, 0.3, -1.0), direction: SIMD3<Float>(1.0, 1.0, 0.0), color: SIMD4<Float>(0.0, 0.8, 1.0, 1.0), coneAngle: 0.1, lightType: DIRECTIONAL_LIGHT)
        
        let light3 = Light(position: SIMD3<Float>(0.0, 0.0, -1.0), direction: SIMD3<Float>(0.0, 0.0, 1.0), color: SIMD4<Float>(0.2, 0.0, 0.2, 1.0), coneAngle: 0.1, lightType: DIRECTIONAL_LIGHT)
        
        lights.append(light1)
        lights.append(light2)
        lights.append(light3)

        assert(Int8(lights.count) < MAX_LIGHTS)
        
        fillBuffer(buffer: &lightBuffer, data: lights, size: MemoryLayout<Light>.stride * MAX_LIGHTS)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
        updateUniformMatrices()
    }
    
    func draw(in view: MTKView) {
        
        fillUniformBuffer()
        createRenderPassDescriptor(texture: renderView.currentDrawable!.texture)
        createCommandBuffer()

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
        
    }
    
    func mouseDown(with event: NSEvent) {
        mousePress = event.locationInWindow
        
        var x = mousePress.x - (event.window!.frame.width / 2.0)
        var y = -(mousePress.y - (event.window!.frame.height / 2.0))
        
        x = x / event.window!.frame.width
        y = y / event.window!.frame.height

        oldCameraDirection = createArcballCameraDirection(x: Float(x), y: Float(y))
        cachedCameraDirction = cameraDirection
    }
    
    //https://braintrekking.wordpress.com/2012/08/21/tutorial-of-arcball-without-quaternions/
    func createArcballCameraDirection(x: Float, y: Float) -> SIMD3<Float>
    {
        var newCameraDirection = SIMD3<Float>(0,0,0)
        let d = x * x + y * y
        let ballRadius: Float = 1.0
        
        if (d > ballRadius * ballRadius)
        {
            newCameraDirection = SIMD3<Float>(x, y, 0.0)
        }
        else
        {
            newCameraDirection = SIMD3<Float>(x, y, Float(sqrt(ballRadius * ballRadius - d)))
        }
        
        if (dot(newCameraDirection, newCameraDirection) > 0.001)
        {
            newCameraDirection = normalize(newCameraDirection)
        }
        else
        {
            print("BAD")
        }
        return newCameraDirection
    }
    
    func mouseDragged(with event: NSEvent) {
        
        let x = event.locationInWindow.x - (event.window!.frame.width / 2.0)
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
