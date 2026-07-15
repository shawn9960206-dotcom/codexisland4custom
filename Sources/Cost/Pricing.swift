import Foundation

/// Embedded snapshot of per-million-token API prices in USD. Mirrors LiteLLM's
/// `model_prices_and_context_window.json` for the models we actually expect
/// in Claude Code and Codex CLI sessions, so totals cross-check against
/// `npx ccusage` and `npx @ccusage/codex` to within rounding.
///
/// To refresh: bump `snapshotDate` and re-fetch the four rates per model
/// from `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`.
/// Unknown models silently price to $0 — same behavior as ccusage when
/// LiteLLM has no entry.
enum Pricing {
    static let snapshotDate = "2026-07-10"

    struct Rates {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cacheCreationPerMillion: Double
        let cacheReadPerMillion: Double
    }

    private static let table: [String: Rates] = [
        // Anthropic — LiteLLM lists Opus 4-5/4-6/4-7/4-8 at the same rates
        // (cheaper than the original Opus 4 because Anthropic re-tiered the
        // Opus line in 2025).
        "claude-fable-5": Rates(
            inputPerMillion: 10, outputPerMillion: 50,
            cacheCreationPerMillion: 12.50, cacheReadPerMillion: 1.00
        ),
        "claude-opus-4-8": Rates(
            inputPerMillion: 5, outputPerMillion: 25,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "claude-opus-4-7": Rates(
            inputPerMillion: 5, outputPerMillion: 25,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "claude-opus-4-6": Rates(
            inputPerMillion: 5, outputPerMillion: 25,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "claude-opus-4-5": Rates(
            inputPerMillion: 5, outputPerMillion: 25,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        // Sonnet 5 rates reflect Anthropic's introductory pricing ($2/$10
        // through 2026-08-31; $3/$15 after) — matches LiteLLM's current entry.
        "claude-sonnet-5": Rates(
            inputPerMillion: 2, outputPerMillion: 10,
            cacheCreationPerMillion: 2.50, cacheReadPerMillion: 0.20
        ),
        "claude-sonnet-4-6": Rates(
            inputPerMillion: 3, outputPerMillion: 15,
            cacheCreationPerMillion: 3.75, cacheReadPerMillion: 0.30
        ),
        "claude-sonnet-4-5": Rates(
            inputPerMillion: 3, outputPerMillion: 15,
            cacheCreationPerMillion: 3.75, cacheReadPerMillion: 0.30
        ),
        "claude-haiku-4-5": Rates(
            inputPerMillion: 1, outputPerMillion: 5,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.10
        ),

        // DeepSeek / Jiayin OpenClaw custom gateway. OpenClaw logs the model
        // id as `deepseek-v4-pro`; provider aliases in openclaw.json may
        // display it as `deepseek-v4-pro-jiayin` or `...-自费版`.
        // Rates use the common DeepSeek reasoner/pro tier per-million USD:
        // cache miss input $0.55, output $2.19, cache hit/read $0.14.
        "deepseek-v4-pro": Rates(
            inputPerMillion: 0.55, outputPerMillion: 2.19,
            cacheCreationPerMillion: 0.55, cacheReadPerMillion: 0.14
        ),

        // OpenAI — Codex CLI tags conversations with the chat-completion
        // model name. cache_creation has no separate rate (OpenAI bills
        // cache writes at the standard input rate).
        // Base reasoning models (newest first). Starting with 5.6, OpenAI
        // bills cache writes at 1.25x input (matching Anthropic) instead of
        // the standard input rate.
        "gpt-5.6": Rates(
            inputPerMillion: 5, outputPerMillion: 30,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "gpt-5.6-sol": Rates(
            inputPerMillion: 5, outputPerMillion: 30,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "gpt-5.6-terra": Rates(
            inputPerMillion: 2.5, outputPerMillion: 15,
            cacheCreationPerMillion: 3.125, cacheReadPerMillion: 0.25
        ),
        "gpt-5.6-luna": Rates(
            inputPerMillion: 1, outputPerMillion: 6,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.10
        ),
        "gpt-5.5": Rates(
            inputPerMillion: 5, outputPerMillion: 30,
            cacheCreationPerMillion: 5, cacheReadPerMillion: 0.50
        ),
        "gpt-5.4": Rates(
            inputPerMillion: 2.5, outputPerMillion: 15,
            cacheCreationPerMillion: 2.5, cacheReadPerMillion: 0.25
        ),
        "gpt-5.2": Rates(
            inputPerMillion: 1.75, outputPerMillion: 14,
            cacheCreationPerMillion: 1.75, cacheReadPerMillion: 0.175
        ),
        "gpt-5.1": Rates(
            inputPerMillion: 1.25, outputPerMillion: 10,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.125
        ),
        "gpt-5": Rates(
            inputPerMillion: 1.25, outputPerMillion: 10,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.125
        ),
        // Codex variants (newest first).
        "gpt-5.3-codex": Rates(
            inputPerMillion: 1.75, outputPerMillion: 14,
            cacheCreationPerMillion: 1.75, cacheReadPerMillion: 0.175
        ),
        "gpt-5.2-codex": Rates(
            inputPerMillion: 1.75, outputPerMillion: 14,
            cacheCreationPerMillion: 1.75, cacheReadPerMillion: 0.175
        ),
        "gpt-5.1-codex": Rates(
            inputPerMillion: 1.25, outputPerMillion: 10,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.125
        ),
        "gpt-5.1-codex-max": Rates(
            inputPerMillion: 1.25, outputPerMillion: 10,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.125
        ),
        "gpt-5.1-codex-mini": Rates(
            inputPerMillion: 0.25, outputPerMillion: 2,
            cacheCreationPerMillion: 0.25, cacheReadPerMillion: 0.025
        ),
        "gpt-5-codex": Rates(
            inputPerMillion: 1.25, outputPerMillion: 10,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.125
        ),
        // Mini / nano tiers.
        "gpt-5.4-mini": Rates(
            inputPerMillion: 0.75, outputPerMillion: 4.5,
            cacheCreationPerMillion: 0.75, cacheReadPerMillion: 0.075
        ),
        "gpt-5.4-nano": Rates(
            inputPerMillion: 0.2, outputPerMillion: 1.25,
            cacheCreationPerMillion: 0.2, cacheReadPerMillion: 0.02
        ),
        "gpt-5-mini": Rates(
            inputPerMillion: 0.25, outputPerMillion: 2,
            cacheCreationPerMillion: 0.25, cacheReadPerMillion: 0.025
        ),
        "gpt-5-nano": Rates(
            inputPerMillion: 0.05, outputPerMillion: 0.4,
            cacheCreationPerMillion: 0.05, cacheReadPerMillion: 0.005
        ),
        // Pro tier — LiteLLM lists no cache-read rate for gpt-5-pro /
        // gpt-5.2-pro (no prompt caching), so 0 is safe: they emit no
        // cache tokens.
        "gpt-5.5-pro": Rates(
            inputPerMillion: 30, outputPerMillion: 180,
            cacheCreationPerMillion: 30, cacheReadPerMillion: 3
        ),
        "gpt-5.4-pro": Rates(
            inputPerMillion: 30, outputPerMillion: 180,
            cacheCreationPerMillion: 30, cacheReadPerMillion: 3
        ),
        "gpt-5.2-pro": Rates(
            inputPerMillion: 21, outputPerMillion: 168,
            cacheCreationPerMillion: 21, cacheReadPerMillion: 0
        ),
        "gpt-5-pro": Rates(
            inputPerMillion: 15, outputPerMillion: 120,
            cacheCreationPerMillion: 15, cacheReadPerMillion: 0
        ),
    ]

    /// Compute the dollar cost of a single TokenEvent. Returns 0 for unknown
    /// models — ccusage parity. Synthetic placeholder models filtered upstream.
    ///
    /// Anthropic's 1M-context tier (2x rate above 200k tokens) is omitted —
    /// it only affects sonnet-4-5 with the 1M flag and is rarely hit in
    /// Claude Code workflows. ccusage's per-bucket threshold check would
    /// disagree with Anthropic's per-position-in-context billing anyway.
    static func cost(for event: TokenEvent) -> Double {
        let lookup = priceLookupModel(event.model)
        guard let rates = table[lookup] else { return 0 }

        let input = Double(event.inputTokens) / 1_000_000 * rates.inputPerMillion
        let output = Double(event.outputTokens) / 1_000_000 * rates.outputPerMillion
        let cacheCreate = Double(event.cacheCreationTokens) / 1_000_000 * rates.cacheCreationPerMillion
        let cacheRead = Double(event.cacheReadTokens) / 1_000_000 * rates.cacheReadPerMillion

        return input + output + cacheCreate + cacheRead
    }

    /// Whether the embedded snapshot has a price entry for this model.
    /// Lets callers warn the user about unpriced spend without re-implementing
    /// the canonical-name stripping logic.
    static func isKnown(_ rawModel: String) -> Bool {
        table[priceLookupModel(rawModel)] != nil
    }

    /// Calendar days between `snapshotDate` and now (UTC). Returns 0 if the
    /// snapshot string fails to parse, so a malformed constant is treated as
    /// fresh rather than triggering a permanent staleness warning.
    static var daysSinceSnapshot: Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let snapshot = formatter.date(from: snapshotDate) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(identifier: "UTC") { calendar.timeZone = utc }
        let components = calendar.dateComponents([.day], from: snapshot, to: Date())
        return max(0, components.day ?? 0)
    }

    /// Model name used for grouping/breakdowns. Keep user-router decorations
    /// (e.g. "cx/gpt-5.5-high") so variants remain separate in the UI, but
    /// still strip Anthropic-style date suffixes so pinned Claude releases
    /// group with their base model. Pricing uses `priceLookupModel(_:)` below.
    static func canonicalModelName(_ raw: String) -> String {
        stripDateSuffix(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Model name used only for price lookup. Codex can be pointed at
    /// user-owned API gateways / model routers that decorate a known upstream
    /// model with a namespace or effort tier, e.g. "cx/gpt-5.5-high",
    /// "openai/gpt-5.5-medium". Price those as the underlying base model
    /// while preserving the original decorated name for per-model stats.
    private static func priceLookupModel(_ raw: String) -> String {
        var model = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let slash = model.lastIndex(of: "/") {
            model = String(model[model.index(after: slash)...])
        }

        for suffix in ["-自费版", "-jiayin", "-minimal", "-medium", "-xhigh", "-high", "-low"] {
            if model.hasSuffix(suffix) {
                model.removeLast(suffix.count)
                break
            }
        }

        return stripDateSuffix(model)
    }

    private static func stripDateSuffix(_ raw: String) -> String {
        guard raw.count > 9 else { return raw }
        let suffixStart = raw.index(raw.endIndex, offsetBy: -9)
        let suffix = raw[suffixStart...]
        guard suffix.first == "-",
              suffix.dropFirst().allSatisfy({ $0.isNumber })
        else { return raw }
        return String(raw[..<suffixStart])
    }
}
