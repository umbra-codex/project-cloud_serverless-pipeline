#!/usr/bin/env bash
set -euo pipefail

COUNT=${1:-1000}

TABLE=$(tofu -chdir=terraform output -raw table_name)
BUCKET=$(tofu -chdir=terraform output -raw landing_bucket)

mkdir -p scratch/bench evidence
rm -f scratch/bench/evt-*.json
for i in $(seq 1 "$COUNT"); do
  printf '{"idempotencyKey":"bench-%04d"}\n' "$i" >"scratch/bench/evt-$i.json"
done

aws s3 cp scratch/bench/ "s3://$BUCKET/bench/" --recursive --only-show-errors

for i in $(seq 1 60); do
  n=$(aws dynamodb scan --table-name "$TABLE" \
    --filter-expression 'begins_with(idempotency_key, :p)' \
    --expression-attribute-values '{":p":{"S":"bench-"}}' \
    --select COUNT --query Count --output text)
  echo "poll $i: $n row(s)"
  [ "$n" -ge "$COUNT" ] && break
  sleep 5
done

aws dynamodb scan --table-name "$TABLE" --output json >evidence/bench-aws-raw.json

jq -r '
  def ts:
    (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)
    + ((capture("\\.(?<f>[0-9]+)Z$").f // "0") | "0." + . | tonumber);
  .Items[]
  | (.payload.S | fromjson) as $p
  | select($p.idempotencyKey | startswith("bench-"))
  | (.processed_at.S | ts) - ($p.landedAt | ts)
' evidence/bench-aws-raw.json | sort -n >evidence/bench-aws-latencies.txt

awk '{a[NR]=$1} END {print "n="NR, "p50="a[int(NR*0.50)], "p95="a[int(NR*0.95)]}' \
  evidence/bench-aws-latencies.txt | tee evidence/bench-aws-summary.txt
