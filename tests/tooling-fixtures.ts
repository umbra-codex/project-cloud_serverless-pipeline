// Five real runs of .github/scripts/check.sh, kept verbatim, so the tests for
// why.sh, check-local.sh, and remote-check.sh need no Terraform and no network.
//
// SP2_RED_LOG: the finished tree with the bootstrap backend block removed and
// milestones.txt holding only SP1, so it is the view a learner has at SP2's
// first checkpoint. SP2 step 1 is green twice, step 2 is red, step 3 is red.
//
// GREEN_LOG: the finished tree, every milestone in milestones.txt, every row
// green. It is the regression fixture: an untouched earlier milestone must keep
// the verdict it had before the helpers existed.

export const SP2_RED_LOG = `Checking SP2 SP1 with OpenTofu v1.13.1
  ✅ formatting (fmt -check)
  ✅ init
  ✅ validate
  ✅ init (bootstrap)
  ✅ SP2 step 1 (bucket)
  ✅ SP2 step 1 (bucket)
  ❌ SP2 step 2 (migrate)
     terraform/bootstrap/backend.tf the bootstrap config needs an S3 backend of its own
     terraform/bootstrap/backend.tf its own key, so the pipeline destroy in SP14 cannot reach it
     terraform/bootstrap/backend.tf native locking, not a DynamoDB table
     terraform/bootstrap/backend.tf state objects are encrypted at rest
  ❌ SP2 step 3 (root-backend)
     terraform/backend.tf the root config needs the backend
     terraform/backend.tf the pipeline's own key, which keeps the two stacks apart
     terraform/backend.tf native locking here too
  ✅ SP1 step 1 (skeleton)
  ✅ SP1 step 2 (seed)
👎 Failed:
     - SP2 step 2 (migrate)
     - SP2 step 3 (root-backend)
   Fix the first one listed, commit, and push. The check runs again on every push.
`;

export const GREEN_LOG = `Checking SP1 SP2 SP3 SP4 SP5 SP6 SP7 SP8 SP9 SP10 SP11 SP12 SP13 SP14 SP15 with OpenTofu v1.13.1
  ✅ formatting (fmt -check)
  ✅ init
  ✅ validate
  ✅ init (bootstrap)
  ✅ SP1 step 1 (skeleton)
  ✅ SP1 step 2 (seed)
  ✅ SP2 step 1 (bucket)
  ✅ SP2 step 1 (bucket)
  ✅ SP2 step 2 (migrate)
  ✅ SP2 step 3 (root-backend)
  ✅ SP3 step 1 (oidc)
  ✅ SP3 step 1 (oidc)
  ✅ SP3 step 2 (trust)
  ✅ SP3 step 3 (permissions)
  ✅ SP3 step 3 (permissions)
  ✅ SP4 step 1 (workflow)
  ✅ SP4 step 2 (badge)
  ✅ SP4 step 3 (old-workflow)
  ✅ SP5 step 1 (queues)
  ✅ SP5 step 2 (table)
  ✅ SP5 step 3 (outputs)
  ✅ SP6 step 1 (s3)
  ✅ SP6 step 2 (ingest)
  ✅ SP6 step 3 (references)
  ✅ SP6 step 4 (trigger)
  ✅ SP6 step 5 (order)
  ✅ SP6 step 6 (handler)
  ✅ SP6 step 7 (wiring)
  ✅ SP6 step 8 (outputs)
  ✅ SP7 step 1 (consumer)
  ✅ SP7 step 2 (references)
  ✅ SP7 step 3 (mapping)
  ✅ SP7 step 4 (outputs)
  ✅ SP8 step 1 (budget)
  ✅ SP8 step 2 (concurrency)
  ✅ SP8 step 3 (mapping-cap)
  ✅ SP9 step 1 (consumer)
  ✅ SP9 step 2 (ingest-key)
  ✅ SP9 step 3 (wiring)
  ✅ SP10 step 1 (compose)
  ✅ SP10 step 2 (worker)
  ✅ SP10 step 3 (ingest-service)
  ✅ SP10 step 4 (schema)
  ✅ SP10 step 5 (secrets)
  ✅ SP10 step 6 (isolation)
  ✅ SP11 step 1 (status)
  ✅ SP11 step 2 (tunnel)
  ✅ SP12 step 1 (redrive)
  ✅ SP13 step 1 (bench)
  ✅ SP14 step 1 (destroyed)
  ✅ SP14 step 2 (evidence)
  ✅ SP15 step 1 (readme)
  ✅ SP15 step 2 (policy)
👍 SP1 SP2 SP3 SP4 SP5 SP6 SP7 SP8 SP9 SP10 SP11 SP12 SP13 SP14 SP15 passed.
`;

