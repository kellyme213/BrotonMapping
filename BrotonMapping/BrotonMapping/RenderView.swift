//
//  RenderView.swift
//  BrotonMapping
//
//  Created by Michael Kelly on 7/9/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

import Foundation
import MetalKit
import Metal


class RenderView: MTKView
{
    var renderer: Renderer!
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        
        self.device = device!
                
        self.depthStencilPixelFormat = .depth32Float

        renderer = Renderer(renderView: self)
        self.delegate = renderer
        renderer.mtkView(self, drawableSizeWillChange: self.drawableSize)
        
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func keyDown(with theEvent: NSEvent) {
        renderer.keyDown(with: theEvent)
    }
    
    override func keyUp(with theEvent: NSEvent) {
        renderer.keyUp(with: theEvent)
    }
}
