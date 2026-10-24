// why.sh reads a check run and says which step to fix, where in the brief to
// re-read, and what the check looked for. Both fixtures are real runs, saved
// verbatim, so this needs no Terraform, no AWS, and no network.
import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { GREEN_LOG, BOOT_RED_LOG, BUN_RED_LOG, FMT_RED_LOG, PITR_RED_LOG, SP2_RED_LOG } from "./tooling-fixtures";

const ROOT = path.resolve(import.meta.dir, "..");

function why(args: string[], stdin: string) {
  const r = spawnSync("bash", [".github/scripts/why.sh", ...args], {
    cwd: ROOT,
    input: stdin,
    encoding: "utf8",
  });
  return { code: r.status, out: r.stdout ?? "", err: r.stderr ?? "" };
}

describe("why.sh on a real incomplete tree (SP2, step 2 not built)", () => {
  test("the summary counts the check files and marks the first red step", () => {
    const { code, out } = why(["--summary", "SP2"], SP2_RED_LOG);
    expect(code).toBe(1);
    expect(out).toContain("SP2: 2 of 4 checks green");
    expect(out).toContain("  ✅ formatting, init, validate");
    expect(out).toContain("  ✅ SP2 step 1 (bucket)");
    expect(out).toContain("  ❌ SP2 step 2 (migrate)      <- next");
    expect(out).toContain("  ❌ SP2 step 3 (root-backend)");
    expect(out).toContain("✅ every other milestone in milestones.txt passes (SP1)");
    // A red run must never claim a pass.
    expect(out).not.toContain("👍");
  });

  test("the first thing to fix: the step, the brief section, the check's own message", () => {
    const { code, out } = why(["--first", "SP2"], SP2_RED_LOG);
    expect(code).toBe(0);
    const lines = out.trimEnd().split("\n");
    expect(lines[0]).toBe(
      'Next: SP2 step 2 (migrate). Re-read docs/milestones/SP2.md, "## Part 2: Move the bootstrap state into the bucket it just made".',
    );
    expect(lines[1]).toBe("terraform/bootstrap/backend.tf: the bootstrap config needs an S3 backend of its own");
    expect(lines[2]).toContain("Also failing: its own key, so the pipeline destroy in SP14 cannot reach it");
    expect(out).toContain("Run bash .github/scripts/check-local.sh --explain for the full output.");
  });

  test("one step by number gives the same pointer and no raw detail", () => {
    const { out } = why(["SP2", "2"], SP2_RED_LOG);
    expect(out.split("\n")[0]).toContain('"## Part 2: Move the bootstrap state');
    expect(out).not.toContain("     terraform/bootstrap/backend.tf the bootstrap config");
  });

  test("--explain adds the check's own lines, unedited", () => {
    const { out } = why(["SP2", "2", "--explain"], SP2_RED_LOG);
    expect(out).not.toContain("Full check output"); // that hint belongs to check-local.sh
    expect(out).toContain("terraform/bootstrap/backend.tf the bootstrap config needs an S3 backend of its own");
  });

  test("--next prints the number of the first red step", () => {
    const { code, out } = why(["--next", "SP2"], SP2_RED_LOG);
    expect(code).toBe(0);
    expect(out.trim()).toBe("2");
  });
});

describe("why.sh on a milestone nobody touched (regression fixture)", () => {
  test("SP1 keeps the verdict it had: two of two, passed", () => {
    const { code, out } = why(["--summary", "SP1"], GREEN_LOG);
    expect(code).toBe(0);
    expect(out).toContain("SP1: 2 of 2 checks green");
    expect(out).toContain("👍 SP1 passed.");
  });

  test("nothing to fix on a green run", () => {
    const { code, out } = why(["--first", "SP1"], GREEN_LOG);
    expect(code).toBe(3);
    expect(out.trim()).toBe("");
  });
});

describe("why.sh on a red formatting gate", () => {
  test("names the file once, not path: path", () => {
    const { code, out } = why(["--first", "SP1"], FMT_RED_LOG);
    expect(code).toBe(0);
    const lines = out.trimEnd().split("\n");
    expect(lines[0]).toBe(
      "Next: SP1 is red at formatting (fmt -check), which fails the whole run on its own. The formatter wants to change these files:",
    );
    expect(lines[1]).toBe("terraform/backend.tf");
    expect(out).not.toContain("terraform/backend.tf: terraform/backend.tf");
    expect(out).toContain("Run tofu fmt -recursive from the repo root");
  });

  test("the summary says a gate is red, and still counts the steps that ran", () => {
    const { code, out } = why(["--summary", "SP1"], FMT_RED_LOG);
    expect(code).toBe(1);
    expect(out).toContain("SP1: 1 of 2 checks green");
    expect(out).toContain("a gate before the steps is red, which fails the run on its own");
  });
});

describe("why.sh on a failing handler test (bun)", () => {
  test("names the test and its error, not bun's version banner", () => {
    const { code, out } = why(["--first", "SP9"], BUN_RED_LOG);
    expect(code).toBe(0);
    expect(out.split("\n")[0]).toContain("Next: SP9 step 1 (consumer)");
    expect(out).toContain("only the message that genuinely failed is reported: the table is unavailable");
    expect(out).not.toContain("bun test v");
  });

  test("the summary counts the handler rows like any other", () => {
    const { code, out } = why(["--summary", "SP9"], BUN_RED_LOG);
    expect(code).toBe(1);
    expect(out).toContain("SP9: 2 of 3 checks green");
    expect(out).toContain("  ❌ SP9 step 1 (consumer)      <- next");
  });
});

