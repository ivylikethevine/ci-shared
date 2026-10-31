#!/usr/bin/env bash
# scripts/retried_timeouts.py: tells a timeout from another cancel by its
# annotation, counts retries without copied jobs, appends each new job once,
# and reads past the runs search limit, a second page and a 5xx.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# job <id> <name> <attempt> <conclusion> <started minute> <completed minute>
# [steps]: a job's JSON, whose failed step is named "stuck" unless it passed.
# Its steps end a minute after it starts and the last has no end; steps
# `finished` adds an ended `Complete job`, and `none` leaves none ended.
job() {
  local step='[]' end
  end="$(printf '2026-10-01T00:%02d:00Z' "$(($5 + 1))")"
  [ "$4" = success ] ||
    step='[{"name":"passed","conclusion":"success","completed_at":"'$end'"},{"name":"stuck","conclusion":"failure","completed_at":null}]'
  case ${7:-} in
  finished) step='[{"name":"stuck","conclusion":"failure","completed_at":"'$end'"},{"name":"Complete job","conclusion":"success","completed_at":"'$end'"}]' ;;
  none) step='[{"name":"Complete job","conclusion":null,"completed_at":null}]' ;;
  esac
  printf '{"id":%s,"name":"%s","run_attempt":%s,"conclusion":"%s","labels":["ubuntu-26.04"],' "$1" "$2" "$3" "$4"
  printf '"started_at":"2026-10-01T00:%02d:00Z","completed_at":"2026-10-01T00:%02d:00Z","steps":%s}' "$5" "$6" "$step"
}

# run 1 of owner/a holds every shape of job; run 2 was not retried, so its jobs
# are never asked for. Job 11 hit its limit, 21 and 22 twice, 31 a step's limit;
# 41 was cancelled by hand, 51 timed out and was never passed, 61 timed out
# three times, 71 reports timed_out with no annotation, and 81 is copied into
# attempt 2 unchanged before passing in attempt 3.
fixture() {
  t_fake_gh <<EOF
case \$ep in
'user/repos?affiliation=owner&per_page=100&page=1')
  reply '[{"name":"a","full_name":"owner/a","fork":false,"archived":false},
    {"name":"forked","full_name":"owner/forked","fork":true,"archived":false},
    {"name":"old","full_name":"owner/old","fork":false,"archived":true}]' ;;
repos/owner/a/actions/runs\?*per_page=1) reply '{"total_count":2}' ;;
repos/owner/a/actions/runs\?*)
  reply '{"workflow_runs":[
    {"id":1,"name":"CI","event":"push","head_branch":"dev","head_sha":"abc","html_url":"https://x/1","run_attempt":4},
    {"id":2,"name":"CI","event":"push","head_branch":"dev","head_sha":"abc","html_url":"https://x/2","run_attempt":1}]}' ;;
repos/owner/a/actions/runs/1/attempts/*/jobs\?*)
  n=\${ep#*attempts/}
  jq -c --argjson n "\${n%%/*}" '{jobs: [.jobs[] | select(.run_attempt == \$n)]}' <<<'{"jobs":[
    $(job 11 one 1 cancelled 0 10), $(job 12 one 2 success 20 21),
    $(job 21 two 1 cancelled 0 10), $(job 22 two 2 cancelled 20 30), $(job 23 two 3 success 40 41),
    $(job 31 step 1 failure 0 5 finished), $(job 32 step 2 success 20 21),
    $(job 41 hand 1 cancelled 0 1), $(job 42 hand 2 success 20 21),
    $(job 51 never 1 cancelled 0 10), $(job 52 never 2 failure 20 21),
    $(job 61 many 1 cancelled 0 1), $(job 62 many 2 cancelled 2 3), $(job 63 many 3 cancelled 4 5), $(job 64 many 4 success 6 7),
    $(job 71 plain 1 timed_out 0 10 none), $(job 72 plain 2 success 20 21),
    $(job 81 copy 1 cancelled 0 10), $(job 82 copy 2 cancelled 0 10), $(job 83 copy 3 success 20 21),
    $(job 91 skip 1 skipped 0 0), $(job 92 skip 2 success 20 21)]}' ;;
repos/owner/a/check-runs/11/annotations* | repos/owner/a/check-runs/21/annotations* | repos/owner/a/check-runs/22/annotations* | \
  repos/owner/a/check-runs/51/annotations* | repos/owner/a/check-runs/6?/annotations* | repos/owner/a/check-runs/81/annotations*)
  reply '[{"message":null},{"message":"The job has exceeded the maximum execution time of 10m0s"}]' ;;
repos/owner/a/check-runs/31/annotations*)
  reply '[{"message":"The action '"'"'stuck'"'"' has timed out after 5 minutes."}]' ;;
repos/owner/a/check-runs/*/annotations*) reply '[]' ;;
*) fail "HTTP 404: \$ep" ;;
esac
EOF
}

