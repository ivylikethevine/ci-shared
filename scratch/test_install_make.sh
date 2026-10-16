#!/usr/bin/env bash
# Runs setup-tool/install.sh's `make` kind from two copies of this repository
# on a good source tarball, an empty one and a corrupt one, served from
# file:// URLs, and prints each run's output and exit status to compare.
#
#   old="$(mktemp -d)"; git archive HEAD | tar -x -C "$old"
#   scratch/test_install_make.sh "$old" .
#
# Needs bash, curl, tar, make and sha256sum; touches nothing outside its
# temporary directory.
set -u
W="$(mktemp -d "${TMPDIR:-/tmp}/inst.XXXXXX")"
trap 'case "$W" in */inst.??????) rm -r -- "$W" ;; esac' EXIT
mkdir -p "$W/pkg/mytool-1.0"
cat >"$W/pkg/mytool-1.0/configure" <<'EOF'
#!/bin/sh
printf 'all:\n\tprintf "#!/bin/sh\\necho mytool 1.0\\n" >mytool && chmod +x mytool\n' >Makefile
EOF
chmod +x "$W/pkg/mytool-1.0/configure"
tar -czf "$W/good.tar.gz" -C "$W/pkg" mytool-1.0
tar -czf "$W/empty.tar.gz" -T /dev/null
printf 'not a tarball' >"$W/bad.tar.gz"
for t in good empty bad; do
  sha=$(sha256sum "$W/$t.tar.gz" | cut -d' ' -f1)
  printf 'mytool|1.0|make|file://%s|--version|-||%s\n' "$W/$t.tar.gz" "$sha" >"$W/$t.txt"
done
for v in old new; do
  R=$2
  [ $v = old ] && R=$1
  for t in good empty bad; do
    echo "== $v $t"
    CI_TOOLS_TXT="$W/$t.txt" CI_TOOL=mytool CI_TOOL_BIN_DIR="$W/bin-$v-$t" \
      bash "$R/files/.github/actions/setup-tool/install.sh" install 2>&1 | sed "s|$W|W|g"
    echo "rc=${PIPESTATUS[0]}"
  done
done
