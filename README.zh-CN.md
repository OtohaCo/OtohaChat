# OtohaChat

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

OtohaChat 是 **[Otoha AI Player](https://otoha.co)** 所用 Swift AI Harness——**[SwiftAgent](https://github.com/OtohaCo/SwiftAgent)**——的原生 SwiftUI 演示。聊天界面展示这份运行时如何接入：Agent、Session、Run、流式输出、宿主工具、可恢复的 Journal，以及各家模型适配器。

同一套程序也跑当前 iOS / macOS 自带的 Apple **Foundation Models**。符合条件的设备上，端侧模型与 **Private Cloud Compute（PCC）** 不需要单独的云端模型 API key。

<p>
  <a href="https://testflight.apple.com/join/BCDWj1h1">
    <img src="docs/images/view-on-testflight.zh.svg" alt="在 TestFlight 中打开" height="56">
  </a>
</p>

公开 TestFlight（iOS 与 macOS）：[https://testflight.apple.com/join/BCDWj1h1](https://testflight.apple.com/join/BCDWj1h1)

![macOS 上的 OtohaChat，当前会话使用 Apple Private Cloud Compute。侧栏列出 DeepSeek、Composer、GPT、Grok 与 Apple PCC 对话。打开的对话中，calculator 返回 1+2+3 = 6，workspace_read 报告 .agents/skills 下有 106 个 skill。](docs/images/otohachat-macos.png)

macOS 版 OtohaChat，运行时为 Apple PCC（`private-cloud-compute`）。普通对话、`calculator` 工具，以及对已授权工作区的 `workspace_read`，都在同一条 Session 里完成。

## Harness 在做什么

[Otoha AI Player](https://otoha.co) 是听歌与听读应用。逐行讲解、追问和相关 AI 能力走 SwiftAgent。OtohaChat 把同一套运行时放进类似 ChatGPT 的窗口，方便查看 Host 契约：

| Host 职责 | OtohaChat 中的对应 |
| --- | --- |
| 运行时 | SwiftAgent `Agent` → `Session` → `Run` → 终态 → drain |
| 流式输出 | 从 `AgentRun.events` 渲染助手文本和可展开的工具卡片 |
| 工具 | 宿主提供的 `calculator`、`datetime`、`workspace_read`、`app_notes_read`、`app_notes` |
| Skill | 已授权工作区 `.agents/skills` 中的任务上下文。`allowed-tools` 只能写宿主工具。`scripts/` 记为 `UNSUPPORTED_RUNTIME`，不会执行 |
| 持久化 | Journal 与展示用 transcript。API key 只进 Keychain |
| 换模型 | 只作用于下一条消息。厂商私有 continuation 与 reasoning 不随模型带走 |

截图是 PCC，不是云厂商。侧栏是同一 Host 接上其他适配器（DeepSeek、OpenAI 兼容网关、Grok 等）。

## iOS / macOS 上的 Foundation Models

| 运行时 | 含义 | 在本应用中 |
| --- | --- | --- |
| 端侧 | 设备上的 Apple Foundation Models | 设置 → Apple on-device。不需要 API key |
| Private Cloud Compute | PCC 上的 Apple Foundation Models | 设置 → Apple PCC。探针为 Available 时作为默认。TestFlight / PCC scheme 会请求 entitlement；账号、设备和地区仍须由 Apple 授予 |

SwiftAgent 1.0.0-rc.3 中的 PCC 仍是实验能力。模型切换器里出现 PCC，不等于仓库已记录完整核心工具循环的 live qualification。在补上已签名案例之前，本仓库将该循环记为 `BLOCKED_CONFIGURATION`。

可选云厂商（设置页，仅 Keychain）：OpenAI Responses、Anthropic、DeepSeek、本地 Responses、兼容的 `/responses` 网关。

## 安装已编译的演示程序

1. 需要时安装 [TestFlight](https://apps.apple.com/app/testflight/id899247664)。
2. 在 iPhone、iPad 或 Mac 上打开 [https://testflight.apple.com/join/BCDWj1h1](https://testflight.apple.com/join/BCDWj1h1)，使用要接收测试版的 Apple ID。
3. Apple 模型需要设备实际提供端侧或 PCC。云厂商在设置里填写 API key。

显示名：`OtohaChat`。Bundle ID：`co.otoha.OtohaChat`。

## 从源码编译

1. 克隆本仓库。不依赖 Tingting、旁边的 `SwiftAgent` 目录，也不依赖 ProviderQualification。
2. 用 Xcode 16 或更新版本打开 `OtohaChat.xcodeproj`（开发环境为 Xcode 27）。
3. 运行 **OtohaChat** scheme（macOS）。该 scheme 不请求 PCC entitlement。
4. PCC 状态为 **Available** 时，新对话优先 PCC；否则在设置里选端侧或云厂商。
5. 可选：授权 `DemoWorkspace`，发送 `/skill docs-qa` 或 `/skill note-capture`。

日常使用不需要 dotenv，也不需要预算 JSON。

| Scheme | 用途 |
| --- | --- |
| **OtohaChat** | 默认 macOS 应用。不请求 PCC entitlement |
| **OtohaChat-iOS** | iOS / iPadOS，共用 kit |
| **OtohaChat-PCC** | 同一应用，带 `OTOHACHAT_PCC` 与 PCC entitlements 文件。这不会替设备完成 Apple 授权 |

个人 `DEVELOPMENT_TEAM` 可把 `Config/Local.xcconfig.example` 复制为 `Config/Local.xcconfig`。该文件已加入 gitignore。不要提交证书或描述文件。

## SDK 固定版本

- 包：https://github.com/OtohaCo/SwiftAgent
- 版本：`1.0.0-rc.3`
- Revision：`d5383a26849f45d8a442c24aebfb0b7ca4798dd5`

`Package.swift` 中为 `exact: "1.0.0-rc.3"`，并锁定在 `Package.resolved`。应用源码不内嵌 SDK，也不改 RC3。

## 提供方

| 类型 | API | 说明 |
| --- | --- | --- |
| Apple PCC | Foundation Models PCC | 可用时作为默认。RC3 中仍为实验 |
| Apple 端侧 | Foundation Models | 具备能力的硬件上，macOS 26 / iOS 26 及更新 |
| OpenAI Responses | `/responses` | HTTPS。未选择时省略 effort |
| Anthropic | Messages | RC3 目录提供 effort 与 thinking 对象 |
| DeepSeek Responses | `/responses` | 始终发送 effort；默认 high |
| 本地 Responses | Responses 兼容 | 允许 loopback HTTP。不是 Chat Completions |
| 兼容网关 | OpenAI Responses 方言 | 包括 SUB2API 一类 `/responses` 代理 |

TypeSafe / Jev 决策提供方不作为聊天模型列出。

## 测试

```sh
bash Scripts/gate.sh
```

`swift test` 覆盖 Keychain 隔离（内存仓库）、端点、带 mock transport 的目录与 reasoning 映射、会话 drain、工具、skill，以及交接提示。

PCC 核心循环：`Tests/OtohaChatKitTests/PCCLiveLoopTests.swift` 在未设置 `OTOHACHAT_PCC_LIVE=1`、且无已授予 entitlement 时记录 `BLOCKED_CONFIGURATION`。

## 许可

MIT。会话控制器与 execution report 代码改编自 SwiftAgent Examples（MIT，ChainBow Co., Ltd.）。见 `NOTICE`。

OtohaChat 与 OpenAI、Anthropic、DeepSeek、xAI 或 Apple Intelligence 产品品牌无隶属关系。这些名称只作为对应 API 的配置标签出现。
