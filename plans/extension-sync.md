# Plan: Replace cp with Pi extension for project agent sync (v1.3.0)

## Context

### Problem

Current SKILL.md Phase 0 uses `cp -f` to sync project agent templates (`triage.md` + `implementation.md`) from the installed package to the target project's `.agents/pr-review-handler/`. This has four pain points:

1. **A — Relies on orchestrator execution**: `cp` is a bash command in SKILL.md, executed by the orchestrator (main agent). The model may skip Phase 0, execute cp out of order, or make errors. The sync is not deterministic.
2. **B — Overwrites user edits**: `cp -f` forcibly overwrites `.agents/pr-review-handler/*.md`. If a user manually edits these files, their changes are lost on next skill run.
3. **C — Sync timing wrong**: After upgrading the npm package, `.agents/` still holds old templates until the user runs the skill. Sync is coupled to skill execution, not to upgrade.
4. **D — All of the above** (confirmed by user).

### Root cause

`cp` is an orchestrator-executed bash command inside SKILL.md. It is unreliable (model-dependent), implicit (user doesn't control when), and coupled to skill runs (not upgrades).

### Solution

Delete the `cp` from SKILL.md Phase 0. Replace with a Pi extension that ships inside the pi package and registers a `/pi-pr-review-handler-sync` command. The user runs this command manually to sync project agents. This makes sync explicit, deterministic, and decoupled from skill execution.

## Approach

### Design decisions (confirmed via grill-me interview)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Trigger mechanism | `pi.registerCommand` — pure manual (user explicit) |
| 2 | Distribution | Bundled in pi package (`extensions/` convention dir, auto-loaded on `pi install`) |
| 3 | Sync logic | Full overwrite (project agents are generated artifacts; user shouldn't hand-edit) |
| 4 | SKILL.md Phase 0 | Check existence + notify + inline fallback (no auto-cp, no blocking) |
| 5 | Phase 0 check scope | Both `triage.md` AND `implementation.md` must exist |
| 6 | Other platforms | Unchanged — embed spec into task prompt (platform-agnostic, no file sync) |
| 7 | Stale path cleanup | Delete `.agents/agents/pr-review-handler/` (v1.2.3 old path); leave `.agents/agents/pr-review/` (user-managed) |
| 8 | Command name | `/pi-pr-review-handler-sync` (matches pi package name `pi-pr-review-handler`) |
| 9 | Extension source location | `packages/pi/extensions/sync-agents.ts` (pi-specific, not synced via sync-skill.mjs) |
| 10 | README docs | packages/pi/README.md detailed + root README.md brief mention; core README unchanged |
| 11 | sync-skill.mjs | Unchanged — still generates project agent templates to `packages/pi/skills/pi-pr-review-handler/agents/pr-review-handler/`; extension reads this path at runtime |
| 12 | Version | v1.3.0 (minor — new feature + Phase 0 mechanism change, non-breaking) |

## Files to modify

| File | Change |
|------|--------|
| `packages/pi/extensions/sync-agents.ts` | **NEW** — Pi extension registering `/pi-pr-review-handler-sync` command |
| `skills/pr-review-handler/SKILL.md` | Phase 0: delete `cp -f` block, add existence check + notify + inline fallback |
| `packages/pi/README.md` | Add "Syncing project agents" section (command usage, upgrade flow, stale path cleanup) |
| `README.md` | Brief mention: Pi users run `/pi-pr-review-handler-sync` |
| `packages/core/package.json` | Version → 1.3.0 |
| `packages/pi/package.json` | Version → 1.3.0 |

## Reuse

- **`sync-skill.mjs`** — unchanged. Still syncs skill source → `packages/pi/skills/pi-pr-review-handler/`. The extension reads project agent templates from this synced path at runtime.
- **`skills/pr-review-handler/agents/{triage,implementation}-agent.md`** — single source of truth for agent specs. sync-skill.mjs generates `packages/pi/skills/pi-pr-review-handler/agents/pr-review-handler/{triage,implementation}.md` from these. Extension copies from there to target project `.agents/`.
- **pi extension convention** — `packages/pi/extensions/*.ts` auto-loaded by `pi install` (per `docs/packages.md` "Convention Directories").

## Steps

- [ ] **Step 1**: Create `packages/pi/extensions/sync-agents.ts`
  - `pi.registerCommand("pi-pr-review-handler-sync", { handler })`
  - Handler logic:
    1. Locate package root via `import.meta.url` (`__dirname` → `path.resolve(__dirname, "..")`)
    2. Source dir: `<pkg>/skills/pi-pr-review-handler/agents/pr-review-handler/`
    3. Dest dir: `<cwd>/.agents/pr-review-handler/`
    4. Stale dir: `<cwd>/.agents/agents/pr-review-handler/`
    5. Check source files exist (`triage.md` + `implementation.md`); if missing → `ctx.ui.notify("Source not found: ...", "error")` + return
    6. `rm -rf` stale dir if exists (no prompt — user triggered = informed)
    7. `mkdir -p` dest dir
    8. `copyFileSync` both files (full overwrite)
    9. `ctx.ui.notify("Synced triage.md + implementation.md → .agents/pr-review-handler/", "info")`
  - Do NOT touch `.agents/agents/pr-review/`

- [ ] **Step 2**: Edit `skills/pr-review-handler/SKILL.md` Phase 0
  - Delete the `mkdir -p` + `cp -f` block (current lines ~153-155)
  - Replace with existence check:

    ```
    ### Ensure project agents registered (Pi only)

    Check that both project agent files exist:

    ```bash
    test -f .agents/pr-review-handler/triage.md && test -f .agents/pr-review-handler/implementation.md
    ```

    - **Both exist** → continue to Phase 1 (subagent dispatch)
    - **Either missing** → notify user: "Project agents not found at `.agents/pr-review-handler/`. Run `/pi-pr-review-handler-sync` to sync them. Continuing inline for this run." → fall back to inline execution (read `agents/triage-agent.md` spec and execute inline)

    Do NOT auto-cp or auto-sync. Syncing is the user's responsibility via the `/pi-pr-review-handler-sync` command.

    ```

- [ ] **Step 3**: Edit `packages/pi/README.md`

  - Add "Syncing project agents" section (after install section):

    ```
    ### Syncing project agents

    Project agents (`.agents/pr-review-handler/{triage,implementation}.md`) are generated artifacts synced from this package. Use the `/pi-pr-review-handler-sync` command to sync:

    - **First run**: creates `.agents/pr-review-handler/` with latest templates
    - **After upgrade**: overwrites with latest templates (also cleans stale `.agents/agents/pr-review-handler/` from v1.2.3)
    - **Does NOT touch** `.agents/agents/pr-review/` (manual, if present)

    The command is a Pi extension bundled with this package — `pi install` auto-loads it. No SKILL.md auto-cp; syncing is explicit and user-triggered.
    ```

- [ ] **Step 4**: Edit `README.md`
  - Add brief note in the "Install as a Pi package" section:

    ```
    > **Pi users**: Run `/pi-pr-review-handler-sync` to sync project agents after install or upgrade. See [packages/pi/README.md](packages/pi/README.md) for details.
    ```

- [ ] **Step 5**: Bump version
  - `packages/core/package.json` → `"version": "1.3.0"`
  - `packages/pi/package.json` → `"version": "1.3.0"`

- [ ] **Step 6**: Sync + publish
  - `npm run sync:core && npm run sync:pi`
  - Verify `packages/pi/extensions/sync-agents.ts` is NOT synced to core (pi-specific)
  - `git add` + `git commit -m "feat: pi extension for project agent sync, remove cp (v1.3.0)"`
  - `git tag core-v1.3.0 && git tag pi-v1.3.0`
  - `git push origin main && git push origin core-v1.3.0 pi-v1.3.0`
  - Wait for CI publish ✅
  - `pi install npm:@trashcodermaker/pi-pr-review-handler`

## Verification

### Extension loads

- [ ] `pi install` succeeds, no errors
- [ ] Start pi session in target project, type `/pi-pr-review-handler-sync` — command appears in autocomplete

### Sync command works

- [ ] In a clean project (no `.agents/`): run `/pi-pr-review-handler-sync`
  - `.agents/pr-review-handler/triage.md` created
  - `.agents/pr-review-handler/implementation.md` created
  - Content matches package templates
  - Notification: "Synced triage.md + implementation.md → .agents/pr-review-handler/"
- [ ] With stale `.agents/agents/pr-review-handler/` present: run command
  - `.agents/agents/pr-review-handler/` deleted
  - `.agents/pr-review-handler/` created/overwritten
- [ ] With `.agents/agents/pr-review/` present: run command
  - `.agents/agents/pr-review/` unchanged
- [ ] Run command twice: second run overwrites without error (idempotent)

### SKILL.md Phase 0 fallback

- [ ] In a project WITHOUT `.agents/pr-review-handler/`: trigger skill
  - Phase 0 detects missing agents, notifies user, continues inline (no subagent dispatch)
- [ ] In a project WITH `.agents/pr-review-handler/{triage,implementation}.md`: trigger skill
  - Phase 0 passes check, dispatches subagents normally
- [ ] In a project with only `triage.md` (missing `implementation.md`): trigger skill
  - Phase 0 detects missing file, notifies, inline fallback

### End-to-end PR review

- [ ] Run `/pi-pr-review-handler-sync` in target project
- [ ] Trigger skill on a real PR
- [ ] Phase 0 check passes, Phase 1 dispatches `pr-review-handler.triage` subagent
- [ ] Phase 2 dispatches `pr-review-handler.implementation` subagent
- [ ] No `cp` commands in orchestrator output
