//
//  MLBase.swift
//  Runner
//
//  Created by david Chiu on 5/21/24.
//
//  Copyright © 2024 Creata AI. All rights reserved.
// Implementation of Face Expression Prediction  model
//

import Foundation
import CoreML


enum MLError: LocalizedError {
  case Error(_ message: String)

  var errorDescription: String? {
      switch self {
      case .Error(let message):
          return message
      }
  }
}

extension Sequence where Element: Hashable {
    var histogram: [Element: Int] {
        return self.reduce(into: [:]) { counts, elem in counts[elem, default: 0] += 1 }
    }
}

class MLBase {
    var modelConfig: MLModelConfiguration!

    init()  throws {
        modelConfig = MLModelConfiguration()
    }

    static func toArray(multiArray: MLMultiArray) -> [Float]? {
        if #available(iOS 13.0, *) {
            if let b = try? UnsafeBufferPointer<Float>(multiArray) {
                let c = Array(b)
                
                return c
            }
        } else {
            // Fallback on earlier versions
        }
        return nil
    }
    
}
