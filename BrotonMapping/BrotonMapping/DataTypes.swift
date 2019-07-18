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
let POINT_LIGHT: Int8 = 2

let MAX_MATERIALS: Int = 8
let MAX_LIGHTS: Int = 8

let RASTERIZATION_MODE = 0
let RAY_TRACING_MODE = 1
let PHOTON_MAPPING_MODE = 2

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
    var position: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    var direction: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    var color: SIMD4<Float> = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
    var coneAngle: Float = 1.0
    var lightType: Int8 = POINT_LIGHT
}

struct FragmentUniforms
{
    var cameraPosition: SIMD3<Float>
    var cameraDirection: SIMD3<Float>
    var numLights: Int8
    var ambientLight: SIMD4<Float>
}

struct Ray
{
    var origin: SIMD3<Float>
    var mask: uint
    var direction: SIMD3<Float>
    var maxDistance: Float
    var color: SIMD3<Float>
}

struct RayKernelUniforms
{
    var position: SIMD3<Float>
    var forward: SIMD3<Float>
    var right: SIMD3<Float>
    var up: SIMD3<Float>
    var width: Int32
    var height: Int32
}


struct Intersection {
    var distance: Float
    var primitiveIndex: Int
    var coordinates: SIMD2<Float>
}

