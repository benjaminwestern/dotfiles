/**
 * Local Share Extension — Export sessions locally and open in browser
 *
 * Replicates the /share flow but stores exported HTML on disk instead of
 * uploading to a GitHub gist. The exported file is opened automatically in
 * the default browser.
 *
 * Usage:
 *   /lshare              — Export current session with auto-generated filename
 *   /lshare my-name      — Export current session as my-name.html
 *   /lshare-list         — Open the exported-sessions directory in Finder
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";
import { mkdirSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { homedir } from "node:os";

const EXPORT_DIR = join(homedir(), ".pi", "agent", "exported-sessions");

function openBrowser(fileUrl: string): void {
	const platform = process.platform;
	const cmd = platform === "darwin" ? "open" : platform === "win32" ? "cmd" : "xdg-open";
	const args = platform === "win32" ? ["/c", "start", "", fileUrl] : [fileUrl];
	spawn(cmd, args, { detached: true, stdio: "ignore" });
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("lshare", {
		description: "Export session to ~/.pi/agent/exported-sessions/ and open in browser",
		handler: async (args, ctx) => {
			const sessionFile = ctx.sessionManager.getSessionFile();
			if (!sessionFile) {
				ctx.ui.notify("Cannot export: no session file (ephemeral mode)", "error");
				return;
			}

			mkdirSync(EXPORT_DIR, { recursive: true });

			const sessionName = ctx.sessionManager.getSessionName() || "session";
			const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
			const baseName = args.trim() || `${sessionName}-${timestamp}`;
			const filename = `${baseName.replace(/\.html$/i, "")}.html`;
			const outputPath = join(EXPORT_DIR, filename);

			try {
				ctx.ui.notify("Exporting session...", "info");

				const piCliPath = process.argv[1];
				if (!piCliPath) {
					throw new Error("Cannot determine pi installation path");
				}
				const resolvedCliPath = realpathSync(piCliPath);
				const piDistDir = dirname(resolvedCliPath);
				const exportHtmlPath = join(piDistDir, "core", "export-html", "index.js");
				const exportHtmlUrl = pathToFileURL(exportHtmlPath).href;

				const { exportFromFile } = await import(exportHtmlUrl);
				await exportFromFile(sessionFile, outputPath);

				openBrowser(`file://${outputPath}`);
				ctx.ui.notify(`Opened ${filename}`, "success");
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`Export failed: ${message}`, "error");
			}
		},
	});

	pi.registerCommand("lshare-list", {
		description: "Open ~/.pi/agent/exported-sessions/ in the file manager",
		handler: async (_args, ctx) => {
			mkdirSync(EXPORT_DIR, { recursive: true });

			const platform = process.platform;
			const cmd = platform === "darwin" ? "open" : platform === "win32" ? "explorer" : "xdg-open";
			spawn(cmd, [EXPORT_DIR], { detached: true, stdio: "ignore" });

			ctx.ui.notify("Opened exported sessions directory", "success");
		},
	});
}
