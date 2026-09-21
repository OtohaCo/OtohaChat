# OtohaChat

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

OtohaChat is a native SwiftUI host for **[SwiftAgent](https://github.com/OtohaCo/SwiftAgent)**, the Swift AI harness used inside **[Otoha AI Player](https://otoha.co)**. The chat UI is a working example of that harness: Agent, Session, Run, streaming, host tools, a durable Journal, and provider adapters.

The same app also runs Apple **Foundation Models** that ship with current iOS and macOS. On supported hardware those models do not need a separate cloud API key: the on-device model, and **Private Cloud Compute (PCC)** when the device, region, and Apple account allow it.

<p>
  <a href="https://testflight.apple.com/join/BCDWj1h1">
    <img src="docs/images/view-on-testflight.svg" alt="View on TestFlight" height="56">
  </a>
</p>

Public TestFlight (iOS and macOS): [https://testflight.apple.com/join/BCDWj1h1](https://testflight.apple.com/join/BCDWj1h1)

![OtohaChat on macOS using Apple Private Cloud Compute. The sidebar lists chats on DeepSeek, Composer, GPT, Grok, and Apple PCC. The open chat shows a calculator tool returning 1+2+3 = 6 and workspace_read reporting 106 skills under .agents/skills.](docs/images/otohachat-macos.png)

macOS build of OtohaChat on Apple PCC (`private-cloud-compute`). Ordinary chat, the `calculator` tool, and `workspace_read` against an authorized workspace run in the same Session.

## What the harness is doing

[Otoha AI Player](https://otoha.co) is a listening app. Line explanations, follow-ups, and related AI work go through SwiftAgent. OtohaChat keeps that same runtime in a ChatGPT-style window so the Host contract is visible:

| Host concern | What OtohaChat shows |
| --- | --- |
| Runtime | SwiftAgent `Agent` → `Session` → `Run` → terminal → drain |
| Streaming | Assistant text and expandable tool cards from `AgentRun.events` |
| Tools | Host-owned `calculator`, `datetime`, `workspace_read`, `app_notes_read`, `app_notes` |
| Skills | Task context from an authorized `.agents/skills` tree. `allowed-tools` can only name host tools. `scripts/` is `UNSUPPORTED_RUNTIME` and is not executed |
| Persistence | Journal plus a display transcript. API keys stay in Keychain |
| Model switch | Next message only. Provider-private continuation and reasoning stay with the previous model |

The screenshot is PCC, not a cloud vendor. The sidebar is the same Host with other adapters (DeepSeek, OpenAI-compatible gateways, Grok, and so on).

## Foundation Models on iOS and macOS

| Runtime | What it is | In this app |
| --- | --- | --- |
| On-device | Apple Foundation Models on the device | Settings → Apple on-device. No API key |
| Private Cloud Compute | Apple Foundation Models in PCC | Settings → Apple PCC. Default when the probe reports Available. The TestFlight / PCC scheme requests the entitlement; Apple still has to grant the account, device, and region |

PCC in SwiftAgent 1.0.0-rc.3 is experimental. Seeing PCC in the model picker is not the same as a recorded live core-loop qualification. This repository still lists that loop as `BLOCKED_CONFIGURATION` until a signed case is written up here.

Optional cloud providers (Settings, Keychain only): OpenAI Responses, Anthropic, DeepSeek, local Responses, compatible `/responses` gateways.

## Try the compiled demo

1. Install [TestFlight](https://apps.apple.com/app/testflight/id899247664) if needed.
2. Open [https://testflight.apple.com/join/BCDWj1h1](https://testflight.apple.com/join/BCDWj1h1) on iPhone, iPad, or Mac, signed into the Apple ID that should receive the beta.
3. For Apple models, use a device that offers on-device or PCC. Cloud vendors need an API key in Settings.

Display name: `OtohaChat`. Bundle ID: `co.otoha.OtohaChat`.

## Build from source

1. Clone this repository. It does not depend on Tingting, a sibling `SwiftAgent` checkout, or ProviderQualification.
2. Open `OtohaChat.xcodeproj` in Xcode 16 or later (Xcode 27 is used in development).
3. Run the **OtohaChat** scheme (macOS). That scheme does not request a PCC entitlement.
4. If PCC status is **Available**, the first chat prefers PCC. Otherwise pick on-device or a cloud provider in Settings.
5. Optional: authorize `DemoWorkspace` and send `/skill docs-qa` or `/skill note-capture`.

There is no dotenv file and no budget JSON for ordinary use.

| Scheme | Purpose |
| --- | --- |
| **OtohaChat** | Default macOS app. No PCC entitlement request |
| **OtohaChat-iOS** | iOS / iPadOS, shared kit |
| **OtohaChat-PCC** | Same app with `OTOHACHAT_PCC` and the PCC entitlements file. This does not grant Apple authorization |

Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` for a personal `DEVELOPMENT_TEAM`. That file is gitignored. Do not commit certificates or profiles.

## SDK pin

- Package: https://github.com/OtohaCo/SwiftAgent
- Version: `1.0.0-rc.3`
- Revision: `d5383a26849f45d8a442c24aebfb0b7ca4798dd5`

The pin is `exact: "1.0.0-rc.3"` in `Package.swift` and is locked in `Package.resolved`. App sources do not vendor SDK files and do not modify RC3.

## Providers

| Kind | API | Notes |
| --- | --- | --- |
| Apple PCC | Foundation Models PCC | Default when available. Experimental in RC3 |
| Apple on-device | Foundation Models | macOS 26 / iOS 26 and later on capable hardware |
| OpenAI Responses | `/responses` | HTTPS. Effort omitted unless chosen |
| Anthropic | Messages | Catalog effort and thinking objects come from RC3 |
| DeepSeek Responses | `/responses` | Effort always sent; default high |
| Local Responses | Responses-compatible | Loopback HTTP allowed. Not Chat Completions |
| Compatible gateway | OpenAI Responses dialect | Including SUB2API-style `/responses` proxies |

TypeSafe / Jev decision providers are not listed as chat models.

## Tests

```sh
bash Scripts/gate.sh
```

`swift test` covers Keychain isolation (memory store), endpoints, catalog and reasoning mapping with a mock transport, conversation drain, tools, skills, and handoff warnings.

PCC live loop: `Tests/OtohaChatKitTests/PCCLiveLoopTests.swift` records `BLOCKED_CONFIGURATION` unless `OTOHACHAT_PCC_LIVE=1` and a granted entitlement are present.

## License

MIT. Adapted conversation controller and execution-report code comes from SwiftAgent Examples (MIT, ChainBow Co., Ltd.). See `NOTICE`.

OtohaChat is not affiliated with OpenAI, Anthropic, DeepSeek, xAI, or Apple Intelligence product brands. Those names appear only as configuration labels for the corresponding APIs.
