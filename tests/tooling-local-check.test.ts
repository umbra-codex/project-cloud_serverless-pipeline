// check-local.sh is presentation around .github/scripts/check.sh: it must run
// that file, with the argument list CI passes, keep the run in a file, and hand
// the output to why.sh. A stub runner and a stub tofu make that testable with no
// Terraform, no provider download, and no network.
import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { GREEN_LOG, SP2_RED_LOG } from "./tooling-fixtures";

const ROOT = path.resolve(import.meta.dir, "..");

function run(args: string[], cwd: string, env: Record<string, string> = {}) {
  const r = spawnSync("bash", [".github/scripts/check-local.sh", ...args], {
    cwd,
    encoding: "utf8",
    env: { ...process.env, ...env },
  });
  return { code: r.status, out: `${r.stdout ?? ""}${r.stderr ?? ""}` };
}

// A tree that looks like the repository, with the runner replaced by a stub that
// prints a saved run. Everything else is the file the guide ships.
function stubTree(log: string, exitCode: number) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "check-local-"));
  fs.mkdirSync(path.join(dir, ".github/scripts"), { recursive: true });
  fs.mkdirSync(path.join(dir, "docs/milestones"), { recursive: true });
  fs.mkdirSync(path.join(dir, "bin"), { recursive: true });
  for (const f of ["check-local.sh", "why.sh"]) {
    fs.copyFileSync(path.join(ROOT, ".github/scripts", f), path.join(dir, ".github/scripts", f));
  }
  fs.copyFileSync(path.join(ROOT, "docs/milestones/SP2.md"), path.join(dir, "docs/milestones/SP2.md"));
  fs.writeFileSync(path.join(dir, "run.log"), log);
  fs.writeFileSync(
    path.join(dir, ".github/scripts/check.sh"),
    `#!/usr/bin/env bash\n# Stub: records the arguments it was given, then prints a saved run.\necho "ARGS: $*"\ncat "$STUB_LOG"\nexit ${exitCode}\n`,
  );
  const tofu = path.join(dir, "bin/tofu");
  fs.writeFileSync(tofu, `#!/usr/bin/env bash\necho "OpenTofu v1.13.1"\n`);
  fs.chmodSync(tofu, 0o755);
  return { dir, env: { PATH: `${path.join(dir, "bin")}:${process.env.PATH ?? ""}`, STUB_LOG: path.join(dir, "run.log") } };
}

describe("check-local.sh", () => {
  test("runs check.sh with the arguments CI uses, keeps the run, and reports a red step", () => {
    const { dir, env } = stubTree(SP2_RED_LOG, 1);
    try {
      const { code, out } = run(["SP2"], dir, env);
      expect(code).toBe(1);
      expect(out).toContain("Running .github/scripts/check.sh SP2 all");
      // The saved run proves the runner saw exactly CI's argument list.
      const saved = fs.readFileSync(path.join(dir, ".terraform/check/last-run.log"), "utf8");
      expect(saved.split("\n")[0]).toBe("ARGS: SP2 all");
      expect(out).toContain("SP2: 2 of 4 checks green");
      expect(out).toContain("Next: SP2 step 2 (migrate). Re-read docs/milestones/SP2.md");
      expect(out).toContain("The whole run is saved in .terraform/check/last-run.log.");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test("a green run exits 0 and says the milestone passed", () => {
    const { dir, env } = stubTree(GREEN_LOG, 0);
    try {
      const { code, out } = run(["SP2"], dir, env);
      expect(code).toBe(0);
      expect(out).toContain("SP2: 4 of 4 checks green");
      expect(out).toContain("👍 SP2 passed.");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test("--explain adds the raw output, and the default does not", () => {
    const { dir, env } = stubTree(SP2_RED_LOG, 1);
    try {
      expect(run(["SP2"], dir, env).out).not.toContain("Full check output:");
      const withRaw = run(["SP2", "--explain"], dir, env);
      expect(withRaw.out).toContain("Full check output:");
      expect(withRaw.out).toContain("terraform/bootstrap/backend.tf the bootstrap config needs an S3 backend of its own");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test("a milestone with no brief is refused before anything runs", () => {
    const { dir, env } = stubTree(SP2_RED_LOG, 1);
    try {
      const { code, out } = run(["SP9"], dir, env);
      expect(code).toBe(2);
      expect(out).toContain("docs/milestones/SP9.md is not here");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test("a branch with no milestone in its name gets a milestone-shaped hint, not SP2", () => {
    const { dir, env } = stubTree(SP2_RED_LOG, 1);
    try {
      const { code, out } = run([], dir, env);
      expect(code).toBe(2);
      expect(out).toContain("<your milestone>");
      expect(out).not.toContain("check-local.sh SP2");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  test("--help prints the usage and exits 0", () => {
    const { code, out } = run(["--help"], ROOT);
    expect(code).toBe(0);
    expect(out).toContain("bash .github/scripts/check-local.sh [milestone] [--explain]");
  });

  test("an unknown option is refused", () => {
    const { code, out } = run(["--wat"], ROOT);
    expect(code).toBe(2);
    expect(out).toContain("unknown option --wat");
  });
});
