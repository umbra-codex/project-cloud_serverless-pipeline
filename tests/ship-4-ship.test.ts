// The ship check is a script, and a check that has never failed has not been
// tested. These tests run it against ten throwaway trees: one that is clean, and
// nine that each carry one thing it refuses.
//
// None of them reads this repository, and this step is deliberate about that: the
// shipped tree still holds everything on the list, so a working-tree assertion
// here would be red until Part 5 and would make the milestone check disagree with
// its own checkpoint. The gate on the working tree is the ship check itself, run
// by hand at the checkpoint and again before the removal commit, which is what
// SHIP.md's "About step 4" says and what its expected output shows.
import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const ROOT = path.resolve(import.meta.dir, "..");
const SCRIPT = path.join(ROOT, ".github/scripts/ship-check.sh");

const WORKFLOW = [
  "on:",
  "  push:",
  "  pull_request:",
  "run: tofu fmt -check -recursive",
  "run: tofu -chdir=terraform validate -no-color",
  "run: tflint --recursive --config \"$(pwd)/.tflint.hcl\"",
  "run: checkov",
  "run: tofu -chdir=terraform test -no-color -test-directory=../tests",
  "run: bun test ./tests",
  "",
].join("\n");

// A tree the check has nothing to say about: the product, its tests, the
// evidence, the README, the license and the normal workflow.
const CLEAN: Record<string, string> = {
  "README.md": "# pipeline\n\nWhat proves it: a green run.\n",
  "LICENSE": "MIT License\n\nCopyright (c) 2026 Someone\n",
  ".github/workflows/ci.yml": WORKFLOW,
  "src/ingest/handler.ts": "export const handler = () => undefined;\n",
  "terraform/main.tf": "\n",
  "tests/sp5-1-queues.tftest.hcl": "\n",
  "tests/sp6-6-handler.test.ts": "\n",
  "evidence/README.md": "# Evidence\n",
};

function tree(files: Record<string, string>): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ship-check-"));
  for (const [rel, body] of Object.entries(files)) {
    const full = path.join(dir, rel);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, body);
  }
  return dir;
}

function check(files: Record<string, string>) {
  const dir = tree(files);
  try {
    return { ...spawnSync("bash", [SCRIPT, dir], { encoding: "utf8" }), dir };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

describe("ship-check.sh", () => {
  test("passes on a tree with nothing left to remove", () => {
    const r = check(CLEAN);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain("👍 Ship check passed.");
  });

  test("fails while the briefs are still there, and names the folder", () => {
    const r = check({ ...CLEAN, "docs/milestones/SP9.md": "# SP9: Idempotent writes\n" });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("docs: still here");
    expect(r.stdout).toContain("👎 Ship check failed");
  });

  test("fails while the milestone list is still there", () => {
    const r = check({ ...CLEAN, "milestones.txt": "SP1\n" });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("milestones.txt: still here");
  });

  test("fails on a learner-facing word and names the file that holds it", () => {
    const r = check({ ...CLEAN, "src/ingest/notes.md": "## Checkpoint\n\nRun it.\n" });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("src/ingest/notes.md: the word Checkpoint");
  });

  test("fails on a local path", () => {
    const r = check({ ...CLEAN, "scripts/run.sh": "cd /home/someone/project\n" });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("scripts/run.sh: an absolute home path");
  });

  test("fails on a secret-shaped string and never prints the line", () => {
    const r = check({ ...CLEAN, "terraform/variables.tf": 'default = "AKIAIOSFODNN7EXAMPLE"\n' });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("terraform/variables.tf: an access key id");
    expect(r.stdout).not.toContain("AKIAIOSFODNN7EXAMPLE");
  });

  test("fails on a TODO", () => {
    const r = check({ ...CLEAN, "src/consumer/index.ts": "// TODO: retry\n" });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("src/consumer/index.ts: a TODO");
  });

  test("fails on a placeholder where a real link belongs", () => {
    const r = check({
      ...CLEAN,
      "README.md": "# pipeline\n\n[the run](https://github.com/OWNER/pipeline/actions/runs/000000000)\n",
    });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("README.md: a placeholder where a real link belongs");
  });

  test("fails when the normal workflow is gone", () => {
    const files = { ...CLEAN };
    delete files[".github/workflows/ci.yml"];
    const r = check(files);
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("the normal workflow is gone");
  });

  test("fails when a workflow still calls the milestone runner", () => {
    const r = check({
      ...CLEAN,
      ".github/workflows/ci.yml": WORKFLOW.replace(
        "run: bun test ./tests",
        "run: bun test ./tests\n  run: .github/scripts/check.sh SP1 all",
      ),
    });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain(".github/workflows/ci.yml: still calls the milestone runner");
  });
});
