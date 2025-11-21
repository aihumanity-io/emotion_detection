

import UIKit
import Vision

open class FaceView: UIView {
    var leftEye: [CGPoint] = []
    var rightEye: [CGPoint] = []
    var faceContour: [CGPoint] = []
    
    var boundingBox = CGRect.zero
    var eyeLeftBox = CGRect.zero
    var eyeRightBox = CGRect.zero
    
    func clear() {
        leftEye = []
        rightEye = []
        faceContour = []
        
        boundingBox = .zero
        eyeLeftBox = .zero
        eyeRightBox = .zero
        
        DispatchQueue.main.async {
            self.setNeedsDisplay()
        }
    }
    
    open override func draw(_ rect: CGRect) {
        // 1
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        
        // 2
        context.saveGState()
        
        // 3
        defer {
            context.restoreGState()
        }
        
        // 4
        context.addRect(boundingBox)
        context.addRect(eyeLeftBox)
        context.addRect(eyeRightBox)
        
        // 5
        UIColor.red.setStroke()
        
        // 6
        context.strokePath()
        
        // 1
        UIColor.white.setStroke()
        
        if !leftEye.isEmpty {
            // 2
            context.addLines(between: leftEye)
            
            // 3
            context.closePath()
            
            // 4
            context.strokePath()
        }
        
        if !rightEye.isEmpty {
            context.addLines(between: rightEye)
            context.closePath()
            context.strokePath()
        }
        
        if !faceContour.isEmpty {
            context.addLines(between: faceContour)
            context.strokePath()
        }
    }
}