scan() {
  t_run "$REPO_DIR/scripts/retried_timeouts.py" --log "$T/log/x.jsonl" "$@"
}

test_logs_each_timeout_that_passed_within_the_retries() {
  fixture
  scan --since 2026-10-01
  t_rc 0
  t_not_logged 'runs/2/attempts|repos/owner/(forked|old)/'
  t_logged 'runs\?created=2026-10-01T00:00:00Z\.\.'
  t_eq "$(jq -r .job "$T/log/x.jsonl" | LC_ALL=C sort | xargs)" "copy one plain step two" jobs
  t_eq "$(jq -c 'select(.job == "two") | [.retries, .timeouts, .passed_attempt, .failed_minutes, .delay_minutes, .step, .message]' "$T/log/x.jsonl")" \
    '[2,2,3,20.0,41.0,"stuck","The job has exceeded the maximum execution time of 10m0s"]' two
  t_eq "$(jq -c 'select(.job == "copy") | [.retries, .timeouts, .passed_attempt, .failed_minutes]' "$T/log/x.jsonl")" '[1,1,3,10.0]' copy
  t_eq "$(jq -r 'select(.job == "plain") | .message' "$T/log/x.jsonl")" "conclusion: timed_out" plain
  t_eq "$(jq -c 'select(.job == "one") | [.job_id, .outcome, .active_minutes, .recorded_minutes]' "$T/log/x.jsonl")" '[11,"stopped",1.0,10.0]' stopped
  t_eq "$(jq -c 'select(.job == "step") | [.outcome, .active_minutes, .recorded_minutes]' "$T/log/x.jsonl")" '["finished",1.0,5.0]' finished
  t_eq "$(jq -c 'select(.job == "plain") | [.outcome, .active_minutes, .recorded_minutes]' "$T/log/x.jsonl")" '["no steps",0.0,10.0]' none
  t_eq "$(jq -r 'select(.job == "one") | [.repository, .run_id, .workflow, .event, .branch, .sha, .runner, .url] | @tsv' "$T/log/x.jsonl")" \
    "$(printf 'owner/a\t1\tCI\tpush\tdev\tabc\tubuntu-26.04\thttps://x/1')" fields
  t_match "$T/out" '^owner/a: 1 retried runs of 2$' '^2026-10-01T00:00:00Z +a +CI +one +1 +1\.0 +10\.0 +stopped$' '^5 new, 5 in ' '^a +5 +1 +3 +1 +'
}

test_a_second_scan_adds_nothing_and_keeps_the_totals() {
  fixture
  scan --since 2026-10-01
  cp "$T/log/x.jsonl" "$T/before"
  scan --since 2026-10-01 a
  t_rc 0
  cmp "$T/before" "$T/log/x.jsonl" || t_fail "the log changed"
  t_match "$T/out" '^0 new, 5 in ' '^a +5 +1 +3 +1 +'
  t_no_out 'Timed out (UTC)'
}

test_max_retries_widens_and_narrows_the_cut() {
  fixture
  scan --since 2026-10-01 --max-retries 3
  t_eq "$(jq -c 'select(.job == "many") | [.retries, .timeouts]' "$T/log/x.jsonl")" '[3,3]' many
  rm "$T/log/x.jsonl"
  scan --since 2026-10-01 --max-retries 1
  t_eq "$(jq -r .job "$T/log/x.jsonl" | LC_ALL=C sort | xargs)" "copy one plain step" jobs
}

test_default_window_and_no_runs_print_no_table() {
  t_fake_gh <<'EOF'
case $ep in
user/repos*) reply '[{"name":"a","full_name":"owner/a","fork":false,"archived":false}]' ;;
*per_page=1) reply '{"total_count":0}' ;;
*) reply '{"workflow_runs":[]}' ;;
esac
EOF
  scan
  t_rc 0
  t_file "$T/out" "$(printf 'owner/a: 0 retried runs of 0\n0 new, 0 in %s' "$T/log/x.jsonl")"
  t_logged "created=$(date -u -d '30 days ago' +%Y-%m-%d)T"
}

