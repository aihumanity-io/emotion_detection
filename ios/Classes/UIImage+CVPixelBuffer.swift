/*
  Copyright (c) 2017-2021 M.I. Hollemans

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to
  deal in the Software without restriction, including without limitation the
  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
  sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
  IN THE SOFTWARE.
*/

import UIKit
import VideoToolbox
import Accelerate

extension UIImage {
  /**
    Converts the image to an ARGB `CVPixelBuffer`.
  */
  public func pixelBuffer() -> CVPixelBuffer? {
    return pixelBuffer(width: Int(size.width), height: Int(size.height))
  }

  /**
    Resizes the image to `width` x `height` and converts it to an ARGB
    `CVPixelBuffer`.
  */
  public func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
    return pixelBuffer(width: width, height: height,
                       pixelFormatType: kCVPixelFormatType_32ARGB,
                       colorSpace: CGColorSpaceCreateDeviceRGB(),
                       alphaInfo: .noneSkipFirst)
  }

  /**
    Converts the image to a grayscale `CVPixelBuffer`.
  */
  public func pixelBufferGray() -> CVPixelBuffer? {
    return pixelBufferGray(width: Int(size.width), height: Int(size.height))
  }

  /**
    Resizes the image to `width` x `height` and converts it to a grayscale
    `CVPixelBuffer`.
  */
  public func pixelBufferGray(width: Int, height: Int) -> CVPixelBuffer? {
    return pixelBuffer(width: width, height: height,
                       pixelFormatType: kCVPixelFormatType_OneComponent8,
                       colorSpace: CGColorSpaceCreateDeviceGray(),
                       alphaInfo: .none)
  }

  /**
    Resizes the image to `width` x `height` and converts it to a `CVPixelBuffer`
    with the specified pixel format, color space, and alpha channel.
  */
  public func pixelBuffer(width: Int, height: Int,
                          pixelFormatType: OSType,
                          colorSpace: CGColorSpace,
                          alphaInfo: CGImageAlphaInfo) -> CVPixelBuffer? {
    var maybePixelBuffer: CVPixelBuffer?
    let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                 kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue]
    let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                     width,
                                     height,
                                     pixelFormatType,
                                     attrs as CFDictionary,
                                     &maybePixelBuffer)

    guard status == kCVReturnSuccess, let pixelBuffer = maybePixelBuffer else {
      return nil
    }

    let flags = CVPixelBufferLockFlags(rawValue: 0)
    guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(pixelBuffer, flags) else {
      return nil
    }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, flags) }

    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                  space: colorSpace,
                                  bitmapInfo: alphaInfo.rawValue)
    else {
      return nil
    }

    UIGraphicsPushContext(context)
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    self.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
    UIGraphicsPopContext()

    return pixelBuffer
  }
}

extension UIImage {
  /**
    Creates a new UIImage from a CVPixelBuffer.

    - Note: Not all CVPixelBuffer pixel formats support conversion into a
            CGImage-compatible pixel format.
  */
  public convenience init?(pixelBuffer: CVPixelBuffer) {
    if let cgImage = CGImage.create(pixelBuffer: pixelBuffer) {
      self.init(cgImage: cgImage)
    } else {
      return nil
    }
  }

  /*
  // Alternative implementation:
  public convenience init?(pixelBuffer: CVPixelBuffer) {
    // This converts the image to a CIImage first and then to a UIImage.
    // Does not appear to work on the simulator but is OK on the device.
    self.init(ciImage: CIImage(cvPixelBuffer: pixelBuffer))
  }
  */

  /**
    Creates a new UIImage from a CVPixelBuffer, using a Core Image context.
  */
  public convenience init?(pixelBuffer: CVPixelBuffer, context: CIContext) {
    if let cgImage = CGImage.create(pixelBuffer: pixelBuffer, context: context) {
      self.init(cgImage: cgImage)
    } else {
      return nil
    }
  }


