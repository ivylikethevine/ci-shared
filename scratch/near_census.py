#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Lists every tracked path two or more local checkouts hold at the same place
and how alike their copies are, to find files that could become shared or
templated.

    scratch/near_census.py [--min N] [--all] [--normalize] [ROOT] [REPO...]

ROOT holds one checkout per repos/<name>.toml (default: this checkout's
parent); REPO names restrict the set. Each path prints with its content groups
(short blob, the repositories holding it) and, for paths with more than one
group, the differing line count of each group against the largest group's
copy, with the maturity order say-hi > sharerr-rs > instadroid breaking ties.
--min N skips paths held by fewer than N checkouts (default 2); --all also
prints byte-identical paths already in files/; --normalize compares after
replacing each repository's names (say-hi, sharerr, instadroid, constricter,
homebrew-tap and their spellings) with __name__, so a file that differs only
by project name scores as identical. Output is plain text; redirect it under
local/.
"""
import difflib
import hashlib
import os
import re
import subprocess
import sys

MATURITY = ["say-hi", "sharerr-rs", "instadroid", "python-constricter", "homebrew-tap"]
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMES = re.compile(
    r"python[-_]constricter|constricter|say[-_]?hi|sharerr[-_]rs|sharerr|instadroid|homebrew[-_]tap",
    re.IGNORECASE,
)


def tracked(repo):
    out = subprocess.run(
        ["git", "-C", repo, "ls-files"], check=True, capture_output=True, text=True
    ).stdout
    return [p for p in out.splitlines() if os.path.isfile(os.path.join(repo, p))]


def blob(path):
    with open(path, "rb") as fh:
        data = fh.read()
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()[:7], data


def main(argv):
    minimum, show_all, normalize, args = 2, False, False, []
    it = iter(argv)
    for a in it:
        if a == "--min":
            minimum = int(next(it))
        elif a == "--all":
            show_all = True
        elif a == "--normalize":
            normalize = True
        else:
            args.append(a)
    root = args[0] if args and os.path.isdir(args[0]) else os.path.dirname(HERE)
    names = args[1:] if args and os.path.isdir(args[0]) else args
    if not names:
        names = [
            f[:-5] for f in sorted(os.listdir(os.path.join(HERE, "repos"))) if f.endswith(".toml")
        ]
    names = [n for n in names if os.path.isdir(os.path.join(root, n, ".git"))]
    rank = {n: i for i, n in enumerate(MATURITY)}
    names.sort(key=lambda n: rank.get(n, len(rank)))

    copies = {}  # path -> {repo: (blob, bytes)}
    for n in names:
        for p in tracked(os.path.join(root, n)):
            b, data = blob(os.path.join(root, n, p))
            if normalize:
                try:
                    data = NAMES.sub("__name__", data.decode()).encode()
                except UnicodeDecodeError:
                    pass
                b = hashlib.sha1(data).hexdigest()[:7]
            copies.setdefault(p, {})[n] = (b, data)

    for p in sorted(copies):
        held = copies[p]
        if len(held) < minimum:
            continue
        groups = {}
        for n, (b, _) in held.items():
            groups.setdefault(b, []).append(n)
        shared = os.path.isfile(os.path.join(HERE, "files", p))
        if len(groups) == 1 and shared and not show_all:
            continue
        ref_blob = max(groups, key=lambda b: (len(groups[b]), -rank.get(groups[b][0], 99)))
        ref = held[groups[ref_blob][0]][1]
        tag = " (files/)" if shared else ""
        print(f"{p}{tag}")
        for b, rs in sorted(groups.items(), key=lambda kv: (kv[0] != ref_blob, kv[1])):
            if b == ref_blob:
                print(f"  {b}  {' '.join(rs)}  [reference, {len(ref.splitlines())} lines]")
                continue
            other = held[rs[0]][1]
            try:
                a, c = ref.decode(), other.decode()
            except UnicodeDecodeError:
                print(f"  {b}  {' '.join(rs)}  [binary]")
                continue
            al, cl = a.splitlines(), c.splitlines()
            sm = difflib.SequenceMatcher(None, al, cl, autojunk=False)
            changed = sum(
                max(i2 - i1, j2 - j1) for op, i1, i2, j1, j2 in sm.get_opcodes() if op != "equal"
            )
            print(f"  {b}  {' '.join(rs)}  [{changed} lines differ of {len(cl)}, ratio {sm.ratio():.2f}]")


if __name__ == "__main__":
    main(sys.argv[1:])
