import Foundation

struct AgentDefinition: Sendable {
    let id: String           // e.g. "cursor", "gemini-cli"
    let displayName: String  // e.g. "Cursor", "Gemini CLI"
    let icon: String         // SF Symbol name
    /// Absolute path to the agent's global skills directory.
    let globalSkillsDir: URL
    /// Path that must exist in HOME for us to consider this agent installed.
    let detectPath: String   // relative to homeDir, e.g. ".cursor"
}

enum AgentRegistry {

    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let xdgConfig: URL = {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
            return URL(fileURLWithPath: xdg)
        }
        return home.appendingPathComponent(".config")
    }()

    /// The canonical "universal" directory all agents share.
    static var canonicalGlobalSkillsDir: URL {
        xdgConfig.appendingPathComponent("agents/skills")
    }

    static let all: [AgentDefinition] = [
        // Universal agents — use canonical dir as their global skills dir too
        .init(id: "amp",            displayName: "Amp",             icon: "bolt",             globalSkillsDir: xdgConfig.appendingPathComponent("agents/skills"),          detectPath: ".config/amp"),
        .init(id: "cline",          displayName: "Cline",           icon: "terminal",         globalSkillsDir: home.appendingPathComponent(".agents/skills"),               detectPath: ".cline"),
        .init(id: "codex",          displayName: "Codex",           icon: "chevron.left.forwardslash.chevron.right", globalSkillsDir: home.appendingPathComponent(".codex/skills"),  detectPath: ".codex"),
        .init(id: "cursor",         displayName: "Cursor",          icon: "cursorarrow",      globalSkillsDir: home.appendingPathComponent(".cursor/skills"),               detectPath: ".cursor"),
        .init(id: "deepagents",     displayName: "Deep Agents",     icon: "brain",            globalSkillsDir: home.appendingPathComponent(".deepagents/agent/skills"),     detectPath: ".deepagents"),
        .init(id: "firebender",     displayName: "Firebender",      icon: "flame",            globalSkillsDir: home.appendingPathComponent(".firebender/skills"),           detectPath: ".firebender"),
        .init(id: "gemini-cli",     displayName: "Gemini CLI",      icon: "g.circle",         globalSkillsDir: home.appendingPathComponent(".gemini/skills"),               detectPath: ".gemini"),
        .init(id: "github-copilot", displayName: "GitHub Copilot",  icon: "network",          globalSkillsDir: home.appendingPathComponent(".copilot/skills"),              detectPath: ".copilot"),
        .init(id: "kimi-cli",       displayName: "Kimi Code CLI",   icon: "k.circle",         globalSkillsDir: xdgConfig.appendingPathComponent("agents/skills"),          detectPath: ".kimi"),
        .init(id: "replit",         displayName: "Replit",          icon: "r.circle",         globalSkillsDir: xdgConfig.appendingPathComponent("agents/skills"),          detectPath: ".replit"),
        .init(id: "warp",           displayName: "Warp",            icon: "terminal.fill",    globalSkillsDir: home.appendingPathComponent(".agents/skills"),               detectPath: ".warp"),
        // Agent-specific dirs
        .init(id: "antigravity",    displayName: "Antigravity",     icon: "arrow.up.circle",  globalSkillsDir: home.appendingPathComponent(".gemini/antigravity/skills"),   detectPath: ".gemini/antigravity"),
        .init(id: "augment",        displayName: "Augment",         icon: "plus.circle",      globalSkillsDir: home.appendingPathComponent(".augment/skills"),              detectPath: ".augment"),
        .init(id: "bob",            displayName: "IBM Bob",         icon: "person.circle",    globalSkillsDir: home.appendingPathComponent(".bob/skills"),                  detectPath: ".bob"),
        .init(id: "codebuddy",      displayName: "CodeBuddy",       icon: "person.2",         globalSkillsDir: home.appendingPathComponent(".codebuddy/skills"),            detectPath: ".codebuddy"),
        .init(id: "command-code",   displayName: "Command Code",    icon: "command",          globalSkillsDir: home.appendingPathComponent(".commandcode/skills"),          detectPath: ".commandcode"),
        .init(id: "continue",       displayName: "Continue",        icon: "arrow.right.circle", globalSkillsDir: home.appendingPathComponent(".continue/skills"),          detectPath: ".continue"),
        .init(id: "cortex",         displayName: "Cortex Code",     icon: "cpu",              globalSkillsDir: home.appendingPathComponent(".snowflake/cortex/skills"),     detectPath: ".snowflake/cortex"),
        .init(id: "crush",          displayName: "Crush",           icon: "hammer",           globalSkillsDir: home.appendingPathComponent(".config/crush/skills"),         detectPath: ".config/crush"),
        .init(id: "droid",          displayName: "Droid",           icon: "desktopcomputer",  globalSkillsDir: home.appendingPathComponent(".factory/skills"),              detectPath: ".factory"),
        .init(id: "goose",          displayName: "Goose",           icon: "bird",             globalSkillsDir: xdgConfig.appendingPathComponent("goose/skills"),            detectPath: ".config/goose"),
        .init(id: "iflow-cli",      displayName: "iFlow CLI",       icon: "arrow.triangle.branch", globalSkillsDir: home.appendingPathComponent(".iflow/skills"),          detectPath: ".iflow"),
        .init(id: "junie",          displayName: "Junie",           icon: "j.circle",         globalSkillsDir: home.appendingPathComponent(".junie/skills"),                detectPath: ".junie"),
        .init(id: "kilo",           displayName: "Kilo Code",       icon: "k.circle.fill",    globalSkillsDir: home.appendingPathComponent(".kilocode/skills"),             detectPath: ".kilocode"),
        .init(id: "kiro-cli",       displayName: "Kiro CLI",        icon: "wand.and.stars",   globalSkillsDir: home.appendingPathComponent(".kiro/skills"),                 detectPath: ".kiro"),
        .init(id: "kode",           displayName: "Kode",            icon: "chevron.left.forwardslash.chevron.right", globalSkillsDir: home.appendingPathComponent(".kode/skills"), detectPath: ".kode"),
        .init(id: "mcpjam",         displayName: "MCPJam",          icon: "puzzlepiece.fill",      globalSkillsDir: home.appendingPathComponent(".mcpjam/skills"),               detectPath: ".mcpjam"),
        .init(id: "mistral-vibe",   displayName: "Mistral Vibe",    icon: "waveform",         globalSkillsDir: home.appendingPathComponent(".vibe/skills"),                 detectPath: ".vibe"),
        .init(id: "mux",            displayName: "Mux",             icon: "m.circle",         globalSkillsDir: home.appendingPathComponent(".mux/skills"),                  detectPath: ".mux"),
        .init(id: "neovate",        displayName: "Neovate",         icon: "n.circle",         globalSkillsDir: home.appendingPathComponent(".neovate/skills"),              detectPath: ".neovate"),
        .init(id: "opencode",       displayName: "OpenCode",        icon: "chevron.left.forwardslash.chevron.right", globalSkillsDir: xdgConfig.appendingPathComponent("opencode/skills"), detectPath: ".config/opencode"),
        .init(id: "openhands",      displayName: "OpenHands",       icon: "hand.raised.fill",       globalSkillsDir: home.appendingPathComponent(".openhands/skills"),            detectPath: ".openhands"),
        .init(id: "pi",             displayName: "Pi",              icon: "p.circle",         globalSkillsDir: home.appendingPathComponent(".pi/agent/skills"),             detectPath: ".pi/agent"),
        .init(id: "pochi",          displayName: "Pochi",           icon: "pawprint",         globalSkillsDir: home.appendingPathComponent(".pochi/skills"),                detectPath: ".pochi"),
        .init(id: "qoder",          displayName: "Qoder",           icon: "q.circle",         globalSkillsDir: home.appendingPathComponent(".qoder/skills"),                detectPath: ".qoder"),
        .init(id: "qwen-code",      displayName: "Qwen Code",       icon: "q.circle.fill",    globalSkillsDir: home.appendingPathComponent(".qwen/skills"),                 detectPath: ".qwen"),
        .init(id: "roo",            displayName: "Roo Code",        icon: "r.square",         globalSkillsDir: home.appendingPathComponent(".roo/skills"),                  detectPath: ".roo"),
        .init(id: "trae",           displayName: "Trae",            icon: "t.circle",         globalSkillsDir: home.appendingPathComponent(".trae/skills"),                 detectPath: ".trae"),
        .init(id: "trae-cn",        displayName: "Trae CN",         icon: "t.circle.fill",    globalSkillsDir: home.appendingPathComponent(".trae-cn/skills"),              detectPath: ".trae-cn"),
        .init(id: "windsurf",       displayName: "Windsurf",        icon: "wind",             globalSkillsDir: home.appendingPathComponent(".codeium/windsurf/skills"),     detectPath: ".codeium/windsurf"),
        .init(id: "zencoder",       displayName: "Zencoder",        icon: "z.circle",         globalSkillsDir: home.appendingPathComponent(".zencoder/skills"),             detectPath: ".zencoder"),
        .init(id: "adal",           displayName: "AdaL",            icon: "a.circle",         globalSkillsDir: home.appendingPathComponent(".adal/skills"),                 detectPath: ".adal"),
    ]

    /// Returns agents whose config directory exists on disk right now.
    static func installedAgents() -> [AgentDefinition] {
        all.filter { FileManager.default.fileExists(atPath: home.appendingPathComponent($0.detectPath).path) }
    }

    static func agent(id: String) -> AgentDefinition? {
        all.first { $0.id == id }
    }
}
