import Foundation

/// Walks OpenClaw / AutoClaw local session logs and emits TokenEvents for
/// assistant messages that recorded token usage. This intentionally feeds the
/// existing left-side provider slot (`.claude`) so the UI can be repurposed as
/// "OpenClaw" without touching the rest of the cost pipeline.
///
/// Default root: `~/.openclaw-autoclaw`
/// Env override: `OPENCLAW_HOME=/path/to/openclaw-home`
///
/// We parse only regular session `*.jsonl` files under:
///   - `$OPENCLAW_HOME/sessions`
///   - `$OPENCLAW_HOME/agents/*/sessions`
///
/// Trajectory and checkpoint logs are deliberately skipped because they repeat
/// per-call usage already present in the regular session JSONL files.
enum OpenClawLogReader {
    static func scan(lookbackDays: Int = 30, rootPath: String? = nil) -> [TokenEvent] {
        let cutoff = Date().addingTimeInterval(-Double(lookbackDays) * 86400)
        let aliases = configuredModelNames(rootPath: rootPath)
        var seen = Set<String>()
        var out: [TokenEvent] = []

        LogParseCache.walk(
            roots: sessionRoots(rootPath: rootPath),
            cutoff: cutoff,
            cacheFilename: "openclaw-parse-cache.v1.json",
            cacheVersion: cacheVersion,
            fileFilter: isRegularSessionJSONL,
            parse: { parseFile(at: $0, aliases: aliases) },
            emit: { (ev: CachedEvent) in
                guard ev.timestamp >= cutoff else { return }
                if !ev.dedupKey.isEmpty {
                    if seen.contains(ev.dedupKey) { return }
                    seen.insert(ev.dedupKey)
                }
                out.append(TokenEvent(
                    provider: .claude,
                    timestamp: ev.timestamp,
                    model: ev.model,
                    inputTokens: ev.inputTokens,
                    outputTokens: ev.outputTokens,
                    cacheCreationTokens: ev.cacheCreationTokens,
                    cacheReadTokens: ev.cacheReadTokens
                ))
            }
        )
        return out
    }

    private static func sessionRoots(rootPath: String? = nil) -> [URL] {
        let fm = FileManager.default
        let home = openClawHome(rootPath: rootPath)
        var roots: [URL] = []

        let topSessions = home.appendingPathComponent("sessions", isDirectory: true)
        if fm.fileExists(atPath: topSessions.path) { roots.append(topSessions) }

        let agents = home.appendingPathComponent("agents", isDirectory: true)
        if let agentDirs = try? fm.contentsOfDirectory(
            at: agents,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for agent in agentDirs {
                let sessions = agent.appendingPathComponent("sessions", isDirectory: true)
                if fm.fileExists(atPath: sessions.path) { roots.append(sessions) }
            }
        }
        return roots
    }

    private static func openClawHome(rootPath: String? = nil) -> URL {
        let raw = normalizedRoot(
            rootPath
                ?? ProcessInfo.processInfo.environment["OPENCLAW_HOME"]
                ?? "~/.openclaw-autoclaw",
            fallback: "~/.openclaw-autoclaw"
        )
        return expandRoot(raw)
    }