    func pixelTensorData(width: Int = 224, height: Int = 224) -> Data {
        let size = CGSize(width:width, height:height)
        let dataSize = size.width * size.height * 4
        var pixelData = [Float32](repeating: 0, count: Int(dataSize))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: &pixelData,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 32,
                                bytesPerRow: 16 * Int(size.width),
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let cgImage = self.cgImage else { return Data() }
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))

        return Data(bytes: pixelData, count: pixelData.count)
    }
    func flipImageHorizontal(_ image: UIImage) -> UIImage {
        return image.withHorizontallyFlippedOrientation()
    }
    
        func rotate(radians: Float) -> UIImage? {
            var newSize = CGRect(origin: CGPoint.zero, size: self.size).applying(CGAffineTransform(rotationAngle: CGFloat(radians))).size
            // Trim off the extremely small float value to prevent core graphics from rounding it up
            newSize.width = floor(newSize.width)
            newSize.height = floor(newSize.height)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
            guard let context = UIGraphicsGetCurrentContext() else { return nil }
            
            // Move origin to middle
            context.translateBy(x: newSize.width/2, y: newSize.height/2)
            // Rotate around middle
            context.rotate(by: CGFloat(radians))
            // Draw the image at its center
            self.draw(in: CGRect(x: -self.size.width/2, y: -self.size.height/2, width: self.size.width, height: self.size.height))
        
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return newImage
        }
    
 }

func pixelTensorCGImage(cgImage: CGImage, width: Int = 224, height: Int = 224) -> CGImage? {
    let size = CGSize(width:width, height:height)
    let dataSize = size.width * size.height * 4
    var pixelData = [UInt8](repeating: 0, count: Int(dataSize))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: &pixelData,
                            width: Int(size.width),
                            height: Int(size.height),
                            bitsPerComponent: 8,
                            bytesPerRow: 4 * Int(size.width),
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
    context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))

    return context?.makeImage()
}

public var rgbaSourceFormat = vImage_CGImageFormat(
  bitsPerComponent: 8,
  bitsPerPixel: 32,
  colorSpace: Unmanaged.passRetained(CGColorSpaceCreateDeviceRGB()),
  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue),
  version: 0,
  decode: nil,
  renderingIntent: .defaultIntent
)

public var fffDestinationFormat = vImage_CGImageFormat(
  bitsPerComponent: 32,
  bitsPerPixel: 96,
  colorSpace: Unmanaged.passRetained(CGColorSpaceCreateDeviceRGB()),
  bitmapInfo: CGBitmapInfo(rawValue: (CGImageAlphaInfo.none.rawValue | CGBitmapInfo.floatComponents.rawValue)),
  version: 0,
  decode: nil,
  renderingIntent: .defaultIntent
)

let bgraToFFFConverter = vImageConverter_CreateWithCGImageFormat(
  &rgbaSourceFormat,
  &fffDestinationFormat,
  nil,
  vImage_Flags(kvImagePrintDiagnosticsToConsole),
  nil
)

let PIXEL_CONVERTER = bgraToFFFConverter!.takeRetainedValue()


func subtractValueFromImagePixels(image: UIImage, subtractValue: UInt8) -> UIImage? {
    guard let cgImage = image.cgImage else {
        return nil
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let width = cgImage.width
    let height = cgImage.height
    let bitsPerComponent = 8
    let bytesPerRow = 4 * width

    // Create a context to manipulate the image
    guard let context = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: bitsPerComponent,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }

    // Draw the original image into the context
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Get a pointer to the pixel data
    guard let pixelData = context.data else {
        return nil
    }

    let pixelBuffer = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)

    // Loop through each pixel and subtract the value
    for i in 0..<(width * height * 4) {
        pixelBuffer[i] = max(pixelBuffer[i] - subtractValue, 0)
    }

    // Create a new image from the modified context
    if let newCGImage = context.makeImage() {
        return UIImage(cgImage: newCGImage)
    }

    return nil
}

// Usage
/*if let originalImage = UIImage(named: "your_image_name") {
    if let subtractedImage = subtractValueFromImagePixels(image: originalImage, subtractValue: 50) {
        // Use the subtractedImage as needed
    }
}
*/

//To subtract pixel values of a `UIImage` from an image represented by a `CVPixelBuffer` in Swift, you can use the Core Video framework for working with pixel buffers and Core Graphics for the image subtraction. Here's an example of how you might achieve this:

//```swift
import CoreVideo

