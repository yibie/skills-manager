import Foundation

/// schema 校验发现的问题。
public struct SchemaIssue: Equatable, Sendable, CustomStringConvertible {
    /// 实例中的位置(JSON Pointer 风格,如 /resources/3/type)。
    public let path: String
    public let message: String

    public var description: String { "\(path.isEmpty ? "/" : path): \(message)" }
}

/// JSON Schema(draft 2020-12)子集校验器。
///
/// 只支持 platform-specs/schema.json 用到的关键字:
/// type / properties / required / additionalProperties(布尔)/ items /
/// enum / minItems / pattern / $ref(仅 #/... 内部引用)。
/// 见 SCHEMA.md"校验器支持的关键字"一节。
public struct SchemaValidator: Sendable {
    private let rootSchema: JSONValue

    public init(schema: JSONValue) {
        self.rootSchema = schema
    }

    /// 从 schema.json 文件加载。
    public init(schemaFileURL: URL) throws {
        let data = try Data(contentsOf: schemaFileURL)
        self.rootSchema = try JSONValue.fromJSON(data)
    }

    /// 校验实例,返回全部问题(空数组即通过)。
    public func validate(_ instance: JSONValue) -> [SchemaIssue] {
        var issues: [SchemaIssue] = []
        validate(instance, against: rootSchema, at: "", issues: &issues)
        return issues
    }

    // MARK: - 内部实现

    private func resolveRef(_ ref: String) -> JSONValue? {
        guard ref.hasPrefix("#") else { return nil }
        let pointer = String(ref.dropFirst())
        return rootSchema.value(atPointer: pointer)
    }

    private func validate(
        _ instance: JSONValue,
        against schema: JSONValue,
        at path: String,
        issues: inout [SchemaIssue]
    ) {
        guard let schemaObject = schema.objectValue else { return }

        // $ref:解析后继续用目标 schema 校验(schema.json 只用内部引用)
        if let ref = schemaObject["$ref"]?.stringValue {
            if let resolved = resolveRef(ref) {
                validate(instance, against: resolved, at: path, issues: &issues)
            } else {
                issues.append(SchemaIssue(path: path, message: "schema 内部错误:无法解析 $ref \(ref)"))
            }
            return
        }

        // type
        if let expected = schemaObject["type"]?.stringValue {
            if !matchesType(instance, expected: expected) {
                issues.append(SchemaIssue(
                    path: path,
                    message: "类型应为 \(expected),实际是 \(instance.typeName)"
                ))
                return // 类型都不对,后续关键字没有意义
            }
        }

        // enum
        if let allowed = schemaObject["enum"]?.arrayValue {
            if !allowed.contains(instance) {
                let allowedText = allowed.map { describe($0) }.joined(separator: ", ")
                issues.append(SchemaIssue(
                    path: path,
                    message: "值 \(describe(instance)) 不在枚举 [\(allowedText)] 内"
                ))
            }
        }

        // pattern
        if let pattern = schemaObject["pattern"]?.stringValue,
           let string = instance.stringValue {
            if !matchesPattern(string, pattern: pattern) {
                issues.append(SchemaIssue(path: path, message: "字符串 \"\(string)\" 不匹配模式 \(pattern)"))
            }
        }

        // object 相关
        if let objectValue = instance.objectValue {
            if let required = schemaObject["required"]?.arrayValue {
                for key in required.compactMap(\.stringValue) where objectValue[key] == nil {
                    issues.append(SchemaIssue(path: path, message: "缺少必填字段 \(key)"))
                }
            }
            let properties = schemaObject["properties"]?.objectValue ?? [:]
            for (key, value) in objectValue.sorted(by: { $0.key < $1.key }) {
                if let propertySchema = properties[key] {
                    validate(value, against: propertySchema, at: "\(path)/\(key)", issues: &issues)
                } else if case .bool(false) = schemaObject["additionalProperties"] ?? .bool(true) {
                    issues.append(SchemaIssue(path: "\(path)/\(key)", message: "未知字段 \(key)"))
                }
            }
        }

        // array 相关
        if let arrayValue = instance.arrayValue {
            if case .int(let minItems)? = schemaObject["minItems"], arrayValue.count < minItems {
                issues.append(SchemaIssue(path: path, message: "元素数量 \(arrayValue.count) 少于最小值 \(minItems)"))
            }
            if let itemSchema = schemaObject["items"] {
                for (index, item) in arrayValue.enumerated() {
                    validate(item, against: itemSchema, at: "\(path)/\(index)", issues: &issues)
                }
            }
        }
    }

    private func matchesType(_ instance: JSONValue, expected: String) -> Bool {
        switch expected {
        case "object": if case .object = instance { return true }
        case "array": if case .array = instance { return true }
        case "string": if case .string = instance { return true }
        case "boolean": if case .bool = instance { return true }
        case "integer": if case .int = instance { return true }
        case "number":
            if case .int = instance { return true }
            if case .double = instance { return true }
        case "null": if case .null = instance { return true }
        default: return false
        }
        return false
    }

    private func matchesPattern(_ string: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, range: range) != nil
    }

    private func describe(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let b): return String(b)
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .string(let s): return "\"\(s)\""
        case .array: return "<array>"
        case .object: return "<object>"
        }
    }
}
