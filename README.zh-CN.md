# codexisland4custom for OpenClaw

[English](README.md) | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="Assets/codexisland-logo.png" width="160" alt="codexisland4custom logo">
</p>

> 面向 OpenClaw / AutoClaw 和 Codex 用量、费用统计的 codexisland4custom 定制版。

## 魔改说明

本仓库是基于原版 CodexIsland 的个人魔改版本，仅限个人学习、研究和自用。它不是 codexisland4custom 官方版本，也不作为商业分发或公共服务使用。

默认左侧服务是 **OpenClaw**，右侧服务是 **Codex**。在设置 -> Providers 里，两侧都可以改成 **OpenClaw**、**Codex** 或 **Claude Code**，并且每个 Agent 的 root 路径都可以自定义。

应用是一个原生 macOS 刘海 / Dynamic Island 风格悬浮层，可以展示用量面板，以及基于本机会话日志计算的费用页面。本项目不会提交或上传你的 OpenClaw API key。

## 这个定制版改了什么

- **左侧从 Claude 改为 OpenClaw。**
  - UI 名称、logo、本地费用来源都改为 OpenClaw。
  - OpenClaw 没有 Claude 那种账号额度接口，所以 OpenClaw 的实时额度卡片是被动状态，不再调用 Claude/Anthropic OAuth。
- **读取 OpenClaw / AutoClaw 本地日志。**
  - 默认目录：`~/.openclaw-autoclaw`
  - 可用环境变量覆盖：`OPENCLAW_HOME=/path/to/openclaw-home`
  - 扫描路径：
    - `~/.openclaw-autoclaw/sessions`
    - `~/.openclaw-autoclaw/agents/*/sessions`
  - 会跳过 trajectory / checkpoint JSONL 文件。
- **费用页面重做。**
  - 按模型展示费用表。
  - 展示今日、本月、历史总费用。
  - 展示近 7 天按天汇总的总费用趋势图。
- **自定义模型分开统计。**
  - 例如 `gpt-5.5`、`cx/gpt-5.5-high`、`cx/gpt-5.5-medium`、`cx/gpt-5.5-xhigh` 会分开显示。
  - 但计费价格仍可以匹配内置基础模型价格表。
- **支持 OpenClaw 模型别名。**
  - 会读取 `openclaw.json` 中的 provider/model alias。
  - 例如网关内部模型可以显示为 `deepseek-v4-pro-jiayin`，但计费价格回退到 `deepseek-v4-pro`。
- **支持 DeepSeek 自定义价格。**
  - 价格表中加入了 `deepseek-v4-pro`。
  - 计费匹配时会去掉 `-jiayin` 和 `-自费版` 后缀。
- **Codex 功能保留。**
  - Codex 实时用量仍读取本地 Codex 登录状态并调用 Codex/ChatGPT 用量接口。
  - Codex 费用仍从本地 Codex 会话日志计算。

## 安装

这个 fork 目前没有单独的 Homebrew tap。

如果本仓库的 GitHub Releases 里发布了 DMG，可以从这里下载：

```text
https://github.com/shawn9960206-dotcom/codexisland4custom/releases
```

因为应用没有 Apple Developer ID 签名，macOS 第一次打开时可能会拦截。把 app 拖到 `/Applications` 后，可以运行：

```sh
xattr -dr com.apple.quarantine /Applications/codexisland4custom.app
```

也可以打开 **系统设置 -> 隐私与安全性**，找到被拦截的 codexisland4custom 提示，点击 **仍要打开**。

## 可配置 Agent

打开设置 -> Providers 可以选择每一栏显示的 Agent：

- Left column / Right column：`OpenClaw`、`Codex` 或 `Claude Code`
- OpenClaw 默认 root：`~/.openclaw-autoclaw`
- Codex 默认 root：`~/.codex`
- Claude Code 默认 root：`~/.claude`

这些 root 设置会用于本地日志扫描。Codex 实时用量也会从配置的 Codex root 读取 `auth.json`。Claude Code 实时用量在存在文件凭据时会使用配置的 Claude root，否则回退到 macOS Keychain。

## 首次运行

codexisland4custom 不会询问你的密码或 API key。

### OpenClaw

OpenClaw 费用统计需要你本机已经使用过 OpenClaw / AutoClaw，并且日志存在于：

```text
~/.openclaw-autoclaw
```

如果你的 OpenClaw 目录不在默认位置，可以这样启动：

```sh
launchctl setenv OPENCLAW_HOME /your/openclaw/home
open /Applications/codexisland4custom.app
```

OpenClaw 统计只读取本地日志。`openclaw.json` 里的 API key 不会被提交到本仓库，也不会被应用上传。

如果只是想从终端临时运行一次，也可以直接启动二进制：

```sh
OPENCLAW_HOME=/your/openclaw/home /Applications/codexisland4custom.app/Contents/MacOS/codexisland4custom
```

### Codex

Codex 实时用量需要：

- 先登录 Codex / ChatGPT CLI。
- codexisland4custom 读取 `~/.codex/auth.json`。
- 如果文件或 access token 缺失，面板会显示 `no codex auth`。

Codex 费用统计会读取本地 Codex 会话日志：`~/.codex/sessions/`。

## 使用

- 悬停刘海，预览当前用量。
- 点击岛，展开完整面板。
- 在面板上横向滑动，或点击底部圆点，在 **Usage**、**Cost** 和 **Overview** 之间切换。
- 点击面板头部的 `synced Xs ago` 可立即刷新。
- 点击展开面板里的齿轮打开设置。
- 鼠标在岛上时按 `⌘Q` 可以退出，也可以从设置里退出。