describe("why.sh on a Terraform assertion with no blank line after it", () => {
  test("the message ends with the assertion, not the next run's result", () => {
    const { code, out } = why(["--first", "SP5"], PITR_RED_LOG);
    expect(code).toBe(0);
    expect(out.split("\n")[0]).toContain("Next: SP5 step 2 (table)");
    expect(out).toContain("Point-in-time recovery must be on: point_in_time_recovery { enabled = true }.");
    expect(out).not.toContain('run "');
  });
});

describe("why.sh on a GitHub-shaped log", () => {
  test("the row count does not depend on the space after the timestamp", () => {
    for (const pad of ["", " ", "  ", "   "]) {
      const wrapped = PITR_RED_LOG.split("\n")
        .map((l) => `job\tstep\t2026-10-22T10:00:00.000Z${pad}${l}`)
        .join("\n");
      const { out } = why(["--summary", "SP5"], wrapped);
      expect(out).toContain("SP5: 2 of 3 checks green");
      expect(out).toContain("❌ SP5 step 2 (table)      <- next");
    }
  });
});

describe("why.sh on a red bootstrap gate", () => {
  test("names init (bootstrap), not init, and quotes the error rather than the progress line", () => {
    const { code, out } = why(["--first", "SP2"], BOOT_RED_LOG);
    expect(code).toBe(0);
    const lines = out.trimEnd().split("\n");
    expect(lines[0]).toBe(
      "Next: SP2 is red at init (bootstrap), so no step could run on this configuration. The check's own message:",
    );
    expect(out).toContain("Failed to query available provider packages");
    expect(out).toContain("Also failing: Could not retrieve the list of available versions for provider hashicorp/bogus");
    // Neither the progress line nor a box glyph belongs in the message.
    expect(out).not.toContain("Initializing provider plugins");
    expect(out).not.toContain("│");
    expect(out).toContain("The bootstrap folder is its own root module, and its init has to succeed too.");
  });

  test("the summary says which gate is red instead of pointing above the gate line", () => {
    const { code, out } = why(["--summary", "SP2"], BOOT_RED_LOG);
    expect(code).toBe(1);
    expect(out).toContain("SP2: the steps did not run: init (bootstrap) is red and the run stopped there");
    expect(out).not.toContain("the gate above is red");
    expect(out).toContain("  ✅ formatting, init, validate");
    expect(out).toContain("  ❌ init (bootstrap)");
  });
});

describe("why.sh pointers", () => {
  test("a two-step block sends each step to the part that builds it", () => {
    // SP0's one block covers the skeleton and the seed, both in Part 2.
    expect(why(["SP0", "1"], "").out).toContain('"## Part 2: Your branch, and the scaffold"');
    expect(why(["SP0", "2"], "").out).toContain('"## Part 2: Your branch, and the scaffold"');
  });

  test("a block that names a range sends each step to its own part", () => {
    // SHIP's block is "steps 1 to 3 (ship check, README, license)": a range, and
    // a comma-separated list, which is the shape the other briefs do not use.
    expect(why(["SHIP", "1"], "").out).toContain('"## Part 1: The ship check", item 1');
    expect(why(["SHIP", "2"], "").out).toContain('"## Part 2: The README a stranger reads"');
    expect(why(["SHIP", "3"], "").out).toContain('"## Part 3: The license", item 3');
  });

  test("a step the block does not cover lands on its own section", () => {
    // Step 4 is the check's own test, and it has a heading written for it.
    const out = why(["SHIP", "4"], "").out;
    expect(out).toContain('"### About step 4: the check\'s own test"');
    expect(out).not.toContain('"## Part 3');
  });

  test("the usage line documents --explain on every mode that takes it", () => {
    const { code, out } = why(["--help"], "");
    expect(code).toBe(0);
    for (const mode of ["--summary", "--first", "--next"]) {
      const line = out.split("\n").find((l) => l.includes(mode))!;
      expect(line).toContain("[--explain]");
    }
  });
});

describe("why.sh with nothing to read", () => {
  test("an empty log says the run stopped, and does not count rows it did not see", () => {
    const { code, out } = why(["--summary", "SP2"], "");
    expect(code).toBe(1);
    expect(out).toContain("SP2: the run stopped before the check printed a result");
  });

  test("a log with rows but no ending is not a pass", () => {
    const cut = GREEN_LOG.split("\n").filter((l) => !l.startsWith("👍")).join("\n");
    const { code, out } = why(["--summary", "SP1"], cut);
    expect(code).toBe(1);
    expect(out).toContain("the run stopped before the check finished");
  });

  test("a truncated log says how many of the milestone's checks it saw", () => {
    const cut = SP2_RED_LOG.split("\n")
      .filter((l) => !l.includes("SP2 step 2") && !l.includes("SP2 step 3") && !l.startsWith("👎"))
      .join("\n");
    const { code, out } = why(["--summary", "SP2"], cut);
    expect(code).toBe(1);
    expect(out).toContain("SP2: 2 of 4 checks green, and the check reported only 2 of them");
  });

  test("gate rows but no step rows: the steps did not run, not \"no checks ran\"", () => {
    const cut = FMT_RED_LOG.split("\n")
      .filter((l) => !/^  [✅❌] SP1 step/.test(l) && !l.startsWith("👎"))
      .join("\n");
    const { code, out } = why(["--summary", "SP1"], cut);
    expect(code).toBe(1);
    expect(out).toContain("SP1: the steps did not run: the gate above is red and the run stopped there");
    expect(out).not.toContain("no checks ran");
  });

  test("a step number that is not a number is refused", () => {
    const { code, out } = why(["SP2", "two"], SP2_RED_LOG);
    expect(code).toBe(2);
    expect(out).toContain("is not a step number");
  });
});
