// The lint is what keeps a new brief from drifting back to "open the results on
// the pull request": every checkpoint block has to name the command. These tests
// run it on the briefs that ship, and on a copy with one block's command taken
// out, which has to fail.
import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const ROOT = path.resolve(import.meta.dir, "..");
const BRIEFS = path.join(ROOT, "docs/milestones");
const CMD = "bash .github/scripts/check-local.sh";

const lint = (cwd: string) =>
  spawnSync("bash", [".github/scripts/lint-briefs.sh"], { cwd, encoding: "utf8" });

function briefCopy(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "lint-briefs-"));
  fs.mkdirSync(path.join(dir, ".github/scripts"), { recursive: true });
  fs.mkdirSync(path.join(dir, "docs/milestones"), { recursive: true });
  fs.copyFileSync(path.join(ROOT, ".github/scripts/lint-briefs.sh"), path.join(dir, ".github/scripts/lint-briefs.sh"));
  for (const f of fs.readdirSync(BRIEFS)) {
    fs.copyFileSync(path.join(BRIEFS, f), path.join(dir, "docs/milestones", f));
  }
  return dir;
}

describe("lint-briefs.sh", () => {
  test("every checkpoint block in every brief is complete", () => {
    const r = lint(ROOT);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain("👍 38 checkpoint blocks in 17 briefs");
  });

  test("the briefs carry one command line per block", () => {
    let blocks = 0;
    let commands = 0;
    for (const f of fs.readdirSync(BRIEFS)) {
      const text = fs.readFileSync(path.join(BRIEFS, f), "utf8");
      blocks += (text.match(/^\*\*.*Checkpoint: steps? /gm) ?? []).length;
      commands += (text.match(new RegExp(`^${CMD}$`, "gm")) ?? []).length;
    }
    expect(blocks).toBe(38);
    expect(commands).toBeGreaterThanOrEqual(blocks);
  });

  test("a block with the command taken out fails the lint, naming the file and line", () => {
    const dir = briefCopy();
    try {
      const file = path.join(dir, "docs/milestones/SP5.md");
      const before = fs.readFileSync(file, "utf8");
      const after = before.replace(`${CMD}\n`, "");
      expect(after).not.toBe(before);
      fs.writeFileSync(file, after);
      const r = lint(dir);
      expect(r.status).toBe(1);
      expect(r.stdout).toContain("docs/milestones/SP5.md");
      expect(r.stdout).toContain("the command");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test("a block that tells the learner to commit before the check fails the lint", () => {
    const dir = briefCopy();
    try {
      const file = path.join(dir, "docs/milestones/SP5.md");
      const text = fs.readFileSync(file, "utf8").replace(
        "**✅ Checkpoint: step 1 (queues)**\n",
        "**✅ Checkpoint: step 1 (queues)**\nCommit your work and push it:\n",
      );
      fs.writeFileSync(file, text);
      const r = lint(dir);
      expect(r.status).toBe(1);
      expect(r.stdout).toContain("tells the learner to commit or push before it runs the check");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test("a half-sentence left behind by a rewrite fails the lint", () => {
    const dir = briefCopy();
    try {
      const file = path.join(dir, "docs/milestones/SP5.md");
      const text = fs.readFileSync(file, "utf8").replace(
        /^(The push runs the same check on GitHub[^\n]*)$/m,
        "$1\npull request (see [How to see your results](#how-to-see-your-results)).",
      );
      fs.writeFileSync(file, text);
      const r = lint(dir);
      expect(r.status).toBe(1);
      expect(r.stdout).toContain("this line starts mid-sentence");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test("a block that only points at the results page fails the lint", () => {
    const dir = briefCopy();
    try {
      const file = path.join(dir, "docs/milestones/SP7.md");
      const text = fs.readFileSync(file, "utf8").replace(
        `${CMD}\n`,
        "Open the results on the pull request.\n",
      );
      fs.writeFileSync(file, text);
      const r = lint(dir);
      expect(r.status).toBe(1);
      expect(r.stdout).toContain("sends the learner to the results page instead of a command");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("the pointers between briefs", () => {
  const slug = (h: string) =>
    h.toLowerCase().replace(/`/g, "").replace(/[^a-z0-9 -]/g, "").trim().replace(/ +/g, "-");

  test("every SP-note anchor a brief links to exists in that brief", () => {
    const headings = new Map<string, Set<string>>();
    for (const f of fs.readdirSync(BRIEFS)) {
      const text = fs.readFileSync(path.join(BRIEFS, f), "utf8");
      const set = new Set<string>();
      for (const line of text.split("\n")) {
        const m = line.match(/^#{2,6} +(.*)$/);
        if (m) set.add(slug(m[1]!.trim()));
      }
      headings.set(f, set);
    }
    const broken: string[] = [];
    for (const f of fs.readdirSync(BRIEFS)) {
      const text = fs.readFileSync(path.join(BRIEFS, f), "utf8");
      for (const m of text.matchAll(/\]\((SP\d+)\.md#([a-z0-9-]+)\)/g)) {
        const target = `${m[1]}.md`;
        if (!headings.has(target)) broken.push(`${f}: ${target} does not exist`);
        else if (!headings.get(target)!.has(m[2]!)) broken.push(`${f}: ${target}#${m[2]}`);
      }
    }
    expect(broken).toEqual([]);
  });
});
