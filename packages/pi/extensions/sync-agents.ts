import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const AGENT_FILES = ["triage.md", "implementation.md"] as const;

export default function (pi: ExtensionAPI) {
  pi.registerCommand("pi-pr-review-handler-sync", {
    description: "Sync pr-review-handler project agents to .agents/pr-review-handler/",
    handler: async (_args, ctx) => {
      const pkgRoot = path.resolve(__dirname, "..");
      const srcDir = path.join(
        pkgRoot,
        "skills",
        "pi-pr-review-handler",
        "agents",
        "pr-review-handler",
      );
      const cwd = process.cwd();
      const destDir = path.join(cwd, ".agents", "pr-review-handler");
      const staleDir = path.join(cwd, ".agents", "agents", "pr-review-handler");

      // Check source files exist
      for (const f of AGENT_FILES) {
        const src = path.join(srcDir, f);
        if (!fs.existsSync(src)) {
          ctx.ui.notify(`Source not found: ${src}`, "error");
          return;
        }
      }

      // Clean stale path (v1.2.3 old layout)
      if (fs.existsSync(staleDir)) {
        fs.rmSync(staleDir, { recursive: true, force: true });
      }

      // Sync (full overwrite)
      fs.mkdirSync(destDir, { recursive: true });
      for (const f of AGENT_FILES) {
        fs.copyFileSync(path.join(srcDir, f), path.join(destDir, f));
      }

      ctx.ui.notify(
        `Synced ${AGENT_FILES.join(" + ")} → .agents/pr-review-handler/`,
        "info",
      );
    },
  });
}
