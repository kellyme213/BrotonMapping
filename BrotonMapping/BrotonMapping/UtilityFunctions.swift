//
//  UtilityFunctions.swift
//  BrotonMapping
//
//  Created by Michael Kelly on 7/17/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

import Foundation
import simd
import Metal
import MetalKit
import MetalPerformanceShaders

let rayStride = 48;
let intersectionStride = MemoryLayout<MPSIntersectionDistancePrimitiveIndexCoordinates>.stride

// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, -1),
                                         vector_float4( 0,  0, zs * nearZ, 0)))
    
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}

func look_at_matrix(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float> = SIMD3<Float>(0, 1, 0)) -> matrix_float4x4
{
    let t = matrix4x4_translation(-eye.x, -eye.y, -eye.z)
    
    let f = normalize(eye - target)
    let l = normalize(cross(up, f))
    let u = normalize(cross(f, l))
    let rot = matrix_float4x4.init(columns: (SIMD4<Float>(l, 0.0),
                                             SIMD4<Float>(u, 0.0),
                                             SIMD4<Float>(f, 0.0),
                                             SIMD4<Float>(0.0, 0.0, 0.0, 1.0))).transpose
    return (rot * t)
}

func createTriangleFromPoints(a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>, m: Material) -> Triangle
{
    let norm = -normalize(cross(b - a, c - a))
    
    let v1 = Vertex(position: SIMD4<Float>(a, 1.0), normal: norm)
    let v2 = Vertex(position: SIMD4<Float>(b, 1.0), normal: norm)
    let v3 = Vertex(position: SIMD4<Float>(c, 1.0), normal: norm)
    
    let t = Triangle(vertA: v1, vertB: v2, vertC: v3, material: m)
    
    return t
}



extension SIMD4
{
    var xyz: SIMD3<Float>
    {
        return SIMD3<Float>(self.x as! Float, self.y as! Float, self.z as! Float)
    }
}




