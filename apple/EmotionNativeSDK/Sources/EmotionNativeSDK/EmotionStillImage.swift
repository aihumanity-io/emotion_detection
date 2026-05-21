import Foundation

public enum EmotionStillImageError: Error, Equatable {
    case unreadable
    case unsupportedFormat
    case invalidDimensions
    case invalidMaxValue
    case invalidPixelData
}

public enum EmotionStillImageLoader {
    public static func loadPPM(at url: URL) throws -> EmotionImage {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw EmotionStillImageError.unreadable
        }
        return try loadPPM(text: text)
    }

    public static func loadPPM(text: String) throws -> EmotionImage {
        var tokenizer = PPMTokenizer(text: text)
        guard tokenizer.next() == "P3" else {
            throw EmotionStillImageError.unsupportedFormat
        }
        guard let widthText = tokenizer.next(),
              let heightText = tokenizer.next(),
              let width = Int(widthText),
              let height = Int(heightText),
              width > 0,
              height > 0 else {
            throw EmotionStillImageError.invalidDimensions
        }
        guard let maxValueText = tokenizer.next(),
              let maxValue = Int(maxValueText),
              maxValue > 0,
              maxValue <= 255 else {
            throw EmotionStillImageError.invalidMaxValue
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 3)
        for _ in 0..<(width * height * 3) {
            guard let channelText = tokenizer.next(),
                  let channel = Int(channelText),
                  channel >= 0,
                  channel <= maxValue else {
                throw EmotionStillImageError.invalidPixelData
            }
            bytes.append(UInt8((channel * 255) / maxValue))
        }
        guard tokenizer.next() == nil else {
            throw EmotionStillImageError.invalidPixelData
        }
        return try EmotionImage(width: width, height: height, rgbData: Data(bytes))
    }
}

private struct PPMTokenizer {
    private var tokens: [String] = []
    private var index = 0

    init(text: String) {
        let stripped = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let hashIndex = line.firstIndex(of: "#") else {
                    return String(line)
                }
                return String(line[..<hashIndex])
            }
            .joined(separator: "\n")
        tokens = stripped.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
    }

    mutating func next() -> String? {
        guard index < tokens.count else {
            return nil
        }
        defer { index += 1 }
        return tokens[index]
    }
}
