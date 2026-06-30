#!/usr/bin/env node
// Copies the canonical skill (skills/pr-review-handler/) into a package dir
// so each npm package ships the skill under skills/pr-review-handler/.
//
// Usage:
//   node scripts/sync-skill.mjs <package-dir>   # from repo root
//   node ../../scripts/sync-skill.mjs .          # from inside a package dir
//
// The target package gains <package-dir>/skills/pr-review-handler/{SKILL.md,agents/}.
// This keeps a single source of truth in skills/pr-review-handler/ while letting
// both packages (core + pi) publish the skill without manual copying.

import { cp, rm, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..");
const src = resolve(root, "skills", "pr-review-handler");

const arg = process.argv[2];
if (!arg) {
	console.error("Usage: node scripts/sync-skill.mjs <package-dir>");
	process.exit(1);
}

const pkgDir = resolve(process.cwd(), arg);
const dest = resolve(pkgDir, "skills", "pr-review-handler");

if (!existsSync(src)) {
	console.error(`Source skill not found: ${src}`);
	process.exit(1);
}

await rm(dest, { recursive: true, force: true });
await mkdir(resolve(dest, ".."), { recursive: true });
await cp(src, dest, { recursive: true });
console.log(`Synced skill → ${dest}`);
