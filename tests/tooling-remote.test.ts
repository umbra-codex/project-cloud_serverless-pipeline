// remote-check.sh must follow the run the push started, and must never start
// one of its own: a second run on the same branch cancels the first. A fake gh
// over a JSON file, and a throwaway git repository, make both testable offline.
import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { GREEN_LOG, SP2_RED_LOG } from "./tooling-fixtures";

const ROOT = path.resolve(import.meta.dir, "..");

const FAKE_GH = `#!/usr/bin/env bash
# A stand-in for the GitHub CLI. It answers from files, records every call, and
# marks it loudly if anything tries to start a run.
echo "$*" >> "$FAKE_GH_CALLS"
case "$1 $2" in
  "auth status")
    echo "github.com"
    echo "  Logged in to github.com account test"
    exit 0 ;;
  "run list")
    commit=""
    prev=""
    for a in "$@"; do
      [ "$prev" = "--commit" ] && commit="$a"
      prev="$a"
    done
    id=$(sed -nE 's/.*"'"$commit"'"[[:space:]]*:[[:space:]]*([0-9]+).*/\\1/p' "$FAKE_GH_JSON")
    [ -n "$id" ] && printf '%s\\n' "$id"
    exit 0 ;;
  "run watch")
    exit "\${FAKE_WATCH_CODE:-0}" ;;
  "run view")
    case "$*" in
      *--log*) cat "$FAKE_GH_LOG" ;;
      *) echo "https://example.test/run/$3" ;;
    esac
    exit 0 ;;
  "workflow run")
    : > "$FAKE_GH_DISPATCH"
    exit 0 ;;
esac
exit 0
`;

function repo() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "remote-check-"));
  fs.mkdirSync(path.join(dir, ".github/scripts"), { recursive: true });
  fs.mkdirSync(path.join(dir, "docs/milestones"), { recursive: true });
  fs.mkdirSync(path.join(dir, "bin"), { recursive: true });
  for (const f of ["remote-check.sh", "why.sh"]) {
    fs.copyFileSync(path.join(ROOT, ".github/scripts", f), path.join(dir, ".github/scripts", f));
  }
  fs.copyFileSync(path.join(ROOT, "docs/milestones/SP2.md"), path.join(dir, "docs/milestones/SP2.md"));
  fs.chmodSync(path.join(dir, ".github/scripts/remote-check.sh"), 0o755);

  const gh = path.join(dir, "bin/gh");
  fs.writeFileSync(gh, FAKE_GH);
  fs.chmodSync(gh, 0o755);

  const git = (args: string[]) =>
    spawnSync("git", args, {
      cwd: dir,
      encoding: "utf8",
      env: {
        ...process.env,
        GIT_AUTHOR_NAME: "test",
        GIT_AUTHOR_EMAIL: "test@example.test",
        GIT_COMMITTER_NAME: "test",
        GIT_COMMITTER_EMAIL: "test@example.test",
      },
    });

  git(["init", "-q"]);
  git(["checkout", "-q", "-b", "sp2-state"]);
  git(["add", "-A"]);
  git(["commit", "-q", "-m", "checkpoint"]);
  git(["remote", "add", "origin", path.join(dir, "origin.git")]);
  git(["update-ref", "refs/remotes/origin/sp2-state", "HEAD"]);
  git(["config", "branch.sp2-state.remote", "origin"]);
  git(["config", "branch.sp2-state.merge", "refs/heads/sp2-state"]);

  const head = spawnSync("git", ["rev-parse", "HEAD"], { cwd: dir, encoding: "utf8" }).stdout.trim();
  const calls = path.join(dir, "calls.txt");
  const dispatch = path.join(dir, "dispatched.txt");
  const log = path.join(dir, "run.log");
  const json = path.join(dir, "runs.json");
  return {
    dir,
    head,
    calls,
    dispatch,
    log,
    json,
    env: {
      PATH: `${path.join(dir, "bin")}:${process.env.PATH ?? ""}`,
      FAKE_GH_CALLS: calls,
      FAKE_GH_DISPATCH: dispatch,
      FAKE_GH_JSON: json,
      FAKE_GH_LOG: log,
      POLLS: "1",
      POLL_SLEEP: "0",
    },
  };
}

function follow(t: ReturnType<typeof repo>, args: string[] = [], extra: Record<string, string> = {}) {
  const r = spawnSync("bash", [".github/scripts/remote-check.sh", ...args], {
    cwd: t.dir,
    encoding: "utf8",
    env: { ...process.env, ...t.env, ...extra },
  });
  return { code: r.status, out: `${r.stdout ?? ""}${r.stderr ?? ""}` };
}