test_a_big_span_is_halved_and_every_page_read() {
  t_fake_gh <<'EOF'
run() { printf '{"id":%s,"run_attempt":1}' "$1"; }
case $ep in
user/repos*) reply '[{"name":"a","full_name":"owner/a","fork":false,"archived":false}]' ;;
*per_page=1)
  if ! [ -e "$T/halved" ]; then
    : >"$T/halved"
    reply '{"total_count":1001}'
  else
    reply '{"total_count":3}'
  fi ;;
*created=2026-10-01T00:00:00Z*page=1)
  ids="$(seq -s, 1 100 | sed -E 's/[0-9]+/{"id":&,"run_attempt":1}/g')"
  reply "{\"workflow_runs\":[$ids]}" ;;
*created=2026-10-01T00:00:00Z*page=2) reply "{\"workflow_runs\":[$(run 101)]}" ;;
*) reply "{\"workflow_runs\":[$(run 102)]}" ;;
esac
EOF
  scan --since 2026-10-01
  t_rc 0
  t_out 'owner/a: 0 retried runs of 102'
  t_logged 'created=2026-10-01T00:00:00Z.*page=2'
}

test_a_5xx_is_retried_and_a_failed_repo_does_not_stop_the_others() {
  t_fake_gh <<'EOF'
case $ep in
user/repos*)
  reply '[{"name":"a","full_name":"owner/a","fork":false,"archived":false},
    {"name":"b","full_name":"owner/b","fork":false,"archived":false},
    {"name":"c","full_name":"owner/c","fork":false,"archived":false},
    {"name":"d","full_name":"owner/d","fork":false,"archived":false}]' ;;
repos/owner/a/*) fail "HTTP 403: no" ;;
repos/owner/b/*) fail "HTTP 502: down" ;;
repos/owner/c/*per_page=1)
  if ! [ -e "$T/flaked" ]; then
    : >"$T/flaked"
    fail "HTTP 502: once"
  fi
  reply '{"total_count":0}' ;;
*per_page=1) reply '{"total_count":0}' ;;
*) reply '{"workflow_runs":[]}' ;;
esac
EOF
  scan --since 2026-10-01
  t_rc 1
  t_out 'HTTP 403: no' 'HTTP 502: down' 'owner/c: 0 retried runs of 0' 'owner/d: 0 retried runs of 0'
  # the 403 once, the persistent 502 three times, the passing retry twice
  t_eq "$(grep -c 'repos/owner/a/' "$GH_LOG")" 1 "403 tries"
  t_eq "$(grep -c 'repos/owner/b/' "$GH_LOG")" 3 "502 tries"
  t_eq "$(grep -c 'repos/owner/c/.*per_page=1$' "$GH_LOG")" 2 "flake tries"
}

test_an_unreadable_run_does_not_stop_its_repo() {
  t_fake_gh <<EOF
case \$ep in
user/repos*) reply '[{"name":"a","full_name":"owner/a","fork":false,"archived":false}]' ;;
*actions/runs\?*per_page=1) reply '{"total_count":2}' ;;
*actions/runs\?*)
  reply '{"workflow_runs":[
    {"id":1,"name":"CI","event":"push","head_branch":"dev","head_sha":"abc","html_url":"https://x/1","run_attempt":2},
    {"id":2,"name":"CI","event":"push","head_branch":"dev","head_sha":"abc","html_url":"https://x/2","run_attempt":2}]}' ;;
*runs/1/attempts/*) fail "HTTP 403: run one" ;;
*runs/2/attempts/1/*) reply '{"jobs":[$(job 11 one 1 cancelled 0 10)]}' ;;
*runs/2/attempts/2/*) reply '{"jobs":[$(job 12 one 2 success 20 21)]}' ;;
*annotations*) reply '[{"message":"The job has exceeded the maximum execution time of 10m0s"}]' ;;
esac
EOF
  scan --since 2026-10-01
  t_rc 1
  t_out 'HTTP 403: run one'
  t_eq "$(jq -r .run_id "$T/log/x.jsonl")" 2 "logged run"
}

test_an_unknown_repo_or_a_failed_listing_stops_the_scan() {
  fixture
  scan nosuch owner/a
  t_rc 1
  t_out 'not an owned repository: nosuch'
  [ ! -e "$T/log/x.jsonl" ] || t_fail "the log was written"
  t_fake_gh <<'EOF'
fail "HTTP 401: bad credentials"
EOF
  scan
  t_rc 1
  t_out 'HTTP 401: bad credentials'
}

t_main
