import Foundation

/// User settings, stored as JSON in ~/.config/displaysplit/config.json. Every key is optional
/// in the file; missing keys take the defaults below and unknown keys are ignored.
public struct Config: Equatable, Sendable {
    /// Put newly opened windows in the center column, full height.
    public var centerNewWindows = true
    public var split = ColumnSplit.default

    public init() {}

    public enum ParseError: Error, CustomStringConvertible {
        case syntax(String)
        case wrongType(key: String, expected: String)
        case invalidSplit(String)

        public var description: String {
            switch self {
            case let .syntax(detail): "Not valid JSON: \(detail)"
            case let .wrongType(key, expected): "\"\(key)\" must be \(expected)"
            case let .invalidSplit(value): "\"split\": \"\(value)\" is not three positive numbers like \"1:2:1\""
            }
        }
    }

    private struct File: Codable {
        var centerNewWindows: Bool?
        var split: String?
    }

    public init(json: Data) throws(ParseError) {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: json)
        } catch let DecodingError.typeMismatch(type, context) {
            throw .wrongType(key: context.codingPath.map(\.stringValue).joined(separator: "."),
                             expected: type == Bool.self ? "true or false" : "a string")
        } catch let DecodingError.dataCorrupted(context) {
            let underlying = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            throw .syntax(underlying ?? context.debugDescription)
        } catch {
            throw .syntax(String(describing: error))
        }
        if let value = file.centerNewWindows { centerNewWindows = value }
        if let value = file.split {
            guard let split = ColumnSplit(value) else { throw .invalidSplit(value) }
            self.split = split
        }
    }

    /// Pretty-printed with sorted keys and a trailing newline, so diffs stay minimal.
    public func json() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try! encoder.encode(File(centerNewWindows: centerNewWindows, split: split.description))
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