func fillBuffer<T>(device: MTLDevice, buffer: inout MTLBuffer?, data: [T], size: Int = 0)
{
    if (buffer == nil)
    {
        buffer = createBuffer(device: device, data: data, size: size)
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

func createBuffer<T>(device: MTLDevice, data: [T], size: Int = 0) -> MTLBuffer!
{
    var bufferSize: Int = size
    
    if (size == 0)
    {
        bufferSize = MemoryLayout<T>.stride * data.count
    }
    
    if (data.count == 0)
    {
        return device.makeBuffer(length: bufferSize, options: .storageModeShared)
    }
    
    return device.makeBuffer(bytes: data, length: bufferSize, options: .storageModeShared)!
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


func createRing(radius: Float, subdivisions: Int, height: Float, thiccness: Float, material: Material, triangles: inout [Triangle])
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

func fillTriangleBuffer(device: MTLDevice, materialArray: inout [Material], triangles: [Triangle], vertexBuffer: inout MTLBuffer?, materialBuffer: inout MTLBuffer?)
{
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
    
    fillBuffer(device: device, buffer: &vertexBuffer, data: vertices)
    
    fillBuffer(device: device, buffer: &materialBuffer, data: materialArray, size: MemoryLayout<Material>.stride * MAX_MATERIALS)
}




func createRandomTexture(device: MTLDevice, width: Int, height: Int, usage: MTLTextureUsage = .shaderRead) -> MTLTexture
{
    let textureDescriptor = MTLTextureDescriptor()
    textureDescriptor.width = width
    textureDescriptor.height = height
    textureDescriptor.pixelFormat = .bgra8Unorm
    textureDescriptor.usage = usage
    textureDescriptor.storageMode = .managed
    
    var randomValues: [SIMD4<Float>] = []
    
    for _ in 0 ..< width * height
    {
        randomValues.append(SIMD4<Float>(Float(drand48()), Float(drand48()), Float(drand48()), Float(drand48())))
    }
        
    let texture = device.makeTexture(descriptor: textureDescriptor)!
    
    texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: &randomValues, bytesPerRow: MemoryLayout<SIMD4<Float>>.stride * width)
    
    return texture
    
    
}



extension Renderer
{
    func createRingStuff()
    {
        triangles.removeAll()
        materialArray.removeAll()
        lights.removeAll()
        vertexInBuffer = nil
        
        var m = Material()
        m.kDiffuse = SIMD4<Float>(1.0, 0.8, 0.0, 1.0)
        m.absorbiness = 0.8
        m.reflectivity = 1.0
        
        createRing(radius: 0.95, subdivisions: 100, height: 0.1, thiccness: 0.05, material: m, triangles: &triangles)
        
        var m2 = Material()
        m2.kDiffuse = SIMD4<Float>(150.0 / 255.0, 75.0 / 255.0, 0.0, 1.0)
        m2.kSpecular = SIMD4<Float>(0.1, 0.1, 0.1, 1.0)
        m2.absorbiness = 0.3
        m2.reflectivity = 0.0
        
        
        let width: Float = 2.4
        let height: Float = 2.4
        let p1 = SIMD3<Float>(width / 2.0, height / 2.0, 0.0)
        let p2 = SIMD3<Float>(-width / 2.0, height / 2.0, 0.0)
        let p3 = SIMD3<Float>(-width / 2.0, -height / 2.0, 0.0)
        let p4 = SIMD3<Float>(width / 2.0, -height / 2.0, 0.0)
        
        triangles.append(createTriangleFromPoints(a: p3, b: p2, c: p1, m: m2))
        triangles.append(createTriangleFromPoints(a: p4, b: p3, c: p1, m: m2))
        
        cameraPosition = SIMD3<Float>(0.0, -1.0, 1.3)
        cameraDirection = normalize(SIMD3<Float>(0.0, 0.5, -0.85))
        
        var light1 = Light(position: SIMD3<Float>(0.0, 1.0, 2.0), direction: normalize(SIMD3<Float>(0.0, -1.0, -1.0)), color: SIMD4<Float>(1.0, 1.0, 1.0, 1.0), coneAngle: 0, lightType: DIRECTIONAL_LIGHT)
        
        let right = normalize(cross(light1.direction, SIMD3<Float>(0, 1, 0)))
        let up = -normalize(cross(right, light1.direction))
        
        light1.right = 1.0 * right
        light1.up = 1.0 * up
        
        lights.append(light1)
        
        materialArray.removeAll()
        fillTriangleBuffer(device: device, materialArray: &materialArray, triangles: triangles, vertexBuffer: &vertexInBuffer, materialBuffer: &materialBuffer)
        fillLightBuffer()
    }
    
    func createBoxStuff()
    {
        triangles.removeAll()
        materialArray.removeAll()
        lights.removeAll()
        vertexInBuffer = nil
        
        let width: Float = 0.8
        
        let p1 = SIMD3<Float>( width / 2.0,  width / 2.0,  width / 2.0)
        let p2 = SIMD3<Float>(-width / 2.0,  width / 2.0,  width / 2.0)
        let p3 = SIMD3<Float>(-width / 2.0, -width / 2.0,  width / 2.0)
        let p4 = SIMD3<Float>( width / 2.0, -width / 2.0,  width / 2.0)
        
        let p5 = SIMD3<Float>( width / 2.0, width / 2.0,  -width / 2.0)
        let p6 = SIMD3<Float>(-width / 2.0, width / 2.0,  -width / 2.0)
        let p7 = SIMD3<Float>(-width / 2.0, -width / 2.0, -width / 2.0)
        let p8 = SIMD3<Float>( width / 2.0, -width / 2.0, -width / 2.0)
        
        var m = Material()
        m.kDiffuse = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
        
        var redM = Material()
        redM.kDiffuse = SIMD4<Float>(1.0, 0.0, 0.0, 1.0)
        
        var blueM = Material()
        blueM.kDiffuse = SIMD4<Float>(0.0, 0.0, 1.0, 1.0)
        
        m.kSpecular = SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
        redM.kSpecular = SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
        blueM.kSpecular = SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
        

        blueM.absorbiness = 0.4
        redM.absorbiness = 0.4
        m.absorbiness = 0.4
        blueM.reflectivity = 0.1
        redM.reflectivity = 0.1
        m.reflectivity = 0.1

        
        triangles.append(createTriangleFromPoints(a: p2, b: p3, c: p1, m: m))
        triangles.append(createTriangleFromPoints(a: p1, b: p3, c: p4, m: m))
        
        triangles.append(createTriangleFromPoints(a: p3, b: p7, c: p8, m: m))
        triangles.append(createTriangleFromPoints(a: p3, b: p8, c: p4, m: m))
        
        triangles.append(createTriangleFromPoints(a: p1, b: p6, c: p2, m: m))
        triangles.append(createTriangleFromPoints(a: p5, b: p6, c: p1, m: m))
        
        
        triangles.append(createTriangleFromPoints(a: p6, b: p7, c: p2, m: redM))
        triangles.append(createTriangleFromPoints(a: p2, b: p7, c: p3, m: redM))
        
        triangles.append(createTriangleFromPoints(a: p1, b: p4, c: p5, m: blueM))
        triangles.append(createTriangleFromPoints(a: p5, b: p4, c: p8, m: blueM))
        
        cameraPosition = SIMD3<Float>(0.0, 0.0, -1.0)
        cameraDirection = SIMD3<Float>(0.0, 0.0, 1.0)
        
        var light1 = Light(position: SIMD3<Float>(0.0, width / 2.0 - 0.01, 0.0), color: SIMD4<Float>(1.0, 1.0, 1.0, 1.0), lightType: POINT_LIGHT)
        light1.direction = normalize(SIMD3<Float>(0.0, -1.0, 0.0))
        
        let right = normalize(cross(light1.direction, SIMD3<Float>(0.0, 0.0, 1.0)))
        let up = -normalize(cross(right, light1.direction))
        
        
        var light2 = Light(position: SIMD3<Float>(0.0, 0.0, -width / 2.0 + 0.01), color: SIMD4<Float>(10.0, 10.0, 10.0, 1.0), lightType: POINT_LIGHT)
        light2.direction = normalize(SIMD3<Float>(0.0, 0.0, 1.0))
        
        let right2 = normalize(cross(light2.direction, SIMD3<Float>(0.0, 1, 0.0)))
        let up2 = -normalize(cross(right2, light2.direction))
        
        light1.right = right
        light1.up = up
        
        light2.right = right2
        light2.up = up2
        
        lights.append(light1)
        lights.append(light2)

        materialArray.removeAll()
        fillTriangleBuffer(device: device, materialArray: &materialArray, triangles: triangles, vertexBuffer: &vertexInBuffer, materialBuffer: &materialBuffer)
        fillLightBuffer()
    }
}


