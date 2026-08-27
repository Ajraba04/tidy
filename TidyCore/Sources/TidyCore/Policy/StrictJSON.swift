import Foundation

enum StrictJSONError: Error, Equatable {
    case malformed
    case oversized
}

struct StrictJSON {
    static let byteLimit = 1_048_576

    indirect enum Value: Equatable {
        case object([String: Value])
        case array([Value])
        case string(String)
        case number(String)
        case bool(Bool)
        case null

        func object() throws -> [String: Value] {
            guard case .object(let value) = self else { throw StrictJSONError.malformed }
            return value
        }

        func array() throws -> [Value] {
            guard case .array(let value) = self else { throw StrictJSONError.malformed }
            return value
        }

        func string() throws -> String {
            guard case .string(let value) = self else { throw StrictJSONError.malformed }
            return value
        }

        func strings() throws -> [String] { try array().map { try $0.string() } }

        func bool() throws -> Bool {
            guard case .bool(let value) = self else { throw StrictJSONError.malformed }
            return value
        }

        func integer() throws -> Int {
            guard case .number(let text) = self, !Self.isFractional(text),
                  let value = Int(text) else { throw StrictJSONError.malformed }
            return value
        }

        func signedInteger() throws -> Int64 {
            guard case .number(let text) = self, !Self.isFractional(text),
                  let value = Int64(text) else { throw StrictJSONError.malformed }
            return value
        }

        func unsignedInteger() throws -> UInt64 {
            guard case .number(let text) = self, !Self.isFractional(text),
                  let value = UInt64(text) else { throw StrictJSONError.malformed }
            return value
        }

        private static func isFractional(_ text: String) -> Bool {
            text.contains(".") || text.contains("e") || text.contains("E")
        }
    }

    static func parse(_ data: Data) throws -> Value {
        guard data.count <= byteLimit else { throw StrictJSONError.oversized }
        guard String(data: data, encoding: .utf8) != nil else { throw StrictJSONError.malformed }
        var parser = Parser(bytes: Array(data))
        return try parser.parse()
    }

    static func canonicalData(_ value: Value) throws -> Data {
        var encoder = CanonicalEncoder()
        try encoder.encode(value, depth: 0)
        return Data(encoder.bytes)
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func parse() throws -> Value {
            let result = try value(depth: 0)
            whitespace()
            guard index == bytes.count else { throw StrictJSONError.malformed }
            return result
        }

        mutating func whitespace() {
            while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }

        mutating func consume(_ byte: UInt8) -> Bool {
            whitespace()
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        mutating func value(depth: Int) throws -> Value {
            whitespace()
            guard index < bytes.count else { throw StrictJSONError.malformed }
            switch bytes[index] {
            case 123:
                guard depth < 16 else { throw StrictJSONError.malformed }
                index += 1
                var object: [String: Value] = [:]
                if consume(125) { return .object(object) }
                repeat {
                    let key = try string()
                    guard object[key] == nil, object.count < 1_000, consume(58) else {
                        throw StrictJSONError.malformed
                    }
                    object[key] = try value(depth: depth + 1)
                    if consume(125) { return .object(object) }
                    guard consume(44) else { throw StrictJSONError.malformed }
                } while true
            case 91:
                guard depth < 16 else { throw StrictJSONError.malformed }
                index += 1
                var array: [Value] = []
                if consume(93) { return .array(array) }
                repeat {
                    guard array.count < 1_000 else { throw StrictJSONError.malformed }
                    array.append(try value(depth: depth + 1))
                    if consume(93) { return .array(array) }
                    guard consume(44) else { throw StrictJSONError.malformed }
                } while true
            case 34: return .string(try string())
            case 116: try literal("true"); return .bool(true)
            case 102: try literal("false"); return .bool(false)
            case 110: try literal("null"); return .null
            default: return .number(try number())
            }
        }

        mutating func literal(_ text: String) throws {
            let expected = Array(text.utf8)
            guard bytes.count - index >= expected.count,
                  Array(bytes[index..<index + expected.count]) == expected else {
                throw StrictJSONError.malformed
            }
            index += expected.count
        }

        mutating func string() throws -> String {
            whitespace()
            let start = index
            guard consume(34) else { throw StrictJSONError.malformed }
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 34 {
                    let token = Data(bytes[start..<index])
                    guard let result = try? JSONDecoder().decode(String.self, from: token),
                          result.utf8.count <= 4_096 else { throw StrictJSONError.malformed }
                    return result
                }
                if byte == 92 {
                    guard index < bytes.count else { throw StrictJSONError.malformed }
                    index += 1
                } else if byte < 32 {
                    throw StrictJSONError.malformed
                }
            }
            throw StrictJSONError.malformed
        }

        mutating func number() throws -> String {
            let start = index
            if bytes[index] == 45 { index += 1 }
            guard index < bytes.count else { throw StrictJSONError.malformed }
            if bytes[index] == 48 { index += 1 }
            else {
                guard (49...57).contains(bytes[index]) else { throw StrictJSONError.malformed }
                digits()
            }
            var integral = true
            if index < bytes.count, bytes[index] == 46 {
                integral = false
                index += 1
                let fractionStart = index
                digits()
                guard index > fractionStart else { throw StrictJSONError.malformed }
            }
            if index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
                integral = false
                index += 1
                if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
                let exponentStart = index
                digits()
                guard index > exponentStart else { throw StrictJSONError.malformed }
            }
            let text = String(decoding: bytes[start..<index], as: UTF8.self)
            if integral {
                guard text.hasPrefix("-") ? Int64(text) != nil : UInt64(text) != nil else {
                    throw StrictJSONError.malformed
                }
            } else {
                guard let value = Double(text), value.isFinite else { throw StrictJSONError.malformed }
            }
            return text
        }

