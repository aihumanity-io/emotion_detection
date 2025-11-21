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

import CoreGraphics
import CoreImage
import VideoToolbox
import UIKit
import Accelerate

extension CGImage {
  /**
    Converts the image to an ARGB `CVPixelBuffer`.
  */
  public func pixelBuffer() -> CVPixelBuffer? {
    return pixelBuffer(width: width, height: height, orientation: .up)
  }

  /**
    Resizes the image to `width` x `height` and converts it to an ARGB
    `CVPixelBuffer`.
  */
  public func pixelBuffer(width: Int, height: Int,
                          orientation: CGImagePropertyOrientation) -> CVPixelBuffer? {
    return pixelBuffer(width: width, height: height,
                       pixelFormatType: kCVPixelFormatType_32ARGB,
                       colorSpace: CGColorSpaceCreateDeviceRGB(),
                       alphaInfo: .noneSkipFirst,
                       orientation: orientation)
  }

  /**
    Converts the image to a grayscale `CVPixelBuffer`.
  */
  public func pixelBufferGray() -> CVPixelBuffer? {
    return pixelBufferGray(width: width, height: height, orientation: .up)
  }

  /**
    Resizes the image to `width` x `height` and converts it to a grayscale
    `CVPixelBuffer`.
  */
  public func pixelBufferGray(width: Int, height: Int,
                              orientation: CGImagePropertyOrientation) -> CVPixelBuffer? {
    return pixelBuffer(width: width, height: height,
                       pixelFormatType: kCVPixelFormatType_OneComponent8,
                       colorSpace: CGColorSpaceCreateDeviceGray(),
                       alphaInfo: .none,
                       orientation: orientation)
  }

  /**
    Resizes the image to `width` x `height` and converts it to a `CVPixelBuffer`
    with the specified pixel format, color space, and alpha channel.
  */
  public func pixelBuffer(width: Int, height: Int,
                          pixelFormatType: OSType,
                          colorSpace: CGColorSpace,
                          alphaInfo: CGImageAlphaInfo,
                          orientation: CGImagePropertyOrientation) -> CVPixelBuffer? {

    // TODO: If the orientation is not .up, then rotate the CGImage.
    // See also: https://stackoverflow.com/a/40438893/
    assert(orientation == .up)

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

    context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixelBuffer
  }
}

extension CGImage {
  /**
    Creates a new CGImage from a CVPixelBuffer.

    - Note: Not all CVPixelBuffer pixel formats support conversion into a
            CGImage-compatible pixel format.
  */
  public static func create(pixelBuffer: CVPixelBuffer) -> CGImage? {
    var cgImage: CGImage?
    VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
    return cgImage
  }

  /*
  // Alternative implementation:
  public static func create(pixelBuffer: CVPixelBuffer) -> CGImage? {
    // This method creates a bitmap CGContext using the pixel buffer's memory.
    // It currently only handles kCVPixelFormatType_32ARGB images. To support
    // other pixel formats too, you'll have to change the bitmapInfo and maybe
    // the color space for the CGContext.

    guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) else {
      return nil
    }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    if let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                               width: CVPixelBufferGetWidth(pixelBuffer),
                               height: CVPixelBufferGetHeight(pixelBuffer),
                               bitsPerComponent: 8,
                               bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue),
       let cgImage = context.makeImage() {
      return cgImage
    } else {
      return nil
    }
  }
  */

  /**
   Creates a new CGImage from a CVPixelBuffer, using Core Image.
  */
  public static func create(pixelBuffer: CVPixelBuffer, context: CIContext) -> CGImage? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let rect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelBuffer),
                                  height: CVPixelBufferGetHeight(pixelBuffer))
    return context.createCGImage(ciImage, from: rect)
  }
}