// FMT_RED_LOG: a real run on the finished tree with one line of
// terraform/backend.tf left unformatted. The formatting gate prints a bare file
// name, step 1 also goes red because the line it pins is the one that moved, and
// the run still ends with a 👎 line.

export const FMT_RED_LOG = `Checking SP1 with OpenTofu v1.13.1
  ❌ formatting (fmt -check)
     terraform/backend.tf
  ✅ init
  ✅ validate
  ✅ init (bootstrap)
  ❌ SP1 step 1 (skeleton)
     terraform/backend.tf the version pin must be >= 1.10, the release that made native S3 locking possible
  ✅ SP1 step 2 (seed)
👎 Failed:
     - formatting (fmt -check)
     - SP1 step 1 (skeleton)
   Fix the first one listed, commit, and push. The check runs again on every push.
`;

// BUN_RED_LOG: a real run where one handler test fails. bun prints its version
// banner first and the failure detail before the (pass)/(fail) list, so this is
// the shape that used to be summarized as "bun test v1.4.4". The run's own
// directory prefix was removed from the stack lines; nothing else was edited.

export const BUN_RED_LOG = `Checking SP9 with OpenTofu v1.13.1
  ✅ formatting (fmt -check)
  ✅ init
  ✅ validate
  ✅ init (bootstrap)
  ❌ SP9 step 1 (consumer)
     bun test v1.4.4 (38afee6c8)
     
     tests/sp9-1-consumer.test.ts:
     (pass) writes one row per message, with the message body kept verbatim [0.68ms]
     (pass) a duplicate is a success: it is not reported as a failure [0.28ms]
     (pass) the SDK's own duplicate error name is treated the same way [0.09ms]
     failed record m2 18 |         // The AWS SDK v3 sets the service error's name to the modelled code.
     19 |         const err = new Error("The conditional request failed");
     20 |         err.name = "ConditionalCheckFailedException";
     21 |         throw err;
     22 |       }
     23 |       if (behavior.failOn?.includes(row.idempotencyKey)) throw new Error("the table is unavailable");
                                                                             ^
     error: the table is unavailable
           at writeRow (tests/sp9-1-consumer.test.ts:23:68)
           at <anonymous> (src/consumer/handler.ts:37:20)
           at async <anonymous> (tests/sp9-1-consumer.test.ts:77:24)
     
     74 | test("only the message that genuinely failed is reported", async () => {
     75 |   const { handler, rows } = build({ failOn: ["evt-2"] });
     76 | 
     77 |   const result = await handler({ Records: [record("m1", "evt-1"), record("m2", "evt-2"), record("m3", "evt-3")] });
     78 | 
     79 |   expect(result).toEqual({ batchItemFailures: [{ itemIdentifier: "m2" }] });
                           ^
     error: expect(received).toEqual(expected)
     
       {
         "batchItemFailures": [
           {
     -       "itemIdentifier": "m2",
     +       "itemIdentifier": "wrong",
           },
         ],
       }
     
     - Expected  - 1
     + Received  + 1
     
           at <anonymous> (tests/sp9-1-consumer.test.ts:79:18)
     (fail) only the message that genuinely failed is reported [0.37ms]
     (pass) an empty batch reports nothing [0.08ms]
     
      4 pass
      1 fail
      8 expect() calls
     Ran 5 tests across 1 file. [8.00ms]
  ✅ SP9 step 2 (ingest-key)
  ✅ SP9 step 3 (wiring)
👎 Failed:
     - SP9 step 1 (consumer)
   Fix the first one listed, commit, and push. The check runs again on every push.
`;

