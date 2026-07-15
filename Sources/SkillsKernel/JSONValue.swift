import Foundation
import Yams

/// 通用 JSON 值。YAML spec 与 schema.json 都先归一化成这个中间表示,
/// 再交给 schema 校验器,避免对具体解析库的耦合。
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// 类型名(用于校验错误信息与 schema 的 type 关键字比对)。
    public var typeName: String {
        switch self {
        case .null: return "null"
        case .bool: return "boolean"
        case .int: return "integer"
        case .double: return "number"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let dict) = self { return dict }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }
}

public enum JSONValueError: Error, CustomStringConvertible {
    case unsupportedValue(String)
    case invalidDocument(String)

    public var description: String {
        switch self {
        case .unsupportedValue(let detail): return "无法归一化的值: \(detail)"
        case .invalidDocument(let detail): return "文档解析失败: \(detail)"
        }
    }
}

extension JSONValue {
    /// 从 Foundation 的 Any(JSONSerialization / Yams.load 的产物)归一化。
    public static func from(any value: Any?) throws -> JSONValue {
        switch value {
        case nil, is NSNull:
            return .null
        case let number as NSNumber:
            // 区分 Bool 与数值(NSNumber 会把 Bool 也包进来)
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            if let int = value as? Int, number.doubleValue == Double(int) {
                return .int(int)
            }
            return .double(number.doubleValue)
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let string as String:
            return .string(string)
        case let date as Date:
            // YAML 会把未加引号的 2026-07-14 解析成时间戳,归一化回日期字符串
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return .string(formatter.string(from: date))
        case let array as [Any?]:
            return .array(try array.map { try JSONValue.from(any: $0) })
        case let dict as [AnyHashable: Any?]:
            var object: [String: JSONValue] = [:]
            for (key, item) in dict {
                guard let keyString = key.base as? String else {
                    throw JSONValueError.unsupportedValue("非字符串键: \(key)")
                }
                object[keyString] = try JSONValue.from(any: item)
            }
            return .object(object)
        default:
            throw JSONValueError.unsupportedValue(String(describing: value))
        }
    }

    /// 解析 YAML 文本。
    public static func fromYAML(_ text: String) throws -> JSONValue {
        let loaded = try Yams.load(yaml: text)
        return try JSONValue.from(any: loaded)
    }

    /// 解析 JSON 数据。
    public static func fromJSON(_ data: Data) throws -> JSONValue {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONValue.from(any: object)
    }

    /// RFC 6901 JSON Pointer 取值(如 "/mcpServers")。空指针返回自身。
    public func value(atPointer pointer: String) -> JSONValue? {
        guard !pointer.isEmpty else { return self }
        guard pointer.hasPrefix("/") else { return nil }
        var current = self
        let tokens = pointer.dropFirst().components(separatedBy: "/").map {
            $0.replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
        }
        for token in tokens {
            switch current {
            case .object(let dict):
                guard let next = dict[token] else { return nil }
                current = next
            case .array(let items):
                guard let index = Int(token), items.indices.contains(index) else { return nil }
                current = items[index]
            default:
                return nil
            }
        }
        return current
    }
}
