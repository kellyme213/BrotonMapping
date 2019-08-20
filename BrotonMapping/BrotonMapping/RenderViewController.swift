//
//  RenderViewController.swift
//  BrotonMapping
//
//  Created by Michael Kelly on 7/9/19.
//  Copyright © 2019 Michael Kelly. All rights reserved.
//

import Foundation
import Cocoa
import MetalKit

class RenderViewController: NSViewController
{
    var renderView: RenderView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.setFrameSize(CGSize(width: 480, height: 270))
                
        let defaultDevice = MTLCreateSystemDefaultDevice()!
                
        renderView = RenderView(frame: self.view.frame, device: defaultDevice)
        
        self.view = renderView
    }
}