// PITR_RED_LOG: a real run with point_in_time_recovery turned off in
// terraform/table.tf. The assertion message is followed by the next run result
// trailer with no blank line between them, which is the shape that used to glue
// the next run trailer onto the end of the message.

export const PITR_RED_LOG = `Checking SP5 with OpenTofu v1.13.1
  ✅ formatting (fmt -check)
  ✅ init
  ✅ validate
  ✅ init (bootstrap)
  ✅ SP5 step 1 (queues)
  ❌ SP5 step 2 (table)
     ../tests/sp5-2-table.tftest.hcl... fail
       run "events_table"... fail
     
     Error: Test assertion failed
     
       on ../tests/sp5-2-table.tftest.hcl line 90, in run "events_table":
       90:     condition     = length(aws_dynamodb_table.events.point_in_time_recovery) == 1 && one(aws_dynamodb_table.events.point_in_time_recovery).enabled == true
         ├────────────────
         │ aws_dynamodb_table.events.point_in_time_recovery is list of object with 1 element
     
     Point-in-time recovery must be on: point_in_time_recovery { enabled = true }.
     
     Error: Test assertion failed
     
       on ../tests/sp5-2-table.tftest.hcl line 95, in run "events_table":
       95:     condition     = length(aws_dynamodb_table.events.server_side_encryption) == 1 && one(aws_dynamodb_table.events.server_side_encryption).enabled == true
         ├────────────────
         │ aws_dynamodb_table.events.server_side_encryption is list of object with 1 element
     
     Server-side encryption must be on: server_side_encryption { enabled = true }.
       run "table_name_follows_the_prefix"... pass
     
     Failure! 1 passed, 1 failed.
  ✅ SP5 step 3 (outputs)
👎 Failed:
     - SP5 step 2 (table)
   Fix the first one listed, commit, and push. The check runs again on every push.
`;

// BOOT_RED_LOG: a real run where terraform/bootstrap/providers.tf names a
// provider that does not exist, so init (bootstrap) is red and no step runs. The
// block is tofu's boxed diagnostic under a progress line, which is the shape that
// used to be reported as "red at init" with "Initializing: provider plugins..."
// as the message. The one search-location path was replaced with a placeholder.

export const BOOT_RED_LOG = `Checking SP2 with OpenTofu v1.13.1
  ✅ formatting (fmt -check)
  ✅ init
  ✅ validate
  ❌ init (bootstrap)
     
     [0m[1mInitializing provider plugins...[0m
     - Finding latest version of hashicorp/bogus...
     - Reusing previous version of hashicorp/aws from the dependency lock file
     - Installing hashicorp/aws v6.69.1...
     - Installed hashicorp/aws v6.69.1 (unauthenticated)
     [31m╷[0m[0m
     [31m│[0m [0m[1m[31mError: [0m[0m[1mFailed to query available provider packages[0m
     [31m│[0m [0m
     [31m│[0m [0m[0mCould not retrieve the list of available versions for provider
     [31m│[0m [0mhashicorp/bogus: provider registry.opentofu.org/hashicorp/bogus was not
     [31m│[0m [0mfound in any of the search locations
     [31m│[0m [0m
     [31m│[0m [0m  - <your providers directory>
     [31m╵[0m[0m
👎 Failed:
     - init (bootstrap)
   Fix the first one listed, commit, and push. The check runs again on every push.
`;
