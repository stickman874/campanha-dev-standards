#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
S=$PWD/plugins/core/scripts/nightly.sh
W=$(mktemp -d); mkdir -p "$W/bin"
for t in semgrep trivy; do printf '#!/usr/bin/env bash\necho "%s: 1 finding"\nexit 1\n' "$t" > "$W/bin/$t"; chmod +x "$W/bin/$t"; done
printf '#!/usr/bin/env bash\necho "socket: ok"\n' > "$W/bin/npx"; chmod +x "$W/bin/npx"
cat > "$W/bin/opencode" <<'EOF'
#!/usr/bin/env bash
agent=; while [ $# -gt 0 ]; do case $1 in --agent) agent=$2; shift;; esac; shift; done
case $agent in
  reviewer) jq -nc '{type:"text",part:{text:"{\"verdict\":\"block\",\"findings\":[{\"severity\":\"medium\",\"file\":\"src/a.ts\",\"line\":1,\"what\":\"w\",\"fix\":\"f\"}]}"}}';;
  docs)     echo "- src/a.ts: a" >> docs/dev/architecture.md; jq -nc '{type:"tool_use",part:{tool:"edit"}}'; jq -nc '{type:"text",part:{text:"docs updated"}}';;
esac
echo '{"type":"step_finish","part":{"tokens":{"total":1},"cost":0}}'
EOF
chmod +x "$W/bin/opencode"; export PATH="$W/bin:$PATH"
git init -q --bare "$W/origin"; git clone -q "$W/origin" "$W/repo" 2>/dev/null; cd "$W/repo"; git checkout -q -b main
mkdir -p .opencode/agents docs/dev/reviews src scripts; cp "$OLDPWD"/template/.opencode/agents/{reviewer,docs}.md .opencode/agents/; cp "$OLDPWD"/template/scripts/review.sh scripts/
echo "# arch" > docs/dev/architecture.md; touch docs/dev/reviews/.gitkeep; echo a > src/a.ts
printf 'backend: claude\n' > .copier-answers.yml
git add -A; git -c user.name=t -c user.email=t@t commit -qm init; git push -q origin main
export OPENCODE_SH=$OLDPWD/plugins/core/scripts/opencode.sh GIT_AUTHOR_NAME=n GIT_AUTHOR_EMAIL=n@n GIT_COMMITTER_NAME=n GIT_COMMITTER_EMAIL=n@n
day=$(date -u +%F)
out=$(bash "$S" "$W/repo" 2>&1); code=$?
assert_eq 0 "$code" "first run exits 0"
git fetch -q origin "nightly/$day" && echo "  ok  nightly branch pushed" || { echo "  FAIL branch not pushed"; FAILS=$((FAILS+1)); }
rep=$(git show "origin/nightly/$day:docs/dev/reviews/$day.md")
assert_contains "$rep" 'semgrep: 1 finding' "semgrep output in report"; assert_contains "$rep" 'trivy: 1 finding' "trivy output in report"; assert_contains "$rep" 'socket: ok' "socket output in report"
assert_contains "$rep" '\[medium\] src/a.ts:1 - w - f' "review findings in report"
assert_contains "$rep" 'zero-data-retention' "ZDR warning when never confirmed"
assert_contains "$(git show "origin/nightly/$day:docs/dev/architecture.md")" 'src/a.ts' "docs agent edits committed"
assert_eq "$(git rev-parse origin/main)" "$(cat .git/nightly-last)" "last reviewed sha stored"
out=$(bash "$S" "$W/repo" 2>&1); code=$?; assert_eq 0 "$code" "no new commits: exit 0"; assert_contains "$out" 'no new commits' "says so"
git checkout -q main; echo b >> src/a.ts; git commit -qam more; git push -q origin main; date -u +%F > docs/dev/reviews/.zdr-confirmed; git add -A; git commit -qm zdr; git push -q origin main
out=$(bash "$S" "$W/repo" 2>&1); code=$?; assert_eq 0 "$code" "second run exits 0"
rep=$(git show "origin/nightly/$day:docs/dev/reviews/$day.md"); printf '%s' "$rep" | grep -q 'zero-data-retention' && { echo "  FAIL ZDR warning despite fresh confirmation"; FAILS=$((FAILS+1)); } || echo "  ok  no ZDR warning when confirmed"
git checkout -q main; echo c >> src/a.ts; git commit -qam c; git push -q origin main
rm "$W/bin/semgrep"
# strip any real semgrep from PATH too (a dev/server box may have one via mise; removing only the fake would then be masked)
clean_path=$(IFS=:; for d in $PATH; do [ -x "$d/semgrep" ] && continue; printf '%s:' "$d"; done)
echo "manual SKIP_REVIEW entry" > docs/dev/reviews/skipped.log
out=$(PATH="${clean_path%:}" bash "$S" "$W/repo" 2>&1); code=$?; assert_eq 1 "$code" "missing tool: exit 1"; assert_contains "$(git show "origin/nightly/$day:docs/dev/reviews/$day.md")" 'semgrep: missing' "missing tool named in report"
assert_contains "$(cat docs/dev/reviews/skipped.log)" 'manual SKIP_REVIEW entry' "skipped.log kept after a failed (rc=1) run"
printf '#!/usr/bin/env bash\necho "semgrep: 1 finding"\nexit 1\n' > "$W/bin/semgrep"; chmod +x "$W/bin/semgrep"
git checkout -q main; echo d >> src/a.ts; git commit -qam d; git push -q origin main
out=$(bash "$S" "$W/repo" 2>&1); code=$?; assert_eq 0 "$code" "run with semgrep back exits 0"
[ -s docs/dev/reviews/skipped.log ] && { echo "  FAIL skipped.log not truncated after a successful run"; FAILS=$((FAILS+1)); } || echo "  ok  skipped.log truncated after a successful run"

# runner: plugin's own when the repo predates 0.5.0, the repo's scripts/opencode.sh once it ships one
git checkout -q main; echo f >> src/a.ts; git commit -qam f; git push -q origin main
out=$(env -u OPENCODE_SH bash "$S" "$W/repo" 2>&1); code=$?
assert_eq 0 "$code" "no repo runner: falls back to the plugin's"
export MARK="$W/mark" REAL="$OLDPWD/plugins/core/scripts/opencode.sh"
git checkout -q main; printf '#!/usr/bin/env bash\ntouch "$MARK"; exec bash "$REAL" "$@"\n' > scripts/opencode.sh; echo g >> src/a.ts; git add -A; git commit -qm g; git push -q origin main
rm -f "$MARK"; out=$(env -u OPENCODE_SH bash "$S" "$W/repo" 2>&1); code=$?
assert_eq 0 "$code" "repo runner run exits 0"
[ -e "$MARK" ] && echo "  ok  repo's scripts/opencode.sh used" || { echo "  FAIL repo runner not used"; FAILS=$((FAILS+1)); }

git checkout -q main; echo e >> src/a.ts; git rm -q scripts/review.sh; git commit -qam 'drop review.sh'; git push -q origin main
out=$(bash "$S" "$W/repo" 2>&1); code=$?
assert_eq 1 "$code" "review.sh missing: exit 1"
assert_contains "$(git show "origin/nightly/$day:docs/dev/reviews/$day.md")" 'review: missing' "missing review.sh named in report"

assert_exit 2 bash "$S" /nonexistent
assert_exit 1 bash "$OLDPWD/deploy/nightly/run-all.sh" /nonexistent-list-$$
cd - >/dev/null; rm -rf "$W"; finish
