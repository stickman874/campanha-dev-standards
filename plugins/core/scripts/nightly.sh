#!/usr/bin/env bash
# Night shift for one adopted repo checkout (runs on the server from a systemd timer; see deploy/nightly/).
#   nightly.sh <repo>   needs: git with push rights, opencode login, semgrep, trivy, npx (Socket), jq.
# Reviews everything pushed to origin/main since the last run, runs the scanners, refreshes docs with the `docs` agent,
# commits to branch nightly/<date> and pushes only that branch. Report: docs/dev/reviews/<date>.md.
# Exit 0 every step ran (findings do not fail the run) · 1 a step could not run (tool missing, reviewer unavailable, push failed) · 2 usage.
set -u
CAP=100000   # like review.sh: the docs-agent prompt is one argv to opencode.sh, capped well under the kernel's 131072-byte MAX_ARG_STRLEN
repo=${1:-}; git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "usage: nightly.sh <repo>" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd); export OPENCODE_SH=${OPENCODE_SH:-$here/opencode.sh}
cd "$repo" || exit 2
day=$(date -u +%F); branch=nightly/$day; report=docs/dev/reviews/$day.md; state=$(git rev-parse --git-dir)/nightly-last
git fetch -q origin main && git checkout -q -B "$branch" origin/main && git clean -fdq docs -e 'docs/dev/reviews/skipped.log' -e 'docs/dev/reviews/.zdr-confirmed' || { echo "nightly: fetch or checkout failed" >&2; exit 1; }
to=$(git rev-parse origin/main); from=$(cat "$state" 2>/dev/null || git rev-parse --verify -q "origin/main~20" 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)
[ "$from" != "$to" ] || { echo "nightly: no new commits since $from"; exit 0; }
mkdir -p docs/dev/reviews; rc=0
step() {   # step <name> <command...>: appends a section; a missing tool is named and fails the run, tool findings do not
  echo; echo "## $1"; echo; shift
  if ! command -v "$1" >/dev/null; then echo "$1: missing"; rc=1; return; fi
  echo '```'; timeout 900 "$@" 2>&1 | tail -n 200; echo '```'
}
{
  echo "# Night shift $day"; echo; echo "Range: \`$from..$to\` ($(git rev-list --count "$from..$to" 2>/dev/null || echo '?') commits)"
  zdr=$(cat docs/dev/reviews/.zdr-confirmed 2>/dev/null || echo 1970-01-01)
  [ $(( ( $(date +%s) - $(date -d "$zdr" +%s 2>/dev/null || echo 0) ) / 86400 )) -le 35 ] || { echo; echo "> WARNING: opencode go zero-data-retention for DeepSeek last confirmed $zdr. Check https://opencode.ai/docs/go/ and write today's date to docs/dev/reviews/.zdr-confirmed."; }
  echo; echo "## Pushed without review"; echo; { cat docs/dev/reviews/skipped.log 2>/dev/null || true; } | grep . || echo "none"
  step semgrep semgrep scan --config p/default --error --quiet --metrics=off
  step trivy trivy fs --scanners vuln,secret --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 --quiet --skip-dirs node_modules --skip-files ".env*,**/.env*" .
  step socket npx --yes socket@1 scan create .
  echo; echo "## Review"; echo; echo '```'
  if [ -f scripts/review.sh ]; then
    printf 'refs/heads/main %s refs/heads/main %s\n' "$to" "$from" | REVIEW_TIMEOUT=${NIGHTLY_REVIEW_TIMEOUT:-1500} timeout 1800 bash scripts/review.sh --all 2>&1; r=$?   # the night has time: one big range may need >5 min of file reads
    [ "$r" -gt 1 ] && rc=1   # r=1 means the reviewer blocked findings, not a failed step
  else
    echo "review: missing"; rc=1
  fi
  echo '```'
} > "$report" 2>&1
grep -qE 'reviewer unavailable|opencode\.sh not found|cannot diff|no valid JSON|No such file' "$report" && rc=1
body=$({ printf '%s\n\nDiff (for context, read the files themselves when unsure):\n%s' "$(git diff --name-only "$from" "$to")" "$(git diff "$from" "$to" --)" 2>/dev/null; } | head -c "$CAP")
out=$(bash "$OPENCODE_SH" "$PWD" docs <<EOF
Refresh the documentation for these files changed between $from and $to:
$body
EOF
); d=$?; { echo; echo "## Docs"; echo; echo '```'; echo "$out" | tail -n 60; echo '```'; } >> "$report"; [ $d -eq 0 ] || rc=1
git add -A docs; git add CHANGELOG.md 2>/dev/null; git -c user.name="night shift" -c user.email="nightly@localhost" commit -qm "docs: night shift $day" 2>/dev/null || true
if git push -q -f origin "$branch"; then
  echo "$to" > "$state"   # advance once the report is on origin, even on rc=1: the report and systemd carry the failure; redoing a giant range every night would wedge the job
  [ $rc -eq 0 ] && { : > docs/dev/reviews/skipped.log 2>/dev/null || true; }
else echo "nightly: push failed" >&2; rc=1; fi
echo "nightly: $branch pushed, report $report, rc=$rc"; exit $rc
