#!/usr/bin/env bash
# scripts/egress_census.sh and scripts/egress_baseline.sh: the census lists
# each macOS or Windows job with its harden-runner policy, and the baseline
# folds StepSecurity's recorded endpoints into one row per job and endpoint.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# a's workflow: a linux job (left out), a macOS job blocking with two
# endpoints, a matrix job on Windows without harden-runner, and one whose
# harden-runner step has an `if`; b has no workflows.
census_fixture() {
  t_target a dev
  t_target b dev
  mkdir -p "$T/a/.github/workflows" "$T/b"
  cat >"$T/a/.github/workflows/ci.yml" <<'EOF'
jobs:
  linux:
    runs-on: ubuntu-latest
    steps:
      - run: true
  mac:
    runs-on: macos-latest
    steps:
      - uses: step-security/harden-runner@x
        with:
          egress-policy: block
          allowed-endpoints: >
            github.com:443
            api.github.com:443
  win:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest]
    steps:
      - run: true
  cond:
    runs-on: macos-14
    steps:
      - uses: step-security/harden-runner@x
        if: runner.os == 'macOS'
EOF
}

test_census_lists_each_macos_and_windows_job() {
  census_fixture
  t_run "$REPO_DIR/scripts/egress_census.sh"
  t_rc 0
  t_file "$T/tree/local/egress_census.tsv" "$(
    printf 'repo\tworkflow\tjob\trunners\tpolicy\tendpoints\n'
    printf 'a\tci.yml\tmac\tmacos-latest\tblock\t2\n'
    printf 'a\tci.yml\twin\twindows-latest\tnone\t\n'
    printf "a\tci.yml\tcond\tmacos-14\taudit [if runner.os == 'macOS']\t0\n"
  )"
  t_match "$T/out" '^a +ci\.yml +mac +macos-latest +block +2$'
  t_run "$REPO_DIR/scripts/egress_census.sh" b
  t_rc 0
  t_file "$T/tree/local/egress_census.tsv" "$(printf 'repo\tworkflow\tjob\trunners\tpolicy\tendpoints')"
}

# gh lists runs 1 and 2 of ci.yml, or none for any other workflow; curl
# answers each run's endpoint record
baseline_fixture() {
  t_fake gh <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$T/gh.log"
case " $* " in *" -w ci.yml "*) printf '1\n2\n' ;; esac
EOF
  t_fake curl <<'EOF'
#!/usr/bin/env bash
case $4 in
*/runs/1) cat "$T/run1.json" ;;
*/runs/2) cat "$T/run2.json" ;;
esac
EOF
  jq -n '{jobs: [
    {name: "e2e (shard 1/4)", labels: ["macos-latest"], steps: [
      {name: "Run tests", tools: [
        {name: "curl", endpoints: [{domainName: "github.com", port: 443}]},
        {name: "/usr/libexec/trustd", endpoints: [{ipAddress: "17.0.0.1", port: 443}]}]}]},
    {name: "lint", labels: ["ubuntu-latest"], steps: [
      {name: "x", tools: [{name: "curl", endpoints: [{domainName: "linux.example", port: 443}]}]}]}]}' >"$T/run1.json"
  jq -n '{jobs: [
    {name: "e2e (shard 2/4)", labels: ["macos-latest"], steps: [
      {name: "Post Run tests", tools: [
        {name: "curl", endpoints: [{domainName: "github.com", port: 443}]}]}]}]}' >"$T/run2.json"
}

test_baseline_folds_runs_into_one_row_per_endpoint() {
  baseline_fixture
  t_run "$REPO_DIR/scripts/egress_baseline.sh" owner/a ci.yml 2
  t_rc 0
  t_out "# owner/a ci.yml: 2 runs, 2 with macOS/Windows endpoint data"
  t_in "$T/gh.log" "gh run list -R owner/a -w ci.yml -s success -L 2 --json databaseId --jq .[].databaseId"
  t_file "$T/tree/local/egress_baseline/a-ci.tsv" "$(
    printf '1\te2e (shard N)\tmacos-latest\ttests\tcurl\tgithub.com:443\n'
    printf '1\te2e (shard N)\tmacos-latest\ttests\t/usr/libexec/trustd\t17.0.0.1:443\n'
    printf '2\te2e (shard N)\tmacos-latest\ttests\tcurl\tgithub.com:443\n'
  )"
  [ "$(grep -c . "$T/out")" = 3 ] || t_fail "wanted a header and two rows"
  # github.com's row, then trustd's
  t_match "$T/out" '^e2e \(shard N\) +macos-latest +github\.com:443 +2/2 +tests$' \
    '^e2e \(shard N\) +macos-latest +17\.0\.0\.1:443 +1/2 +os +tests$'
}

test_baseline_needs_a_successful_run() {
  baseline_fixture
  t_run "$REPO_DIR/scripts/egress_baseline.sh" owner/a other.yml
  t_rc 1
  t_out "no successful other.yml runs in owner/a"
}

t_main
