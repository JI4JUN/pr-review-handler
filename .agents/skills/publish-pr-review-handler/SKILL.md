---
name: publish-pr-review-handler
description: 'Publish a new version of the pr-review-handler monorepo packages. Use whenever the skill content in skills/pr-review-handler/ has changed and needs to be released to npm, or when releasing a new version of either @trashcodermaker/pr-review-handler (core) or @trashcodermaker/pi-pr-review-handler (pi). Triggers: "发版", "发布新版本", "publish packages", "release a new version", "bump and publish", "打 tag 发布", or any mention of cutting a release for this repo''s npm packages.'
---

# Publish pr-review-handler

Release a new version of the two npm packages in this monorepo. Both packages
ship identical content from `skills/pr-review-handler/` (the single source of
truth) and are published in lockstep via tag-driven GitHub Actions.

## When to Use

Use after editing skill content under `skills/pr-review-handler/` when you want
to release a new version to npm. Also use when asked to "发版", "publish",
"release", or "bump version" for this repo.

Do NOT use for edits to package-only files (READMEs, workflow) that don't
affect published skill content — those can go out without a version bump if
desired, though bumping is harmless.

## Procedure

1. **Decide the new version** `X.Y.Z`. Conventions:
   - bug fix / doc tweak = patch (`Z++`)
   - new agent spec, new phase, or minor feature = minor (`Y++`)
   - breaking change to skill contract = major (`X++`)

   Both packages MUST share the same version unless a package-exclusive change
   applies (rare).

2. **Edit `packages/core/package.json`** and set `"version": "X.Y.Z"`.

3. **Edit `packages/pi/package.json`** and set `"version": "X.Y.Z"` (same value).

4. **(Optional) Sanity-check the tarball.** The `prepublishOnly` script runs
   sync automatically in CI, so this is local reassurance only:

   ```bash
   npm run sync
   npm pack --workspace packages/core --dry-run
   npm pack --workspace packages/pi --dry-run
   ```

   Confirm both tarballs contain
   `skills/pr-review-handler/{SKILL.md,agents/}`.

5. **Commit the version bump:**

   ```bash
   git add -A
   git commit -m "chore: release vX.Y.Z"
   ```

   Use a more descriptive message if the release includes real changes.

6. **Create both tags.** Tag name format `<pkg>-vX.Y.Z` is required — the
   publish workflow routes by this prefix:

   ```bash
   git tag core-vX.Y.Z
   git tag pi-vX.Y.Z
   ```

7. **Push everything.** Pushing the tags triggers the publish workflow:

   ```bash
   git push origin main core-vX.Y.Z pi-vX.Y.Z
   ```

8. **Watch the CI:**

   ```bash
   gh run list --workflow=publish.yml --limit 4
   ```

   Each tag triggers one run; both should reach `[ok]`. Confirm npm accepted
   the publish:

   ```bash
   gh run view <id> --log | grep '+ @trashcodermaker'
   ```

   You should see `+ @trashcodermaker/pr-review-handler@X.Y.Z` (core run) and
   `+ @trashcodermaker/pi-pr-review-handler@X.Y.Z` (pi run).

9. **Verify on npm:**

   ```bash
   npm view @trashcodermaker/pr-review-handler version
   npm view @trashcodermaker/pi-pr-review-handler version
   ```

   Both must print `X.Y.Z`. See Pitfalls for the propagation-delay caveat.

10. **(Optional) Install-test** in a throwaway dir:

    ```bash
    npm install @trashcodermaker/pr-review-handler@X.Y.Z
    ls node_modules/@trashcodermaker/pr-review-handler/skills/pr-review-handler/agents/
    ```

## Pitfalls

- **Local `npm publish` won't work.** This machine is not logged into npm
  (`npm whoami` returns E401). The `NPM_TOKEN` lives only in GitHub Actions
  secrets. ALL publishes go through the tag-push → CI flow. Do not attempt
  `npm publish` locally.

- **npm scope is `@trashcodermaker`** (trash-CODER-maker, with an 'r'). Writing
  `@trashcodemaker` (no 'r') publishes to a different/nonexistent scope —
  silent failure or 403. Always copy the name from an existing package.json.

- **The `NPM_TOKEN` is scope-restricted to `@trashcodermaker`.** Unscoped
  package names (e.g. bare `pr-review-handler`) will fail with 403 Forbidden.
  Both packages MUST use the `@trashcodermaker/` scope.

- **Tag names must match `core-v*` or `pi-v*` exactly.** The workflow's resolve
  step case-matches on these prefixes; a bare `v1.2.3` tag routes to
  `pkgs=both` and tries to publish both packages, which is usually not what
  you want for a single-package fix.

- **Do NOT place SKILL.md at the repo root.** skills CLI
  (`npx skills add JI4JUN/pr-review-handler`) treats a root SKILL.md as a
  single-file skill and silently drops `agents/`. The canonical skill lives at
  `skills/pr-review-handler/SKILL.md`; the sync script copies it into each
  package at publish time.

- **npm metadata propagation delay.** After CI shows success, `npm view` may
  still E404 for several minutes. The tarball endpoint
  (`/.../-/...-X.Y.Z.tgz`) responds 200 immediately. Wait and retry; do NOT
  republish the same version (npm rejects re-publishing existing versions).

- **Both packages ship identical content** from `skills/pr-review-handler/`.
  Bump versions in lockstep. The only valid reason to diverge is a
  package-exclusive change (e.g. adding Pi runtime agents to the pi package
  only) — which has not happened yet.

- **`packages/*/skills/` directories are gitignored** and generated by
  `scripts/sync-skill.mjs`. Never edit files inside them directly — edit
  `skills/pr-review-handler/` and re-run sync.

## Verification

1. `gh run list --workflow=publish.yml --limit 2` shows both tag-triggered
   runs as `[ok]`.
2. `gh run view <latest-id> --log | grep '+ @trashcodermaker'` prints
   `+ @trashcodermaker/pr-review-handler@X.Y.Z` (and the pi line for the pi
   run).
3. `npm view @trashcodermaker/pr-review-handler version` prints `X.Y.Z`
   (retry if E404 within first 5 minutes).
4. `npm view @trashcodermaker/pi-pr-review-handler version` prints `X.Y.Z`.
5. GitHub Releases page shows `core-vX.Y.Z` and `pi-vX.Y.Z` (auto-created by
   the workflow).
