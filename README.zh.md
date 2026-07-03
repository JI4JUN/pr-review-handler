# PR Review Handler

> 系统地处理 GitHub PR review 评论：判断有效性、修复代码、发布回复。

📦 **仓库地址**: <https://github.com/JI4JUN/pr-review-handler>

[![Build Status](https://img.shields.io/github/actions/workflow/status/JI4JUN/pr-review-handler/publish.yml?style=flat-square&label=Build)](https://github.com/JI4JUN/pr-review-handler/actions)
[![npm version](https://img.shields.io/npm/v/@trashcodermaker/pr-review-handler?style=flat-square&label=%40trashcodermaker%2Fpr-review-handler)](https://www.npmjs.com/package/@trashcodermaker/pr-review-handler)
[![npm version](https://img.shields.io/npm/v/@trashcodermaker/pi-pr-review-handler?style=flat-square&label=%40trashcodermaker%2Fpi-pr-review-handler)](https://www.npmjs.com/package/@trashcodermaker/pi-pr-review-handler)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)

⭐ 如果这个项目对你有帮助，欢迎在 [GitHub](https://github.com/JI4JUN/pr-review-handler) 上点个 star！

[项目简介](#项目简介) • [包](#包) • [快速开始](#快速开始) • [工作原理](#工作原理) • [仓库结构](#仓库结构) • [环境要求](#环境要求) • [支持的平台](#支持的平台)

[English version](./README.md)

## 项目简介

Code Review 是健康 PR 流程的一部分，但把 review 评论转化为实际修复和得体温回复往往既繁琐又容易出错。

**PR Review Handler** 用自动化流程解决这个问题。它会抓取 GitHub PR 中未关闭的 review 线程，逐条判断评论是否成立，对有效问题做最小化代码修复，生成与评论者语言、语气一致的回复，并在确认后推送变更、请求 re-review。

本 skill 与具体 agent 无关：在 `agents/` 中提供 agent 规格，可运行于任何支持子任务的 agent 框架（Pi、Claude Code、Cursor、Gemini CLI、OpenCode 等），也可在内联模式下回退执行。

## 包

本仓库是 monorepo，从单一真实来源（`skills/pr-review-handler/`）发布两个 npm
包。两者 skill 内容完全一致，仅在发布的 skill 名称和 npm 关键字上不同，便于各自的用户群体找到合适的包。

| 包 | npm 名称 | Skill 名称 | 安装命令 | 适用人群 |
| --- | --- | --- | --- | --- |
| Core | `@trashcodermaker/pr-review-handler` | `pr-review-handler` | `npm install @trashcodermaker/pr-review-handler` | 任意 agent 框架 |
| Pi | `@trashcodermaker/pi-pr-review-handler` | `pi-pr-review-handler` | `pi install npm:@trashcodermaker/pi-pr-review-handler` | Pi 用户 |

除非你通过 Pi 安装 skill，否则请使用 **Core** 包。**Pi** 包的存在是为了让 Pi
用户能通过 `pi install` 和 Pi 包画廊（`pi-package` 关键字）发现并安装。

> [!NOTE]
> Pi 包以 **`pi-pr-review-handler`** 作为 skill 名称发布（而非
> `pr-review-handler`），这样在同一项目里同时存在 `skills.sh` / `npx skills add`
> 安装的 Core skill 时不会发生名称冲突。调用方式为 `/skill:pi-pr-review-handler`。

## 快速开始

### 作为 npm 包安装（任意 agent）

```bash
npm install @trashcodermaker/pr-review-handler
```

### 作为 Pi 包安装

```bash
pi install npm:@trashcodermaker/pi-pr-review-handler
```

该 skill 注册为 **`pi-pr-review-handler`**（调用方式
`/skill:pi-pr-review-handler`）。这与 Core / `skills.sh` 的 skill 名称
（`pr-review-handler`）不同，两者可在同一环境中并存，不会发生 Pi skill
名称冲突。

> [!IMPORTANT]
> **从 ≤ 1.1.3 升级？** 旧版本在本包内以 `pr-review-handler/` 目录发布 skill。
> npm 不一定会删除旧版本中存在但新版本中已不存在的文件，因此升级后可能残留
> `skills/pr-review-handler/` 目录，从而再次引发名称冲突。升级后若存在该目录，请手动删除：
>
> ```bash
> rm -rf ~/.pi/agent/npm/node_modules/@trashcodermaker/pi-pr-review-handler/skills/pr-review-handler
> ```
>
> 或直接卸载后重装：
>
> ```bash
> pi uninstall @trashcodermaker/pi-pr-review-handler
> pi install npm:@trashcodermaker/pi-pr-review-handler
> ```

### 通过 skills CLI 安装（任意 agent 框架）

```bash
npx skills add JI4JUN/pr-review-handler --skill pr-review-handler
```

该命令会克隆仓库并把 skill（含 `agents/` 规格）复制到你的 agent skills 目录。

### 从源码安装

```bash
git clone https://github.com/JI4JUN/pr-review-handler.git
cd pr-review-handler
npm install
```

> [!IMPORTANT]
> 使用本 skill 之前，请确保已安装并登录 GitHub CLI（`gh`）。读取 PR 数据、发布回复等核心操作都依赖它。

## 工作原理

整个流程由多个阶段组成，每个阶段职责清晰；在需要人工确认的位置会设置
checkpoint 暂停执行。

```
Phase 0: Setup
Phase 1: Triage        ← 并行，只读
Phase 2: Fix           ← 串行，最小修改
Phase 3: Reply         ← 由编排器直接起草
Phase 4: Post & Push
Phase 5: Report
```

### Phase 0: Setup

根据当前分支或显式 PR 链接定位目标 PR，抓取未关闭的 review 线程，并补充抓取
review 级别的整体反馈。本阶段只做数据准备，不修改代码。

### Phase 1: Triage

读取评论所指代码和完整 review 线程后，逐条将评论分类为：

- `valid-fix` — 存在真实问题，需要代码修改
- `valid-nofix` — 问题成立，但不需要改代码
- `invalid` — 前提不适用于当前代码，或建议的修复反而有害

在 Pi 且装有 pi-subagents 时，Triage 通过 `pr-review-handler.triage` project agent 并行执行；其他平台用各自子任务机制；无子任务机制则内联。

> [!TIP]
> Triage 默认偏保守。如果某条评论含义不清，可直接标记为 `invalid`，原因写
> `unclear — needs human review`。

### Phase 2: Fix

对每条 `valid-fix` 线程，由专门的 implementation agent 施加满足 review 要求的
最小改动。修改前先追踪引用关系；如果改动影响函数签名、类型或导出，会同步更新
调用方和测试；不顺手做无关的重构或清理。

本阶段所有修复都会提交到本地，但 **不会推送**。

全部修复完成后，流程会运行项目的类型检查或等效验证（自动检测：TypeScript 用 `tsc`、Python 用 `ruff`/`mypy`、Go 用 `go build`、Rust 用 `cargo check` 等）。如果验证失败，流程会自动定位引入错误的提交，回滚、修复后重新提交，再继续后续阶段。

### Phase 3: Reply

编排器基于以下信息逐条起草回复：

- 原始线程数据
- Triage 结论
- 实际变更：`git diff origin/{branch}...HEAD`
- Phase 2 中的失败记录

回复会尽量匹配评论者的语言和语气，保持简洁，避免防御性措辞。

### Phase 4: Post & Push

将用户确认后的回复发布到 GitHub，并把本地的 review-fix 提交统一推送。

可选地，流程还可以：

- 向原 reviewer 请求 re-review
- 将已处理的 review 线程标记为“Addressed”并关闭

### Phase 5: Report

最后输出简要总结：

```
✅ Triage: N/N 条线程已处理
✅ Fixes: M/K 条 valid-fix 已应用（本地提交并推送）
   ❌ Failed: {thread} — {reason}
✅ Replies: P/P 条回复已起草并发布
```

## 仓库结构

```
pr-review-handler/
├── skills/
│   └── pr-review-handler/      # 规范 skill（单一真实来源）
│       ├── SKILL.md
│       └── agents/             # triage + implementation agent 规格
├── packages/
│   ├── core/                   # → npm: @trashcodermaker/pr-review-handler
│   └── pi/                     # → npm: @trashcodermaker/pi-pr-review-handler
├── scripts/
│   └── sync-skill.mjs          # 发布前把 skill 复制到各包
├── package.json                # workspaces 根
└── .github/workflows/publish.yml
```

两个包都从 `packages/<name>/` 发布。`prepublishOnly` 脚本会运行
`sync-skill.mjs`，在 npm 打包前把 `skills/pr-review-handler/` 复制进包目录，
因此 skill 内容在源码中不会重复维护。

### 发布

发布由 tag 驱动（也可用 `workflow_dispatch`）：

- `core-v1.1.0` → 发布 `packages/core`
- `pi-v1.1.0` → 发布 `packages/pi`

本地发布：

```bash
npm run publish:core    # 或 npm run publish:pi
```

## 使用方法

### 在 agent 中调用

安装为 skill 后，直接用自然语言发起请求即可。常见触发方式包括：

- "帮我处理这个 PR 的 review：<https://github.com/owner/repo/pull/123>"
- "回复 reviewer 的评论"
- "看看 PR 里那些 unresolved threads"
- "review 提的问题要修一下"
- "CI 过了，但 review 还没回"
- "someone left comments on my PR"
- "帮我看看那些人提的意见"

### 命令行手动驱动

如果你希望手动控制流程，也可以直接基于 GitHub CLI 命令执行。本 skill 和包的
主要价值，是把这些命令封装成 agent 可理解、可执行的结构化流水线。

## 环境要求

- 已安装并登录 GitHub CLI（`gh`）
- Git 工作区足够干净，可以创建 review-fix 提交
- 项目需有类型检查器或 linter（TypeScript、Python、Go、Rust 等）用于修复后验证 — 自动检测，无则跳过

## 支持的平台

| 平台 | 支持情况 |
| --- | --- |
| npm / Node.js | ✅ 安装 `@trashcodermaker/pr-review-handler` 已发布包 |
| Pi | ✅ 通过 `pi install` 安装 `@trashcodermaker/pi-pr-review-handler`。如需子任务分发（每个线程独立上下文），安装 [`pi-subagents`](https://github.com/nicobailon/pi-subagents) 扩展（`pi install npm:pi-subagents`）；否则 skill 内联运行。 |
| Claude Code | ✅ Task 机制分发，或 `npx skills add` |
| Cursor | ✅ background agent 分发 |
| Gemini CLI / OpenCode / 其他 | ✅ 原生子任务机制，或内联回退 |
| skills CLI | ✅ `npx skills add JI4JUN/pr-review-handler --skill pr-review-handler` |

## 推荐配套工具

### CodeGraph（可选，增强 triage 与 implementation）

Triage 和 Implementation project agent 的工具列表引用了 `mcp:codegraph`。[CodeGraph](https://github.com/colbymchenry/codegraph) 是语义代码图谱 MCP server — 提供符号查找、调用边遍历、爆炸半径分析，能力超越 `grep`（能处理动态分发、多态等）。

**为什么需要**：triage 时，CodeGraph 帮 agent 精确找到符号的所有调用方（补全 `affected_files`）；implementation 时，能追踪 grep 可能遗漏的引用。

**安装**：见 [CodeGraph repo](https://github.com/colbymchenry/codegraph)。安装 CLI 后（`curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh`），运行 `codegraph install` 接入你的 agent，然后在每个项目运行 `codegraph init`。

**Pi 用户**：CodeGraph 的 `install` 命令自动配置 Claude Code、Cursor、Codex 等，但不支持 Pi。需手动在 Pi 的 MCP 配置中添加 CodeGraph MCP server。若未安装 CodeGraph，agent 回退到 `grep`/`find` — skill 仍可用，只是引用发现精度降低。

## 备注

- 项目在 `agents/` 中提供可复用的 agent 规格。
- 在 Pi 且装有 pi-subagents 时，Triage 通过 `pr-review-handler.triage` project agent 并行执行；其他平台用各自子任务机制；无则内联。
- 流程中有两处会暂停等待确认：一次在 Triage 结论出来后，一次在发布回复前。
- 推送仅在回复确认后执行一次。
- Fix 阶段默认串行执行，以避免并发修改带来的冲突。
