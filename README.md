# codexisland4custom for OpenClaw

[English](README.md) | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="Assets/codexisland-logo.png" width="160" alt="codexisland4custom logo">
</p>

> A customized codexisland4custom build for OpenClaw / AutoClaw and Codex usage + cost tracking.

## Custom modification notice

This repository is a personal modified build based on the original CodexIsland project. It is intended for personal learning, research, and self-use only. It is not an official codexisland4custom release and is not intended for commercial distribution or public service operation.

By default, the left provider slot is **OpenClaw** and the right provider is **Codex**. In Settings -> Providers, both slots can be changed to **OpenClaw**, **Codex**, or **Claude Code**, and each agent root can be customized.

The app is a native macOS notch / Dynamic-Island-style overlay. It shows live usage panels and a local-first cost page built from local session logs. No OpenClaw API key is committed or uploaded by this project.

## What is different in this fork

- **OpenClaw instead of Claude on the left side.**
  - The UI label, logo, and local cost source use OpenClaw.
  - OpenClaw live quota tiles are passive because OpenClaw does not expose a Claude-style account quota endpoint.
- **Reads OpenClaw / AutoClaw local logs.**
  - Default root: `~/.openclaw-autoclaw`
  - Override with: `OPENCLAW_HOME=/path/to/openclaw-home`
  - Scans:
    - `~/.openclaw-autoclaw/sessions`
    - `~/.openclaw-autoclaw/agents/*/sessions`
  - Skips trajectory / checkpoint JSONL files.
- **Cost screen redesign.**
  - Per-model cost table.
  - Today, current month, and historical total cost stats.
  - 7-day daily total cost trend chart.
- **Custom model statistics stay separate.**
  - For example `gpt-5.5`, `cx/gpt-5.5-high`, `cx/gpt-5.5-medium`, and `cx/gpt-5.5-xhigh` are displayed separately.
  - Pricing lookup can still match the built-in base model price table.
- **OpenClaw model alias support.**
  - Reads OpenClaw config from `openclaw.json` to map provider/model aliases.
  - Example: a gateway/internal model can display as `deepseek-v4-pro-jiayin` while pricing falls back to `deepseek-v4-pro`.
- **DeepSeek custom pricing support.**
  - `deepseek-v4-pro` is included in the price table.
  - `-jiayin` and `-自费版` suffixes are stripped for price lookup.
- **Codex support remains.**
  - Codex live usage still reads local Codex auth and calls Codex/ChatGPT usage endpoints.
  - Codex costs still come from local Codex session logs.

## Install

There is currently no custom Homebrew tap for this fork.

If a DMG is attached to this repository's GitHub Releases, download it from:

```text
https://github.com/shawn9960206-dotcom/codexisland4custom/releases
```

Because the app is unsigned, macOS may block it on first launch. After dragging it to `/Applications`, run:

```sh
xattr -dr com.apple.quarantine /Applications/codexisland4custom.app
```

Or open **System Settings -> Privacy & Security**, find the blocked codexisland4custom message, and click **Open Anyway**.

## Configurable agents

Open Settings -> Providers to choose the agent displayed in each column:

- Left column / right column: `OpenClaw`, `Codex`, or `Claude Code`
- OpenClaw root default: `~/.openclaw-autoclaw`
- Codex root default: `~/.codex`
- Claude Code root default: `~/.claude`

These root settings are used for local log scanning. Codex live usage also reads `auth.json` from the configured Codex root. Claude Code live usage uses Claude Code credentials from the configured Claude root when a file credential store is present, or the macOS Keychain fallback.

## First run

codexisland4custom does not ask for your passwords or API keys.

### OpenClaw

For OpenClaw cost statistics, make sure you have used OpenClaw / AutoClaw locally and that logs exist under:

```text
~/.openclaw-autoclaw
```

If your OpenClaw home is elsewhere, launch the app with:

```sh
launchctl setenv OPENCLAW_HOME /your/openclaw/home
open /Applications/codexisland4custom.app
```

OpenClaw statistics are read from local logs only. Your OpenClaw API keys in `openclaw.json` are not committed to this repository and are not uploaded by the app.

For a temporary one-off run from Terminal, you can also start the binary directly:

```sh
OPENCLAW_HOME=/your/openclaw/home /Applications/codexisland4custom.app/Contents/MacOS/codexisland4custom
```

### Codex

For Codex live usage:

- Sign in to Codex / ChatGPT CLI first.
- codexisland4custom reads `~/.codex/auth.json`.
- If the file or access token is missing, the panel shows `no codex auth`.

For Codex cost statistics, the app reads local Codex session logs from `~/.codex/sessions/`.

## Using the app

- Hover the notch to peek at current usage.
- Click the island to expand the full panel.
- Swipe horizontally on the panel, or use the indicator dots, to switch between **Usage**, **Cost**, and **Overview**.
- Click `synced Xs ago` in the panel header to refresh immediately.
- Click the gear in the expanded panel to open Settings.
- Press `⌘Q` while the pointer is over the island to quit, or quit from Settings.