        mutating func digits() {
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        }
    }

    private struct CanonicalEncoder {
        var bytes: [UInt8] = []

        mutating func append(_ byte: UInt8) throws {
            guard bytes.count < StrictJSON.byteLimit else { throw StrictJSONError.oversized }
            bytes.append(byte)
        }

        mutating func append<S: Sequence>(_ sequence: S) throws where S.Element == UInt8 {
            for byte in sequence { try append(byte) }
        }

        mutating func encode(_ value: Value, depth: Int) throws {
            switch value {
            case .object(let object):
                guard depth < 16, object.count <= 1_000 else { throw StrictJSONError.malformed }
                try append(123)
                let keys = object.keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
                for (offset, key) in keys.enumerated() {
                    if offset > 0 { try append(44) }
                    try string(key)
                    try append(58)
                    guard let member = object[key] else { throw StrictJSONError.malformed }
                    try encode(member, depth: depth + 1)
                }
                try append(125)
            case .array(let array):
                guard depth < 16, array.count <= 1_000 else { throw StrictJSONError.malformed }
                try append(91)
                for (offset, member) in array.enumerated() {
                    if offset > 0 { try append(44) }
                    try encode(member, depth: depth + 1)
                }
                try append(93)
            case .string(let value): try string(value)
            case .number(let text):
                guard !text.contains("."), !text.contains("e"), !text.contains("E"),
                      canonicalInteger(text) != nil else {
                    throw StrictJSONError.malformed
                }
                try append(canonicalInteger(text)!.utf8)
            case .bool(let value): try append((value ? "true" : "false").utf8)
            case .null: try append("null".utf8)
            }
        }

        private func canonicalInteger(_ text: String) -> String? {
            if text == "-0" { return "0" }
            if let signed = Int64(text), String(signed) == text { return text }
            if let unsigned = UInt64(text), String(unsigned) == text { return text }
            return nil
        }

        mutating func string(_ value: String) throws {
            guard value.utf8.count <= 4_096 else { throw StrictJSONError.malformed }
            try append(34)
            for scalar in value.unicodeScalars {
                switch scalar.value {
                case 0x22: try append("\\\"".utf8)
                case 0x5c: try append("\\\\".utf8)
                case 0x08: try append("\\b".utf8)
                case 0x0c: try append("\\f".utf8)
                case 0x0a: try append("\\n".utf8)
                case 0x0d: try append("\\r".utf8)
                case 0x09: try append("\\t".utf8)
                case 0...0x1f:
                    try append(String(format: "\\u%04x", scalar.value).utf8)
                default:
                    try append(String(scalar).utf8)
                }
            }
            try append(34)
        }
    }
}
