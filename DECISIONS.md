# Decisions
- 2026-10-25 SP4: two workflows, because the step tests need Bun and any branch, while the plan needs an identity
- 2026-11-08 SP13: AWS benchmark, 1,000 events, p50 21.38 s, p95 43.71 s, includes the queue wait; cost per 1,000 is 0.0071 USD (DynamoDB + S3, 2026-11-07 to 2026-11-08, credits excluded), from evidence/cost-explorer.txt
- 2026-11-08 SP13: Compose benchmark, 1,000 events, p50 0.93 ms, p95 1.42 ms, a floor because requests were sent one at a time; 0 USD of cloud spend
