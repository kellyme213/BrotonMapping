//
//  Vertex.swift
//  BrotonMapping
//
//  Created by Michael Kelly on 7/9/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

import Foundation
import simd
import Metal
import MetalKit


let DIRECTIONAL_LIGHT: Int8 = 0
let SPOT_LIGHT: Int8 = 1
let MAX_MATERIALS: Int = 8
let MAX_LIGHTS: Int = 8

struct Vertex
{
    var position: SIMD4<Float>
    var normal: SIMD3<Float>
    var materialNum: Int = -1
}

struct Triangle
{
    var vertA: Vertex
    var vertB: Vertex
    var vertC: Vertex
    
    var material: Material
}

struct Material: Equatable
{
    static func == (lhs: Material, rhs: Material) -> Bool
    {
        return lhs.kAmbient == rhs.kAmbient &&
                lhs.kDiffuse == rhs.kDiffuse &&
                lhs.kSpecular == rhs.kSpecular &&
                lhs.shininess == rhs.shininess &&
                lhs.diffuse == rhs.diffuse
    }
    
    var kAmbient: SIMD4<Float>  = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
    var kDiffuse: SIMD4<Float>  = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
    var kSpecular: SIMD4<Float> = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
    var shininess: Float = 100.0
    var diffuse: Float = 0.0
}

struct Uniforms
{
    var modelViewMatrix: simd_float4x4
    var projectionMatrix: simd_float4x4
}

struct Light
{
    var position: SIMD3<Float>
    var direction: SIMD3<Float>
    var color: SIMD4<Float>
    var coneAngle: Float
    var lightType: Int8
}

struct FragmentUniforms
{
    var cameraPosition: SIMD3<Float>
    var cameraDirection: SIMD3<Float>
    var numLights: Int8
    var ambientLight: SIMD4<Float>
}

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