    private static func expandRoot(_ raw: String) -> URL {
        if raw == "~" {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        if raw.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(raw.dropFirst(2)), isDirectory: true)
        }
        return URL(fileURLWithPath: raw, isDirectory: true)
    }

    private static func normalizedRoot(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func isRegularSessionJSONL(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.hasSuffix(".jsonl") else { return false }
        if name.hasSuffix(".trajectory.jsonl") { return false }
        if name.contains(".checkpoint.") { return false }
        return true
    }

    private static func configuredModelNames(rootPath: String? = nil) -> [String: String] {
        let config = openClawHome(rootPath: rootPath).appendingPathComponent("openclaw.json")
        guard let data = try? Data(contentsOf: config),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [String: Any],
              let providers = models["providers"] as? [String: Any]
        else { return [:] }

        var out: [String: String] = [:]
        for (providerID, providerValue) in providers {
            guard let provider = providerValue as? [String: Any],
                  let providerModels = provider["models"] as? [[String: Any]]
            else { continue }
            for model in providerModels {
                guard let id = stringValue(model["id"]),
                      let name = stringValue(model["name"])
                else { continue }
                out["\(providerID)/\(id)"] = name
            }
        }
        return out
    }

    private static func displayModelName(provider: String?, modelId: String, aliases: [String: String]) -> String {
        if let provider, let alias = aliases["\(provider)/\(modelId)"] {
            return alias
        }
        return modelId
    }

    private static func parseFile(at url: URL, aliases: [String: String]) -> [CachedEvent] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFractional = ISO8601DateFormatter()
        formatterNoFractional.formatOptions = [.withInternetDateTime]

        var out: [CachedEvent] = []
        var currentModel: String?
        var currentProvider: String?

        LogParseCache.streamLines(at: url) { lineData in
            guard let raw = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { return }

            if let type = raw["type"] as? String,
               type == "model_change" || type == "model.changed" {
                currentModel = stringValue(raw["modelId"])
                    ?? stringValue(raw["model"])
                    ?? currentModel
                currentProvider = stringValue(raw["provider"]) ?? currentProvider
                return
            }

            if let event = parseUsageRow(
                raw,
                filePath: url.path,
                currentModel: currentModel,
                currentProvider: currentProvider,
                aliases: aliases,
                formatter: formatter,
                formatterNoFractional: formatterNoFractional
            ) {
                out.append(event)
            }
        }
        return out
    }

    private static func parseUsageRow(
        _ raw: [String: Any],
        filePath: String,
        currentModel: String?,
        currentProvider: String?,
        aliases: [String: String],
        formatter: ISO8601DateFormatter,
        formatterNoFractional: ISO8601DateFormatter
    ) -> CachedEvent? {
        guard let message = raw["message"] as? [String: Any],
              (message["role"] as? String) == "assistant",
              let usage = message["usage"] as? [String: Any]
        else { return nil }

        let provider = stringValue(message["provider"])
            ?? stringValue(raw["provider"])
            ?? currentProvider
        let rawModel = stringValue(message["model"])
            ?? stringValue(raw["modelId"])
            ?? currentModel
            ?? "openclaw-unknown"
        let model = displayModelName(provider: provider, modelId: rawModel, aliases: aliases)

        if model == "<synthetic>" || model.hasPrefix("synthetic") { return nil }

        let input = intValue(usage["input"])
            ?? intValue(usage["input_tokens"])
            ?? intValue(usage["prompt_tokens"])
            ?? 0
        let output = intValue(usage["output"])
            ?? intValue(usage["output_tokens"])
            ?? intValue(usage["completion_tokens"])
            ?? 0
        let cacheRead = intValue(usage["cacheRead"])
            ?? intValue(usage["cache_read"])
            ?? intValue(usage["cache_read_input_tokens"])
            ?? intValue(usage["cached_input_tokens"])
            ?? 0
        let cacheCreate = intValue(usage["cacheWrite"])
            ?? intValue(usage["cache_write"])
            ?? intValue(usage["cache_creation"])
            ?? intValue(usage["cache_creation_input_tokens"])
            ?? 0

        if input == 0 && output == 0 && cacheCreate == 0 && cacheRead == 0 { return nil }

        let timestampString = stringValue(raw["timestamp"])
            ?? stringValue(raw["ts"])
            ?? ""
        let timestamp = formatter.date(from: timestampString)
            ?? formatterNoFractional.date(from: timestampString)
            ?? Date.distantPast

        let responseId = stringValue(message["responseId"])
            ?? stringValue(message["id"])
        let rowId = stringValue(raw["id"])
        let dedupKey: String
        if let responseId, !responseId.isEmpty {
            dedupKey = "openclaw-response:\(responseId)"
        } else if let rowId, !rowId.isEmpty {
            dedupKey = "openclaw-row:\(filePath):\(rowId)"
        } else {
            dedupKey = "openclaw-fingerprint:\(filePath):\(timestampString):\(model):\(input):\(output):\(cacheCreate):\(cacheRead)"
        }

        return CachedEvent(
            timestamp: timestamp,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cacheCreate,
            cacheReadTokens: cacheRead,
            dedupKey: dedupKey
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let s as String:
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let d as Double: return Int(d)
        case let s as String: return Int(s)
        default: return nil
        }
    }

    private static let cacheVersion = 2

    private struct CachedEvent: Codable {
        let timestamp: Date
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int
        let dedupKey: String
    }
}