func subtractCGImages(_ image1: CGImage, _ image2: CGImage) -> CGImage? {
    let width = image1.width
    let height = image1.height

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: width * 4,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

    if let context = context {
        context.draw(image1, in: CGRect(x: 0, y: 0, width: width, height: height))

        if let data = context.data {
            let dataPointer = data.assumingMemoryBound(to: UInt8.self)

            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = (y * width + x) * 4

                    let pixel1 = image1.pixelData(atX: x, y: y) //dataPointer[pixelIndex..<pixelIndex + 4]
                    let pixel2 = image2.pixelData(atX: x, y: y)

                    var temp0 = Int(pixel1[1]) - Int(pixel2[0])
                    temp0 = max(0, temp0)
                    var temp1 = Int(pixel1[2]) - Int(pixel2[1])
                    temp1 = max(0, temp1)
                    var temp2 = Int(pixel1[3]) - Int(pixel2[2])
                    temp2 = max(0, temp2)

                    let subtractedPixel: [UInt8] = [UInt8(temp0),
                                                    UInt8(temp1),
                                                    UInt8(temp2),
                        pixel1[0]  // Alpha channel remains the same
                    ]
                   /* let subtractedPixel: [UInt8] = [
                        max(0, pixel1[0] - pixel2[0]),
                        max(0, pixel1[1] - pixel2[1]),
                        max(0, pixel1[2] - pixel2[2]),
                        pixel1[3]  // Alpha channel remains the same
                    ]*/

                    for i in 0..<4 {
                        dataPointer[pixelIndex + i] = subtractedPixel[i]
                    }
                }
            }
        }

        return context.makeImage()
    }

    return nil
}

extension CGImage {
    func pixelData(atX x: Int, y: Int) -> [UInt8] {
        let width = self.width
        let height = self.height

        let dataProvider = self.dataProvider
        let data = dataProvider?.data
        let dataPointer = CFDataGetBytePtr(data)

        let pixelIndex = (y * width + x) * 4

        let red = dataPointer?[pixelIndex] ?? 0
        let green = dataPointer?[pixelIndex + 1] ?? 0
        let blue = dataPointer?[pixelIndex + 2] ?? 0
        let alpha = dataPointer?[pixelIndex + 3] ?? 0

        return [red, green, blue, alpha]
    }
}

// Usage
/*if let image1 = UIImage(named: "image1"),
   let image2 = UIImage(named: "image2"),
   let cgImage1 = image1.cgImage,
   let cgImage2 = image2.cgImage {

    if let subtractedCGImage = subtractCGImages(cgImage1, cgImage2) {
        let subtractedImage = UIImage(cgImage: subtractedCGImage)
        // Use the subtractedImage as needed
    }
}
 */

extension CGImage {

    @available(iOS 13.0, *)
    func toGrayscale() -> CGImage {
        
        guard let format = vImage_CGImageFormat(cgImage: self),
              // The source image bufffer
              var sourceBuffer = try? vImage_Buffer(
                cgImage: self,
                format: format
              ),
              // The 1-channel, 8-bit vImage buffer used as the operation destination.
              var destinationBuffer = try? vImage_Buffer(
                width: Int(sourceBuffer.width),
                height: Int(sourceBuffer.height),
                bitsPerPixel: 8
              ) else {
            return self
        }
        
        // Declare the three coefficients that model the eye's sensitivity
        // to color.
        let redCoefficient: Float = 0.2126
        let greenCoefficient: Float = 0.7152
        let blueCoefficient: Float = 0.0722
        
        // Create a 1D matrix containing the three luma coefficients that
        // specify the color-to-grayscale conversion.
        let divisor: Int32 = 0x1000
        let fDivisor = Float(divisor)
        
        var coefficientsMatrix = [
            Int16(redCoefficient * fDivisor),
            Int16(greenCoefficient * fDivisor),
            Int16(blueCoefficient * fDivisor)
        ]
        
        // Use the matrix of coefficients to compute the scalar luminance by
        // returning the dot product of each RGB pixel and the coefficients
        // matrix.
        let preBias: [Int16] = [0, 0, 0, 0]
        let postBias: Int32 = 0
        
        vImageMatrixMultiply_ARGB8888ToPlanar8(
            &sourceBuffer,
            &destinationBuffer,
            &coefficientsMatrix,
            divisor,
            preBias,
            postBias,
            vImage_Flags(kvImageNoFlags)
        )
        
        // Create a 1-channel, 8-bit grayscale format that's used to
        // generate a displayable image.
        guard let monoFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            colorSpace: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            renderingIntent: .defaultIntent
        ) else {
            return self
        }
        
        // Create a Core Graphics image from the grayscale destination buffer.
        guard let result = try? destinationBuffer.createCGImage(format: monoFormat) else {
            return self
        }
        
        return result
    }
}
