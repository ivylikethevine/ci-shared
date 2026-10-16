#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs check_tool_versions.sh, scan_pinned_images.sh and lint_workflows.sh from
# two copies of this repository over the same fixtures, with a fake curl that
# logs and fails and a fake trivy, and diffs their output: a refactor of
# files/ should change nothing but curl's argument order or the report path.
#
#   old="$(mktemp -d)"; git archive HEAD | tar -x -C "$old"
#   scratch/compare_shared_scripts.sh "$old" .
#
# Needs bash, git, jq and yq; the new copy's output lands in local/compare.out.
set -uo pipefail
OLD=$1 NEW=$2
work="$(mktemp -d "${TMPDIR:-/tmp}/cmpfx.XXXXXX")"
trap 'case "$work" in */cmpfx.??????) rm -r -- "$work" ;; esac' EXIT

mkdir -p "$work/bin"
cat >"$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CURL_LOG"
exit 22
EOF
# fake trivy: a.json for pinned digests, b.json for tags; counts per image name
cat >"$work/bin/trivy" <<'EOF'
#!/usr/bin/env bash
[ "$2" = --download-db-only ] && exit 0
out="" ref="${@: -1}"
while [ $# -gt 0 ]; do [ "$1" = --output ] && out=$2; shift; done
case "$ref" in
*alpine*@*) ids='["CVE-1","CVE-2"]' ;;
*alpine*) ids='["CVE-1"]'; dig=sha256:$(printf 'b%.0s' {1..64}) ;;
*debian*@*) ids='["CVE-9"]' ;;
*debian*) ids='["CVE-9"]'; dig=sha256:$(printf 'c%.0s' {1..64}) ;;
*nodata*) echo '{"Results":null}' >"$out"; exit 0 ;;
*broken*) exit 1 ;;
*) ids='[]' ;;
esac
jq -n --argjson ids "$ids" --arg d "${dig:-}" \
  '{Metadata: {RepoDigests: (if $d == "" then [] else ["x@" + $d] end)},
    Results: [{Vulnerabilities: [$ids[] | {VulnerabilityID: .}]}]}' >"$out"
EOF
chmod +x "$work/bin/"*

d64=$(printf 'a%.0s' {1..64})
fixture() { # fixture <dir> <ci-shared>
  local r=$1 src=$2
  mkdir -p "$r/.github/scripts" "$r/.github/actions/setup-tool" "$r/.github/workflows" "$r/svc"
  cp "$src"/files/.github/scripts/{lib.sh,check_tool_versions.sh,scan_pinned_images.sh,lint_workflows.sh} "$r/.github/scripts/"
  cp "$src"/files/.github/actions/setup-tool/{lib.sh,install.sh} "$r/.github/actions/setup-tool/"
  cat >"$r/.github/actions/setup-tool/tools.txt" <<EOF
cb|1.2|raw|https://example.invalid/%v||gitlab:salsa.debian.org/debian%2Fdevscripts|v|$d64
gl|3.4|raw|https://example.invalid/%v||gitlab:group%2Fname||$d64
gh|5.6|raw|https://example.invalid/%v||github:o/r|v|$d64
EOF
  printf 'FROM alpine:3.20@sha256:%s\nFROM --platform=linux/amd64 debian:12@sha256:%s AS b\nFROM b\nFROM ubuntu:24.04\n' "$d64" "$d64" >"$r/Dockerfile"
  printf 'services:\n  a:\n    image: "nodata:1@sha256:%s"\n  b:\n    image: broken:2@sha256:%s\n  c:\n    image: ghcr.io/x/y:1@sha256:%s\n  d:\n    image: redis:7\n' "$d64" "$d64" "$d64" >"$r/svc/compose.yml"
  cat >"$r/.github/workflows/sparse.yml" <<'EOF'
on: push
permissions: {}
jobs:
  a:
    timeout-minutes: 1
    steps:
      - uses: step-security/harden-runner@0000000000000000000000000000000000000000 # v1.0.0
        with: {egress-policy: block}
      - uses: actions/checkout@0000000000000000000000000000000000000000 # v1.0.0
        with:
          persist-credentials: false
          sparse-checkout: |
            .github/actions/ok
            /scripts/
      - uses: ./.github/actions/ok/sub
      - uses: ./.github/actions/missing
      - uses: ./scripts
  b:
    timeout-minutes: 1
    steps:
      - uses: step-security/harden-runner@0000000000000000000000000000000000000000 # v1.0.0
        with: {egress-policy: audit}
      - uses: actions/checkout@0000000000000000000000000000000000000000 # v1.0.0
        with: {persist-credentials: false}
      - uses: ./.github/actions/anything
  c:
    timeout-minutes: 1
    steps:
      - uses: step-security/harden-runner@0000000000000000000000000000000000000000 # v1.0.0
        with: {egress-policy: audit}
      - uses: actions/checkout@0000000000000000000000000000000000000000 # v1.0.0
        with: {persist-credentials: false, sparse-checkout: ""}
      - uses: ./.github/actions/x
EOF
  git -C "$r" init -q && git -C "$r" add -A
}

for v in old new; do
  src=$OLD
  [ $v = new ] && src=$NEW
  r="$work/$v"
  fixture "$r" "$src"
  {
    echo "### check_tool_versions"
    CURL_LOG="$work/curl.$v" PATH="$work/bin:$PATH" GH_TOKEN=tok TOOL_COOLDOWN_DAYS=7 \
      "$r/.github/scripts/check_tool_versions.sh"
    echo "rc=$?"
    echo "### curl calls"
    cat "$work/curl.$v"
    echo "### scan_pinned_images"
    SCAN_REPORT="$work/report.$v" PATH="$work/bin:$PATH" "$r/.github/scripts/scan_pinned_images.sh" | sed "s|$r|R|g"
    echo "rc=$?"
    cat "$work/report.$v"
    echo "### lint_workflows"
    "$r/.github/scripts/lint_workflows.sh" .github/workflows/sparse.yml "$NEW"/files/.github/workflows/*.yml "$NEW"/.github/workflows/*.yml 2>&1 | sed "s|$NEW|N|g"
    echo "rc=$?"
    echo "### lint_workflows without yq"
    mkdir -p "$work/nobin" && ln -sf "$(command -v dirname)" "$work/nobin/dirname"
    PATH="$work/nobin" "$BASH" "$r/.github/scripts/lint_workflows.sh" 2>&1
    echo "rc=$?"
  } >"$work/out.$v" 2>&1
done
diff "$work/out.old" "$work/out.new" && echo "IDENTICAL ($(wc -l <"$work/out.new") lines)"
mkdir -p "$NEW/local" && cp "$work/out.new" "$NEW/local/compare.out"
