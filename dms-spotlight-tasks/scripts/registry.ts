#!/usr/bin/env bun
// Generates the plugin registry entry (registry/<owner>-<repo>.json) from plugin.json.
//
//   bun scripts/registry.ts            # (re)write the registry file
//   bun scripts/registry.ts --check    # exit 1 when the registry file is missing or out of date
//
// Fields the registry needs but plugin.json does not have (compositors, distro) come from an
// optional "registry" block in plugin.json; both default to ["any"]. The repo URL comes from the
// git "origin" remote, falling back to https://github.com/AleBles/<directory name>.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, join, relative } from "node:path";
import { spawnSync } from "node:child_process";

const root = process.cwd();
const check = process.argv.includes("--check");

type Manifest = {
    id: string;
    name: string;
    description: string;
    author: string;
    capabilities?: string[];
    category?: string;
    dependencies?: string[];
    requires_dms?: string;
    registry?: { compositors?: string[]; distro?: string[]; screenshot?: string; repo?: string };
};

const manifest: Manifest = JSON.parse(readFileSync(join(root, "plugin.json"), "utf8"));

function repoFromGit(): string | null {
    const res = spawnSync("git", ["remote", "get-url", "origin"], { cwd: root, encoding: "utf8" });
    if (res.status !== 0) return null;
    const url = res.stdout.trim();
    const m = url.match(/github\.com[:/]([^/]+)\/([^/]+?)(?:\.git)?$/);
    return m ? `https://github.com/${m[1]}/${m[2]}` : null;
}

function defaultBranch(): string {
    const res = spawnSync("git", ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], { cwd: root, encoding: "utf8" });
    if (res.status === 0) return res.stdout.trim().replace(/^origin\//, "");
    return "main";
}

// In a monorepo the plugin sits in a subdirectory of the repository: the registry entry then needs
// that subdirectory as "path", and both the entry filename and the screenshot URL follow the plugin
// directory rather than the repository name. Standalone repos keep the old behaviour (subPath "").
function repoRoot(): string | null {
    const res = spawnSync("git", ["rev-parse", "--show-toplevel"], { cwd: root, encoding: "utf8" });
    return res.status === 0 ? res.stdout.trim() : null;
}

const top = repoRoot();
const subPath = top && top !== root ? relative(top, root) : "";
const repo = manifest.registry?.repo ?? repoFromGit() ?? `https://github.com/AleBles/${basename(top ?? root)}`;
const [, owner, repoName] = repo.match(/github\.com\/([^/]+)\/([^/]+)$/) ?? [];
if (!owner || !repoName) {
    console.error(`Cannot derive owner/repo from ${repo}`);
    process.exit(1);
}

const entry = {
    id: manifest.id,
    name: manifest.name,
    capabilities: manifest.capabilities ?? [],
    category: manifest.category ?? "utilities",
    repo,
    ...(subPath ? { path: subPath } : {}),
    author: manifest.author,
    description: manifest.description,
    dependencies: manifest.dependencies ?? [],
    compositors: manifest.registry?.compositors ?? ["any"],
    distro: manifest.registry?.distro ?? ["any"],
    screenshot: manifest.registry?.screenshot
        ?? `https://raw.githubusercontent.com/${owner}/${repoName}/${defaultBranch()}/${subPath ? `${subPath}/` : ""}assets/screenshot.png`,
    ...(manifest.requires_dms ? { requires_dms: manifest.requires_dms } : {})
};

// Keep short arrays on one line, like the hand-written registry entries.
const json = JSON.stringify(entry, null, 2).replace(/\[\s+((?:"[^"]*",?\s+)*)\]/g, (_, items: string) =>
    `[${items.trim().split(/,\s+/).join(", ")}]`) + "\n";

const entryName = subPath ? basename(root) : repoName;
const outFile = join(root, "registry", `${owner.toLowerCase()}-${entryName.toLowerCase()}.json`);

if (check) {
    const current = existsSync(outFile) ? readFileSync(outFile, "utf8") : null;
    if (current === json) {
        console.log(`up to date: ${outFile}`);
        process.exit(0);
    }
    console.error(current === null ? `missing: ${outFile}` : `out of date: ${outFile}`);
    console.error("run: bun scripts/registry.ts");
    process.exit(1);
}

mkdirSync(join(root, "registry"), { recursive: true });
writeFileSync(outFile, json);
console.log(`wrote ${outFile}`);