describe("remote-check.sh", () => {
  test("follows the run for the pushed commit and prints the same summary", () => {
    const t = repo();
    try {
      fs.writeFileSync(t.json, `{"${t.head}": 4242}\n`);
      fs.writeFileSync(t.log, SP2_RED_LOG);
      const { code, out } = follow(t, ["SP2"], { FAKE_WATCH_CODE: "1" });
      expect(code).toBe(1);
      expect(out).toContain("Looking for the run your push started...");
      expect(out).toContain("SP2: 2 of 4 checks green");
      expect(out).toContain("Next: SP2 step 2 (migrate). Re-read docs/milestones/SP2.md");
      expect(out).toContain("Full results: https://example.test/run/4242");
      // It asked for the commit that was pushed, on the milestone-check workflow.
      const calls = fs.readFileSync(t.calls, "utf8");
      expect(calls).toContain("run list --workflow milestone-check.yml --branch sp2-state");
      expect(calls).toContain(`--commit ${t.head}`);
      expect(calls).toContain("run watch 4242 --exit-status");
    } finally {
      fs.rmSync(t.dir, { recursive: true, force: true });
    }
  });

  test("never starts a run, even when no run exists for the commit", () => {
    const t = repo();
    try {
      fs.writeFileSync(t.json, "{}\n");
      fs.writeFileSync(t.log, SP2_RED_LOG);
      const { code, out } = follow(t, ["SP2"]);
      expect(code).toBe(1);
      expect(out).toContain("No run of milestone-check.yml appeared for this commit");
      expect(out).toContain("Nothing was started, on purpose");
      expect(fs.existsSync(t.dispatch)).toBe(false);
      expect(fs.readFileSync(t.calls, "utf8")).not.toContain("workflow run");
    } finally {
      fs.rmSync(t.dir, { recursive: true, force: true });
    }
  });

  test("a green run exits 0", () => {
    const t = repo();
    try {
      fs.writeFileSync(t.json, `{"${t.head}": 77}\n`);
      fs.writeFileSync(t.log, GREEN_LOG);
      const { code, out } = follow(t, ["SP2"], { FAKE_WATCH_CODE: "0" });
      expect(code).toBe(0);
      expect(out).toContain("SP2: 4 of 4 checks green");
      expect(out).toContain("👍 SP2 passed.");
      expect(fs.existsSync(t.dispatch)).toBe(false);
    } finally {
      fs.rmSync(t.dir, { recursive: true, force: true });
    }
  });

  test("--summarize reads a saved log and needs no GitHub at all", () => {
    const t = repo();
    try {
      const r = spawnSync("bash", [".github/scripts/remote-check.sh", "--summarize", "SP2"], {
        cwd: t.dir,
        input: SP2_RED_LOG,
        encoding: "utf8",
        env: { ...process.env, PATH: "/usr/bin:/bin" },
      });
      expect(r.stdout).toContain("SP2: 2 of 4 checks green");
      expect(r.stdout).toContain("❌ SP2 step 2 (migrate)      <- next");
    } finally {
      fs.rmSync(t.dir, { recursive: true, force: true });
    }
  });

  test("a branch with no milestone in its name gets a milestone-shaped hint, not SP2", () => {
    const t = repo();
    const git = (args: string[]) => spawnSync("git", args, { cwd: t.dir, encoding: "utf8" });
    try {
      git(["checkout", "-q", "-b", "experiment"]);
      git(["update-ref", "refs/remotes/origin/experiment", "HEAD"]);
      git(["config", "branch.experiment.remote", "origin"]);
      git(["config", "branch.experiment.merge", "refs/heads/experiment"]);
      const { code, out } = follow(t, []);
      expect(code).toBe(1);
      expect(out).toContain("<your milestone>");
      expect(out).not.toContain("remote-check.sh SP2");
      expect(fs.existsSync(t.dispatch)).toBe(false);
    } finally {
      fs.rmSync(t.dir, { recursive: true, force: true });
    }
  });

  test("a signed-out CLI is reported, not polled for", () => {
    const t = repo();
    try {
      const gh = path.join(t.dir, "bin/gh");
      fs.writeFileSync(gh, `#!/usr/bin/env bash\ncase "$1 $2" in "auth status") echo "You are not logged into any GitHub hosts. Run gh auth login." >&2; exit 1 ;; esac\nexit 0\n`);
      fs.chmodSync(gh, 0o755);
      const { code, out } = follow(t, ["SP2"]);
      expect(code).toBe(1);
      expect(out).toContain("can't reach your account");
      expect(out).toContain("gh auth login");
    } finally {
      fs.rmSync(t.dir, { recursive: true, force: true });
    }
  });
});
