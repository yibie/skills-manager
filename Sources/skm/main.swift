import Foundation
import SkillsKernel

// skm — Effective-Agent 检视器 CLI(M1:validate / check;M2:inspect)
//
//   skm validate <spec.yaml> [--schema <schema.json>]
//       对照 schema.json 校验 spec 结构 + 语义规则(id 唯一、引用存在等)。
//       schema 默认取 spec 同目录下的 schema.json。
//
//   skm check <spec.yaml> --project <path> [--home <path>]
//       按 spec 扫描文件系统,报告每条路径 present/missing,
//       以及 spec 声明目录邻域内未建模的可疑文件 [unmodeled]。只读。
//
//   skm inspect <spec.yaml> --project <path> [--home <path>] [--pretty]
//       输出 Effective-Agent JSON(资源实例、遮蔽关系、missing/unmodeled、
//       runtime 浅计数)。格式契约:docs/goals/effective-agent-schema.json。只读。

let usage = """
用法:
  skm validate <spec.yaml> [--schema <schema.json>]
  skm check <spec.yaml> --project <path> [--home <path>]
  skm inspect <spec.yaml> --project <path> [--home <path>] [--pretty]
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("skm: " + message + "\n").utf8))
    exit(1)
}

/// 无值的布尔开关(出现即为真)。
let booleanFlags: Set<String> = ["pretty"]

/// 解析 `--flag value` 形式的选项与布尔开关,返回 (位置参数, 选项表)。
func parseArguments(_ arguments: [String]) -> (positional: [String], options: [String: String]) {
    var positional: [String] = []
    var options: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        if argument.hasPrefix("--") {
            let name = String(argument.dropFirst(2))
            if booleanFlags.contains(name) {
                options[name] = "true"
                index += 1
                continue
            }
            guard index + 1 < arguments.count else {
                fail("选项 --\(name) 缺少值")
            }
            options[name] = arguments[index + 1]
            index += 2
        } else {
            positional.append(argument)
            index += 1
        }
    }
    return (positional, options)
}

/// 加载 spec 并完成 schema + 语义校验;失败打印问题并退出。
/// issuesToStderr:stdout 被 JSON 输出占用时(inspect),问题清单改走 stderr。
func validateSpec(
    specURL: URL,
    schemaURL: URL,
    quiet: Bool,
    issuesToStderr: Bool = false
) -> AdapterSpec {
    func emit(_ line: String) {
        if issuesToStderr {
            FileHandle.standardError.write(Data((line + "\n").utf8))
        } else {
            print(line)
        }
    }
    let raw: JSONValue
    do {
        raw = try SpecLoader.loadRaw(fileURL: specURL)
    } catch {
        fail(String(describing: error))
    }

    let validator: SchemaValidator
    do {
        validator = try SchemaValidator(schemaFileURL: schemaURL)
    } catch {
        fail("schema 加载失败(\(schemaURL.path)): \(error)")
    }

    let structuralIssues = validator.validate(raw)
    if !structuralIssues.isEmpty {
        for issue in structuralIssues {
            emit("[schema] \(issue)")
        }
        fail("spec 未通过 schema 校验,共 \(structuralIssues.count) 个问题")
    }

    let spec: AdapterSpec
    do {
        spec = try SpecLoader.loadTyped(fileURL: specURL)
    } catch {
        fail(String(describing: error))
    }

    let semanticIssues = SpecLoader.semanticIssues(in: spec)
    if !semanticIssues.isEmpty {
        for issue in semanticIssues {
            emit("[semantic] \(issue)")
        }
        fail("spec 未通过语义校验,共 \(semanticIssues.count) 个问题")
    }

    if !quiet {
        print("ok: \(specURL.lastPathComponent) 通过校验(\(spec.resources.count) 条 resource 规则,platform: \(spec.platform.id))")
    }
    return spec
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print(usage)
    exit(1)
}

let (positional, options) = parseArguments(Array(arguments.dropFirst()))

switch command {
case "validate":
    guard let specPath = positional.first else {
        fail("validate 需要 spec 文件路径\n\(usage)")
    }
    let specURL = URL(fileURLWithPath: specPath).standardizedFileURL
    let schemaURL = options["schema"].map { URL(fileURLWithPath: $0) }
        ?? specURL.deletingLastPathComponent().appendingPathComponent("schema.json")
    _ = validateSpec(specURL: specURL, schemaURL: schemaURL, quiet: false)

case "check":
    guard let specPath = positional.first else {
        fail("check 需要 spec 文件路径\n\(usage)")
    }
    guard let projectPath = options["project"] else {
        fail("check 需要 --project <path>")
    }
    let specURL = URL(fileURLWithPath: specPath).standardizedFileURL
    let schemaURL = options["schema"].map { URL(fileURLWithPath: $0) }
        ?? specURL.deletingLastPathComponent().appendingPathComponent("schema.json")
    let projectURL = URL(fileURLWithPath: projectPath).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDirectory),
          isDirectory.boolValue
    else {
        fail("项目目录不存在: \(projectURL.path)")
    }

    // check 之前先隐式 validate:坏 spec 的检查结果没有意义
    let spec = validateSpec(specURL: specURL, schemaURL: schemaURL, quiet: true)

    let home = options["home"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser
    let checker = SpecChecker(spec: spec, projectRoot: projectURL, home: home)
    let report = checker.run()
    print(report.renderText(homePath: home.path))
    exit(report.requiredMissing.isEmpty ? 0 : 1)

case "inspect":
    guard let specPath = positional.first else {
        fail("inspect 需要 spec 文件路径\n\(usage)")
    }
    guard let projectPath = options["project"] else {
        fail("inspect 需要 --project <path>")
    }
    let specURL = URL(fileURLWithPath: specPath).standardizedFileURL
    let schemaURL = options["schema"].map { URL(fileURLWithPath: $0) }
        ?? specURL.deletingLastPathComponent().appendingPathComponent("schema.json")
    let projectURL = URL(fileURLWithPath: projectPath).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDirectory),
          isDirectory.boolValue
    else {
        fail("项目目录不存在: \(projectURL.path)")
    }

    // 坏 spec 的检视结果没有意义;stdout 留给 JSON,校验问题走 stderr
    let spec = validateSpec(specURL: specURL, schemaURL: schemaURL, quiet: true, issuesToStderr: true)

    let home = options["home"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser
    let inspector = EffectiveAgentInspector(
        spec: spec,
        projectRoot: projectURL,
        home: home,
        specPath: specURL.path
    )
    let report = inspector.run()
    do {
        print(try report.renderJSON(pretty: options["pretty"] == "true"))
    } catch {
        fail("JSON 序列化失败: \(error)")
    }

default:
    print(usage)
    exit(1)
}
