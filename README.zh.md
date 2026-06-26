# PR Review Handler

> 系统地处理 GitHub PR review 评论：判断有效性、修复代码、发布回复。

[![Build Status](https://img.shields.io/github/actions/workflow/status/JI4JUN/pr-review-handler/ci.yml?style=flat-square&label=Build)](https://github.com/JI4JUN/pr-review-handler/actions)
[![npm version](https://img.shields.io/npm/v/@trashcodermaker/pi-pr-review-handler?style=flat-square)](https://www.npmjs.com/package/@trashcodermaker/pi-pr-review-handler)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)

⭐ 如果这个项目对你有帮助，欢迎在 GitHub 上点个 star！

[项目简介](#项目简介) • [快速开始](#快速开始) • [工作原理](#工作原理) • [使用方法](#使用方法) • [环境要求](#环境要求) • [支持的平台](#支持的平台)

[English version](./README.md)

## 项目简介

Code Review 是健康 PR 流程的一部分，但把 review 评论转化为实际修复和得体温回复往往既繁琐又容易出错。

**PR Review Handler** 用自动化流程解决这个问题。它会抓取 GitHub PR 中未关闭的 review 线程，逐条判断评论是否成立，对有效问题做最小化代码修复，生成与评论者语言、语气一致的回复，并在确认后推送变更、请求 re-review。

它可以作为 npm 包、Pi 包、Pi skill，或嵌入到其他 agent 环境使用。项目在 `agents/` 中提供 agent 规格，因此不同平台可以用自己的任务/调度机制运行同一套流水线。

## 快速开始

### 作为 npm 包安装

```bash
npm install @trashcodermaker/pi-pr-review-handler
```

### 作为 Pi 包安装

```bash
pi install @trashcodermaker/pi-pr-review-handler
```

### 通过 skill.sh 安装

```bash
npx skills add JI4JUN/pr-review-handler
```

### 从源码安装

```bash
git clone https://github.com/JI4JUN/pr-review-handler.git
cd pr-review-handler
npm install
```

> [!IMPORTANT]
> 使用本 skill 或包之前，请确保已安装并登录 GitHub CLI（`gh`）。读取 PR 数据、发布回复等核心操作都依赖它。

## 工作原理

整个流程由多个阶段组成，每个阶段职责清晰；在需要人工确认的位置会设置 checkpoint 暂停执行。

```
Phase 0: Setup
Phase 1: Triage        ← 并行，只读
Phase 2: Fix           ← 串行，最小修改
Phase 3: Reply         ← 由编排器直接起草
Phase 4: Post & Push
Phase 5: Report
```

### Phase 0: Setup

根据当前分支或显式 PR 链接定位目标 PR，抓取未关闭的 review 线程，并补充抓取 review 级别的整体反馈。本阶段只做数据准备，不修改代码。

### Phase 1: Triage

读取评论所指代码和完整 review 线程后，逐条将评论分类为：

- `valid-fix` — 存在真实问题，需要代码修改
- `valid-nofix` — 问题成立，但不需要改代码
- `invalid` — 前提不适用于当前代码，或建议的修复反而有害

如果线程很多且平台支持并行 agent，Triage 会并行执行以提高速度。

> [!TIP]
> Triage 默认偏保守。如果某条评论含义不清，可直接标记为 `invalid`，原因写 `unclear — needs human review`。

### Phase 2: Fix

对每条 `valid-fix` 线程，由专门的 implementation agent 施加满足 review 要求的最小改动。修改前先追踪引用关系；如果改动影响函数签名、类型或导出，会同步更新调用方和测试；不顺手做无关的重构或清理。

本阶段所有修复都会提交到本地，但 **不会推送**。

全部修复完成后会执行：

```bash
npx tsc --noEmit
```

如果类型检查失败，流程会自动定位引入错误的提交，回滚、修复后重新提交，再继续后续阶段。

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

如果你希望手动控制流程，也可以直接基于 GitHub CLI 命令执行。本 skill 和包的主要价值，是把这些命令封装成 agent 可理解、可执行的结构化流水线。

## 环境要求

- 已安装并登录 GitHub CLI（`gh`）
- Git 工作区足够干净，可以创建 review-fix 提交
- 若想执行最后的 `tsc --noEmit` 检查，项目应为 Node.js / TypeScript 项目

## 支持的平台

| 平台 | 支持情况 |
| --- | --- |
| npm / Node.js | ✅ 可作为已发布包安装 |
| Pi | ✅ 支持作为 package 和 skill 使用 |
| Claude Code | ✅ 通过 Task 机制分发 agent |
| Cursor | ✅ 通过 background agent 分发 |
| 其他 agent 客户端 | ✅ 使用 `agents/` 中的 agent 规格，以内联方式运行 |

## 备注

- 项目在 `agents/` 中提供可复用的 agent 规格。
- 若平台支持并行 agent，Triage 可并行执行；否则以内联方式运行。
- 流程中有两处会暂停等待确认：一次在 Triage 结论出来后，一次在发布回复前。
- 推送仅在回复确认后执行一次。
- Fix 阶段默认串行执行，以避免并发修改带来的冲突。
