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
    
    var metalKitView: MTKView!
    
    init?(metalKitView: MTKView) {
        super.init()
        
        self.metalKitView = metalKitView
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    func draw(in view: MTKView) {
    }
    
    func keyDown(with theEvent: NSEvent) {
        print("HI")
    }
    
    func keyUp(with theEvent: NSEvent) {
        
    }
    
    
}