Provider visibility is display-only. Hiding the left or right column removes that slot from the island UI, but cached values remain available when it is shown again.

## Cost calculation notes

Cost estimates are local calculations based on token usage found in JSONL session logs.

- OpenClaw reader: `Sources/Cost/OpenClawLogReader.swift`
- Codex reader: `Sources/Cost/CodexLogReader.swift`
- Price table: `Sources/Cost/Pricing.swift`

The app can only price models that match the built-in price table or alias rules. Unknown models may show token counts but no cost until pricing is added.

Current custom logic includes:

- separate statistics for custom model names such as `cx/gpt-5.5-high`;
- base-price matching for custom variants;
- DeepSeek `deepseek-v4-pro` pricing;
- stripping `-jiayin` / `-自费版` suffixes for price lookup.

## Build from source

Requires macOS 13+ and Xcode Command Line Tools.

```sh
git clone https://github.com/shawn9960206-dotcom/codexisland4custom.git
cd codexisland4custom
./build.sh
open build/codexisland4custom.app
```

There is no Xcode project and no SwiftPM package. `build.sh` runs `swiftc` over `Sources/**/*.swift`, compiles arm64 and x86_64 slices, merges them with `lipo`, copies bundled resources, and writes `Info.plist`.

Smoke test:

```sh
./scripts/run-tests.sh
./scripts/verify.sh
```

## Package a DMG

Install `create-dmg` first:

```sh
npm install --global create-dmg
```

Then run:

```sh
./release.sh
```

The DMG will be generated under `dist/`, for example:

```text
dist/codexisland4custom-0.1.16.dmg
```

The app is ad-hoc signed but not Apple Developer ID signed, so other users may still need to remove quarantine or choose **Open Anyway**.

## Repository layout

```text
.
├── Sources/
│   ├── Cost/                # Local-log cost + token aggregation
│   ├── Localization/        # Runtime localization helper
│   ├── Model/
│   ├── Theme/
│   ├── Update/              # Sparkle wrapper
│   ├── Usage/
│   ├── Views/
│   └── Window/
├── Resources/              # Icons, provider marks, localized strings
├── Assets/                 # README logo asset
├── Tests/                  # Bare-swiftc regression harnesses
├── docs/                   # Sparkle notes / design specs
├── Casks/                  # Original Homebrew Cask template
├── scripts/                # Tests, native smoke test, Sparkle setup
├── build.sh                # Universal .app build
├── release.sh              # DMG packaging
└── VERSION
```

## Privacy

Native app behavior:

- No app telemetry.
- No app analytics.
- No crash reporting.
- No proxy server.
- No credentials are stored by codexisland4custom.
- OpenClaw cost data is read locally from the configured OpenClaw root, `~/.openclaw-autoclaw` by default, or `OPENCLAW_HOME` when no custom root is set.
- Codex tokens are read locally from `~/.codex/auth.json` for Codex usage refresh.
- Log aggregation happens on-device; session log content is not uploaded by the app.

Network usage:

- Codex live usage refresh may contact Codex / ChatGPT endpoints using your existing Codex auth token.
- OpenClaw cost statistics are local-log only.
- Sparkle update checks may contact this repository's GitHub Releases if enabled.

## Troubleshooting

**OpenClaw cost is missing or too low.**

Check that OpenClaw logs exist under `~/.openclaw-autoclaw/sessions` or `~/.openclaw-autoclaw/agents/*/sessions`. If your logs are elsewhere, set `OPENCLAW_HOME`.

**A model has tokens but no cost.**

The model probably does not match the built-in price table. Add its price or alias logic in `Sources/Cost/Pricing.swift`.

**Codex shows `no codex auth`.**

Sign in to Codex / ChatGPT CLI and confirm `~/.codex/auth.json` exists.

**Codex shows `auth expired — codex login`.**

Run `codex login` to refresh the credentials in `~/.codex/auth.json`.

**The app shows stale values after an error.**

That is intentional. `UsageStore` keeps previous good values when a refresh returns only errors, so a temporary error does not turn the panel into 0%.

**Does it work without a notch?**

Yes. It falls back to a compact menu-bar pill; Settings can switch it to the wider notch-style spacing.

**Does it support multiple monitors?**

Yes, with one island at a time. Auto mode prefers a notched display, then the main display. You can also pin the island to a connected display in Settings.

## Known limits

- Unsigned builds require dequarantine / Open Anyway.
- OpenClaw has no live quota endpoint in this fork; OpenClaw cost is local-log based.
- Codex usage endpoints are undocumented and may change.
- Sparkline history contains only readings recorded while codexisland4custom is running.
- Multi-monitor setups use one island at a time.

## License

MIT - see [LICENSE](LICENSE).