服务可见性只影响显示。隐藏左栏或右栏会把对应栏位从 UI 移除，但缓存值仍会保留，重新显示时可继续使用。

## 费用计算说明

费用是根据本地 JSONL 会话日志中的 token usage 估算出来的。

- OpenClaw 读取器：`Sources/Cost/OpenClawLogReader.swift`
- Codex 读取器：`Sources/Cost/CodexLogReader.swift`
- 价格表：`Sources/Cost/Pricing.swift`

只有能匹配内置价格表或别名规则的模型才能计算费用。未知模型可能能显示 token，但费用为 0 或不显示，需要在价格表里补充。

当前定制逻辑包括：

- `cx/gpt-5.5-high` 等自定义模型名分开统计；
- 自定义变体可回退匹配基础模型价格；
- DeepSeek `deepseek-v4-pro` 价格；
- 计费匹配时去掉 `-jiayin` / `-自费版` 后缀。

## 从源码构建

需要 macOS 13+ 和 Xcode Command Line Tools。

```sh
git clone https://github.com/shawn9960206-dotcom/codexisland4custom.git
cd codexisland4custom
./build.sh
open build/codexisland4custom.app
```

这个项目没有 Xcode project，也没有 SwiftPM package。`build.sh` 会直接用 `swiftc` 编译 `Sources/**/*.swift`，分别构建 arm64 和 x86_64，再用 `lipo` 合并为通用二进制，复制资源并写入 `Info.plist`。

冒烟测试：

```sh
./scripts/run-tests.sh
./scripts/verify.sh
```

## 打包 DMG

先安装 `create-dmg`：

```sh
npm install --global create-dmg
```

然后运行：

```sh
./release.sh
```

DMG 会生成在 `dist/` 目录，例如：

```text
dist/codexisland4custom-0.1.16.dmg
```

应用会做 ad-hoc codesign，但不是 Apple Developer ID 签名，所以其他用户下载后可能仍需要移除 quarantine 或点击 **仍要打开**。

## 仓库结构

```text
.
├── Sources/
│   ├── Cost/                # 本地日志费用与 token 聚合
│   ├── Localization/        # 运行时多语言辅助
│   ├── Model/
│   ├── Theme/
│   ├── Update/              # Sparkle 更新封装
│   ├── Usage/
│   ├── Views/
│   └── Window/
├── Resources/              # 图标、服务 logo、本地化字符串
├── Assets/                 # README logo
├── Tests/                  # swiftc 测试脚本
├── docs/                   # Sparkle / 设计文档
├── Casks/                  # 原版 Homebrew Cask 模板
├── scripts/                # 测试、冒烟测试、Sparkle 安装脚本
├── build.sh                # 通用 .app 构建脚本
├── release.sh              # DMG 打包脚本
└── VERSION
```

## 隐私

原生应用行为：

- 没有应用遥测。
- 没有应用分析。
- 没有崩溃上报。
- 没有代理服务器。
- codexisland4custom 不保存凭据。
- OpenClaw 费用数据从配置的 OpenClaw root 本地读取，默认是 `~/.openclaw-autoclaw`；未自定义时也兼容 `OPENCLAW_HOME`。
- Codex token 只从本机 `~/.codex/auth.json` 读取，用于 Codex 用量刷新。
- 日志聚合完全在本机完成，会话日志内容不会被应用上传。

网络使用：

- Codex 实时用量刷新可能会带着你已有的 Codex auth token 访问 Codex / ChatGPT 接口。
- OpenClaw 费用统计只依赖本地日志。
- 如果开启 Sparkle 自动更新，可能会访问本仓库的 GitHub Releases。

## 常见问题

**OpenClaw 费用缺失或偏低。**

检查 OpenClaw 日志是否存在于 `~/.openclaw-autoclaw/sessions` 或 `~/.openclaw-autoclaw/agents/*/sessions`。如果日志在别的位置，请设置 `OPENCLAW_HOME`。

**某个模型有 token 但没有费用。**

通常是模型名没有匹配到内置价格表。需要在 `Sources/Cost/Pricing.swift` 里补充价格或别名规则。

**Codex 显示 `no codex auth`。**

先登录 Codex / ChatGPT CLI，并确认 `~/.codex/auth.json` 存在。

**Codex 显示 `auth expired — codex login`。**

运行 `codex login` 刷新 `~/.codex/auth.json` 里的凭据。

**出错后应用显示旧值。**

这是有意设计。`UsageStore` 会在刷新失败时保留上一次成功值，避免临时错误把面板变成 0%。

**没有刘海的 Mac 能用吗？**

可以。它会退回到菜单栏胶囊，设置里也可以切换成更宽的刘海风格间距。

**支持多显示器吗？**

支持，但同时只显示一个 island。Auto 模式优先选择有刘海的屏幕，然后是主屏；也可以在设置里固定到某个显示器。

## 已知限制

- 未签名构建需要移除 quarantine 或点击仍要打开。
- 这个 fork 中 OpenClaw 没有实时额度接口，OpenClaw 费用基于本地日志。
- Codex 用量接口不是公开稳定接口，未来可能变化。
- Sparkline 历史只包含 codexisland4custom 运行期间记录到的数据。
- 多显示器同时只显示一个 island。

## License

MIT - see [LICENSE](LICENSE).
