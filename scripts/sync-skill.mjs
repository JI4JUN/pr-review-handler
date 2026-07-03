#!/usr/bin/env node
// Copies the canonical skill (skills/pr-review-handler/) into a package dir
// so each npm package ships the skill under skills/<skill-name>/.
//
// Usage:
//   node scripts/sync-skill.mjs <package-dir> [--name <skill-name>]
//
// Defaults to source skill name (`pr-review-handler`). Pass `--name` to publish
// the skill under a different name — the target directory and the `name:`
// frontmatter field in SKILL.md are both rewritten. This lets the Pi package
// ship as `pi-pr-review-handler` so it does not collide with a skills.sh
// install of `pr-review-handler` when both are present.
//
// The target package gains <package-dir>/skills/<skill-name>/{SKILL.md,agents/}.
// This keeps a single source of truth in skills/pr-review-handler/ while letting
// both packages (core + pi) publish the skill without manual copying.

import { cp, rm, mkdir, readFile, writeFile, readdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..");
const SOURCE_SKILL_NAME = "pr-review-handler";
const src = resolve(root, "skills", SOURCE_SKILL_NAME);

// Parse argv: first positional = package dir, optional --name <skill-name>
const args = process.argv.slice(2);
if (args.length === 0) {
	console.error(
		"Usage: node scripts/sync-skill.mjs <package-dir> [--name <skill-name>]",
	);
	process.exit(1);
}

let pkgDirArg = null;
let skillName = SOURCE_SKILL_NAME;
for (let i = 0; i < args.length; i++) {
	const a = args[i];
	if (a === "--name") {
		skillName = args[++i];
		if (!skillName) {
			console.error("--name requires a value");
			process.exit(1);
		}
	} else if (a.startsWith("--name=")) {
		skillName = a.slice("--name=".length);
	} else if (pkgDirArg === null) {
		pkgDirArg = a;
	} else {
		console.error(`Unexpected argument: ${a}`);
		process.exit(1);
	}
}

if (!pkgDirArg) {
	console.error(
		"Usage: node scripts/sync-skill.mjs <package-dir> [--name <skill-name>]",
	);
	process.exit(1);
}

const pkgDir = resolve(process.cwd(), pkgDirArg);
const skillsRoot = resolve(pkgDir, "skills");
const dest = resolve(skillsRoot, skillName);

if (!existsSync(src)) {
	console.error(`Source skill not found: ${src}`);
	process.exit(1);
}

// Clean any previously-synced skill directories under <pkg>/skills/ so stale
// dirs (e.g. an old name from a prior rename) do not ship in the package.
// These packages are dedicated skill packages — `skills/` contains only this
// one skill — so removing all subdirectories is safe.
if (existsSync(skillsRoot)) {
	const entries = await readdir(skillsRoot, { withFileTypes: true });
	for (const entry of entries) {
		if (entry.isDirectory()) {
			await rm(resolve(skillsRoot, entry.name), {
				recursive: true,
				force: true,
			});
			console.log(`Removed stale skill dir → ${entry.name}`);
		}
	}
}

await mkdir(skillsRoot, { recursive: true });
await cp(src, dest, { recursive: true });

// If publishing under a different name, rewrite the `name:` frontmatter field
// in the copied SKILL.md so it matches the target directory.
if (skillName !== SOURCE_SKILL_NAME) {
	const skillMdPath = resolve(dest, "SKILL.md");
	const original = await readFile(skillMdPath, "utf8");
	// Match the `name:` line in the frontmatter (top of file). Only the first
	// occurrence is rewritten; the source has exactly one such line.
	const nameLine = `name: ${SOURCE_SKILL_NAME}`;
	if (!original.includes(nameLine)) {
		console.error(
			`Could not find "${nameLine}" in ${skillMdPath}; refusing to rewrite.`,
		);
		process.exit(1);
	}
	const updated = original.replace(nameLine, `name: ${skillName}`);
	await writeFile(skillMdPath, updated, "utf8");
	console.log(`Rewrote skill name → ${skillName}`);
}

// Generate project agent templates for pi-subagents from the spec files.
// These are build artifacts (gitignored) — derived from agents/*-agent.md
// so there is a single source of truth. Phase 0 copies them into the
// target project's .agents/agents/pr-review-handler/ to register
// `pr-review-handler.triage` and `pr-review-handler.implementation`.
const agentsDir = resolve(dest, "agents");
const projectAgentsDir = resolve(agentsDir, "pr-review-handler");
await mkdir(projectAgentsDir, { recursive: true });

const triageSpec = await readFile(
	resolve(agentsDir, "triage-agent.md"),
	"utf8",
);
const implSpec = await readFile(
	resolve(agentsDir, "implementation-agent.md"),
	"utf8",
);

// Strip the leading "# Triage Agent" / "# Implementation Agent" title —
// project agents go straight to the system prompt body.
const stripTitle = (s) => s.replace(/^# .+\n+/, "");

const triageAgent = `---
name: triage
package: pr-review-handler
description: PR review triage specialist — read-only verdict classifier for review threads
systemPromptMode: replace
inheritProjectContext: true
inheritSkills: false
tools: read, bash, mcp:codegraph
defaultContext: fresh
---

${stripTitle(triageSpec)}`;

const implAgent = `---
name: implementation
package: pr-review-handler
description: PR review code fix specialist — applies minimal surgical fixes for one review thread
systemPromptMode: replace
inheritProjectContext: true
inheritSkills: false
tools: read, bash, edit, write, mcp:codegraph
defaultContext: fresh
---

${stripTitle(implSpec)}`;

await writeFile(resolve(projectAgentsDir, "triage.md"), triageAgent, "utf8");
await writeFile(
	resolve(projectAgentsDir, "implementation.md"),
	implAgent,
	"utf8",
);
console.log(`Generated project agent templates → agents/pr-review-handler/`);

console.log(`Synced skill → ${dest} (name: ${skillName})`);
