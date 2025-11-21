//
//  MathExtension.swift
//  Runner
//
//  Created by david Chiu on 5/24/24.
//

import Foundation
// should be refactored :-)
public extension Array where Element : Collection {
    func getColumn(_ column : Element.Index) -> [ Element.Iterator.Element ] {
        return self.map { $0[ column ] }
    }
}

public extension Array where Element == Float {
    func scale(_ factor: Float) -> Array {
        return self.map { $0 * factor}
    }
}

public extension Collection where Element: Comparable {
    func firstIndexOfMaxElement() -> Index? {
        zip(indices, self).max(by: { $0.1 < $1.1 })?.0
    }
    func firstIndexOfMinElement() -> Index? {
        zip(indices, self).min(by: { $0.1 < $1.1 })?.0
    }
}

public extension Array where Element: RangeReplaceableCollection, Element.Index == Index {
    mutating func insert(_ elements: Element, column: Index) {
        for index in indices {
            self[index].insert(elements[index], at: column)
        }
    }
    mutating func appendColumn(_ elements: Element) {
        for index in indices {
            self[index].insert(elements[index], at: self[index].endIndex)
        }
    }
    mutating func replace(_ elements: Element, from: Index, to: Index, subrange: Range<Int>) {
        for index in from...to {
            self[index].replaceSubrange(subrange, with: elements)
        }
    }
}

struct FixedFIFOArray<T> {
    var _maxSize: Int
    var _array: [T] = []

    init(maxSize: Int) {
        self._maxSize = maxSize
    }
    mutating func append(_ value: T) {
        if endIndex >= _maxSize {
            _array.removeFirst()
        }
        _array.append(value)
    }
    
    func prev() -> T? {
        if _array.count <= 1 {
            return nil
        }
        return _array[endIndex-1]
    }

}
extension FixedFIFOArray : RandomAccessCollection {
    var startIndex: Int {
        return _array.startIndex
    }

    var endIndex: Int {
        return _array.endIndex
    }

    subscript(i: Int) -> T {
            get {
                return _array[i]
            }
            set {
                _array[i] = newValue
            }
        }
}

func getMedian(_ array: [Float]) -> Float {
    if array.count <= 0 {return 0}
    if array.count <= 1 {return array[0]}
    let sorted = array.sorted()
    if sorted.count % 2 == 0 {
        return Float((sorted[(sorted.count / 2)] + sorted[(sorted.count / 2) - 1])) / 2
    } else {
        return Float(sorted[(sorted.count - 1) / 2])
    }
}
