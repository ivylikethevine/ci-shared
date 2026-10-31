#!/usr/bin/env bash
# scratch/job_durations.py: one row per workflow and job from passing executions,
# a limit suggested only from enough of them, and every page of a run's jobs.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# job <name> <conclusion> <minutes>: a job's JSON, started on the hour
job() {
  printf '{"name":"%s","conclusion":"%s","started_at":"2026-10-01T00:00:00Z","completed_at":"2026-10-01T00:%02d:00Z"}' "$1" "$2" "$3"
}

# owner/a's ci.yml has 5 passing runs of `build` and one of `rare`; its disabled
# old.yml is never asked for.
fixture() {
  t_fake_gh <<EOF
case \$ep in
repos/owner/a/actions/workflows\?*)
  reply '{"workflows":[{"id":1,"path":".github/workflows/ci.yml","state":"active"},
    {"id":2,"path":".github/workflows/old.yml","state":"disabled_manually"}]}' ;;
repos/owner/a/actions/workflows/1/runs*)
  reply '{"workflow_runs":[{"id":1},{"id":2},{"id":3},{"id":4},{"id":5}]}' ;;
repos/owner/a/actions/runs/1/jobs*)
  reply '{"jobs":[$(job build success 2), $(job rare success 1), $(job flaky failure 30)]}' ;;
repos/owner/a/actions/runs/*/jobs*) reply '{"jobs":[$(job build success 7)]}' ;;
repos/owner/gone/*) fail "HTTP 404: gone" ;;
repos/owner/bad/actions/workflows\?*) reply '{"workflows":[{"id":1,"path":"x.yml","state":"active"}]}' ;;
repos/owner/bad/*) fail "HTTP 403: no" ;;
*) fail "HTTP 500: \$ep" ;;
esac
EOF
}

test_rows_from_passing_jobs_with_a_suggested_limit() {
  fixture
  t_run "$REPO_DIR/scratch/job_durations.py" --runs 5 owner/a
  t_rc 0
  t_file "$T/out" "$(
    printf 'owner/a\t.github/workflows/ci.yml\tbuild\t5\t7.0\t7.0\t15\n'
    printf 'owner/a\t.github/workflows/ci.yml\trare\t1\t1.0\t1.0\t-'
  )"
  t_logged 'workflows/1/runs\?status=success&per_page=5$'
  t_not_logged 'workflows/2/runs'
}

test_every_page_of_a_runs_jobs_is_read() {
  t_fake_gh <<'EOF'
one='{"name":"big","conclusion":"success","started_at":"2026-10-01T00:00:00Z","completed_at":"2026-10-01T00:01:00Z"}'
case $ep in
*/workflows\?*) reply '{"workflows":[{"id":1,"path":"ci.yml","state":"active"}]}' ;;
*/workflows/1/runs*) reply '{"workflow_runs":[{"id":1}]}' ;;
*jobs*page=1) reply "{\"jobs\":[$(printf "$one,%.0s" $(seq 1 99))$one]}" ;;
*jobs*page=2) reply "{\"jobs\":[$one]}" ;;
esac
EOF
  t_run "$REPO_DIR/scratch/job_durations.py" owner/a
  t_rc 0
  t_file "$T/out" "$(printf 'owner/a\tci.yml\tbig\t101\t1.0\t1.0\t5')"
}

test_a_5xx_is_retried_and_a_workflow_with_no_runs_prints_nothing() {
  t_fake_gh <<'EOF'
case $ep in
repos/owner/a/*workflows\?*)
  if ! [ -e "$T/flaked" ]; then
    : >"$T/flaked"
    fail "HTTP 502: once"
  fi
  reply '{"workflows":[{"id":1,"path":"ci.yml","state":"active"}]}' ;;
repos/owner/a/*) reply '{"workflow_runs":[]}' ;;
*) fail "HTTP 502: down" ;;
esac
EOF
  t_run "$REPO_DIR/scratch/job_durations.py" owner/a
  t_rc 0
  [ ! -s "$T/out" ] || t_fail "printed: $(cat "$T/out")"
  t_run "$REPO_DIR/scratch/job_durations.py" owner/b
  t_rc 1
  t_eq "$(grep -c 'repos/owner/b/' "$GH_LOG")" 3 "502 tries"
}

test_a_failure_is_reported_and_the_rest_still_print() {
  fixture
  t_run "$REPO_DIR/scratch/job_durations.py" owner/gone owner/bad owner/a
  t_rc 1
  t_out 'HTTP 404: gone' 'HTTP 403: no'
  t_match "$T/out" '^owner/a.*build'
}

t_main