func subtractImage(_ image: UIImage, fromPixelBuffer pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    var newPixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &newPixelBuffer)

    guard let newPixelBuffer = newPixelBuffer else {
        return nil
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
    CVPixelBufferLockBaseAddress(newPixelBuffer, [])

    if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
       let newBaseAddress = CVPixelBufferGetBaseAddress(newPixelBuffer) {

        let data = baseAddress.assumingMemoryBound(to: UInt8.self)
        let newData = newBaseAddress.assumingMemoryBound(to: UInt8.self)

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let newBytesPerRow = CVPixelBufferGetBytesPerRow(newPixelBuffer)

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * bytesPerRow) + (x * 4)
                let newIndex = (y * newBytesPerRow) + (x * 4)

                // Get the pixel value from the original image
                let pixel = image.getPixelColor(x: x, y: y)
                let red = UInt8(pixel.red * 255)
                let green = UInt8(pixel.green * 255)
                let blue = UInt8(pixel.blue * 255)

                // Subtract the pixel values from the original pixel buffer
                newData[newIndex + 0] = min(data[index + 0] - blue, 255)
                newData[newIndex + 1] = min(data[index + 1] - green, 255)
                newData[newIndex + 2] = min(data[index + 2] - red, 255)
                newData[newIndex + 3] = data[index + 3]
            }
        }
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
    CVPixelBufferUnlockBaseAddress(newPixelBuffer, [])

    return newPixelBuffer
}

extension UIImage {
    func getPixelColor(x: Int, y: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        guard let cgImage = self.cgImage else {
            return (0, 0, 0, 0)
        }

        let pixelData = cgImage.dataProvider!.data
        let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)

        let pixelInfo: Int = ((cgImage.width * y) + x) * 4

        let red = CGFloat(data[pixelInfo]) / 255.0
        let green = CGFloat(data[pixelInfo + 1]) / 255.0
        let blue = CGFloat(data[pixelInfo + 2]) / 255.0
        let alpha = CGFloat(data[pixelInfo + 3]) / 255.0

        return (red, green, blue, alpha)
    }
}

// Usage
/*if let originalImage = UIImage(named: "your_image_name") {
    let pixelBuffer: CVPixelBuffer = ... // Get your pixel buffer

    if let subtractedPixelBuffer = subtractImage(originalImage, fromPixelBuffer: pixelBuffer) {
        // Use the subtractedPixelBuffer as needed
    }
}*/
//```

//Please note that this example assumes that the input image and the pixel buffer have the same dimensions. Also, remember to replace `"your_image_name"` with the actual name of your image file. The `getPixelColor` extension method extracts the color values at a given pixel location from a `UIImage`. The `subtractImage` function performs the subtraction operation. This code provides a basic implementation and might need adjustments based on your specific requirements and use case.

//To convert a `UIImage` to a `CVPixelBuffer` in Swift, you can use the Core Video framework. Here's an example of how you might achieve this:

//```swift
import CoreVideo

func createPixelBuffer(from image: UIImage) -> CVPixelBuffer? {
    let width = Int(image.size.width)
    let height = Int(image.size.height)

    var pixelBuffer: CVPixelBuffer?
    let options: [String: Any] = [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ]
    
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, options as CFDictionary, &pixelBuffer)

    if let pixelBuffer = pixelBuffer {
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        if let context = context {
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            context.clear(rect)
            context.draw(image.cgImage!, in: rect)
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        return pixelBuffer
    }

    return nil
}

// Usage
/*if let image = UIImage(named: "your_image_name") {
    if let pixelBuffer = createPixelBuffer(from: image) {
        // Use the pixelBuffer as needed
    }
}*/

//```

//Replace `"your_image_name"` with the actual name of your image file. The `createPixelBuffer` function takes a `UIImage` as input and returns a corresponding `CVPixelBuffer`. Make sure that the pixel buffer format (in this case, `kCVPixelFormatType_32ARGB`) and other settings match your specific requirements.



func loadImageIntoPixelBuffer(image: UIImage) -> CVPixelBuffer? {
    let width = Int(image.size.width)
    let height = Int(image.size.height)

    var pixelBuffer: CVPixelBuffer?
    let options: [String: Any] = [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ]

    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, options as CFDictionary, &pixelBuffer)

    if let pixelBuffer = pixelBuffer {
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        if let context = context {
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            context.clear(rect)
            context.draw(image.cgImage!, in: rect)
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        return pixelBuffer
    }

    return nil
}

// Usage
/*if let image = UIImage(named: "your_image_name") {
    if let pixelBuffer = loadImageIntoPixelBuffer(image: image) {
        // Use the pixelBuffer as needed
    }
}*/
