import Foundation

/// User-configurable mapping from the two visual slots to concrete local
/// agents. Internally the app still uses the historical `.claude` (left) and
/// `.codex` (right) slots so the alert/layout code stays small; this store
/// decides what each slot actually means.
enum AgentKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case openClaw
    case codex
    case claudeCode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openClaw: return "OpenClaw"
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        }
    }

    var shortName: String {
        switch self {
        case .openClaw: return "OC"
        case .codex: return "CX"
        case .claudeCode: return "CC"
        }
    }

    var rootLabel: String {
        switch self {
        case .openClaw: return "OpenClaw root"
        case .codex: return "Codex root"
        case .claudeCode: return "Claude Code root"
        }
    }

    var defaultRoot: String {
        switch self {
        case .openClaw: return "~/.openclaw-autoclaw"
        case .codex: return "~/.codex"
        case .claudeCode: return "~/.claude"
        }
    }

    var logoResource: String? {
        switch self {
        case .openClaw: return "openclaw_logo"
        case .codex: return "openai_logo"
        case .claudeCode: return "claude_logo"
        }
    }
}

@MainActor
final class AgentConfigurationStore: ObservableObject {
    static let shared = AgentConfigurationStore()

    private static let leftAgentKey = "MacIsland.leftAgentKind"
    private static let rightAgentKey = "MacIsland.rightAgentKind"
    private static let openClawRootKey = "MacIsland.openClawRoot"
    private static let codexRootKey = "MacIsland.codexRoot"
    private static let claudeCodeRootKey = "MacIsland.claudeCodeRoot"

    @Published var leftAgent: AgentKind {
        didSet {
            UserDefaults.standard.set(leftAgent.rawValue, forKey: Self.leftAgentKey)
            refreshConsumersIfChanged(oldValue, leftAgent)
        }
    }

    @Published var rightAgent: AgentKind {
        didSet {
            UserDefaults.standard.set(rightAgent.rawValue, forKey: Self.rightAgentKey)
            refreshConsumersIfChanged(oldValue, rightAgent)
        }
    }

    @Published var openClawRoot: String {
        didSet {
            UserDefaults.standard.set(openClawRoot, forKey: Self.openClawRootKey)
            refreshConsumersIfChanged(oldValue, openClawRoot)
        }
    }

    @Published var codexRoot: String {
        didSet {
            UserDefaults.standard.set(codexRoot, forKey: Self.codexRootKey)
            refreshConsumersIfChanged(oldValue, codexRoot)
        }
    }

    @Published var claudeCodeRoot: String {
        didSet {
            UserDefaults.standard.set(claudeCodeRoot, forKey: Self.claudeCodeRootKey)
            refreshConsumersIfChanged(oldValue, claudeCodeRoot)
        }
    }

    private init() {
        self.leftAgent = Self.agent(forKey: Self.leftAgentKey, default: .openClaw)
        self.rightAgent = Self.agent(forKey: Self.rightAgentKey, default: .codex)
        self.openClawRoot = Self.string(forKey: Self.openClawRootKey, default: AgentKind.openClaw.defaultRoot)
        self.codexRoot = Self.string(forKey: Self.codexRootKey, default: AgentKind.codex.defaultRoot)
        self.claudeCodeRoot = Self.string(forKey: Self.claudeCodeRootKey, default: AgentKind.claudeCode.defaultRoot)
    }

    func agent(for slot: AlertEngine.Provider) -> AgentKind {
        switch slot {
        case .claude: return leftAgent
        case .codex: return rightAgent
        }
    }

    func root(for agent: AgentKind) -> String {
        switch agent {
        case .openClaw: return normalized(openClawRoot, fallback: agent.defaultRoot)
        case .codex: return normalized(codexRoot, fallback: agent.defaultRoot)
        case .claudeCode: return normalized(claudeCodeRoot, fallback: agent.defaultRoot)
        }
    }

    func root(for slot: AlertEngine.Provider) -> String {
        root(for: agent(for: slot))
    }

    func displayName(for slot: AlertEngine.Provider) -> String {
        agent(for: slot).displayName
    }

    func shortName(for slot: AlertEngine.Provider) -> String {
        agent(for: slot).shortName
    }

    func isCodexVisible(visibility: ProviderVisibilityStore) -> Bool {
        (visibility.claudeVisible && leftAgent == .codex)
            || (visibility.codexVisible && rightAgent == .codex)
    }

    private func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func refreshConsumersIfChanged<T: Equatable>(_ oldValue: T, _ newValue: T) {
        guard oldValue != newValue else { return }
        UsageStore.shared.refresh()
        CostStore.shared.refresh()
    }

    private static func agent(forKey key: String, default fallback: AgentKind) -> AgentKind {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let agent = AgentKind(rawValue: raw)
        else { return fallback }
        return agent
    }

    private static func string(forKey key: String, default fallback: String) -> String {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return fallback }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : raw
    }
}
