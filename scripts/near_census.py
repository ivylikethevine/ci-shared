#!/usr/bin/env python3
"""Lists every tracked path two or more local checkouts hold at the same place
and how alike their copies are, to find files that could become shared or
templated.

    scripts/near_census.py [--min N] [--all] [--normalize] [ROOT] [REPO...]

ROOT holds one checkout per repos/<name>.toml (default: this checkout's
parent); REPO names restrict the set. Each path prints with its content groups
(short blob, the repositories holding it) and, for paths with more than one
group, the differing line count of each group against the largest group's
copy, with the maturity order say-hi > sharerr-rs > instadroid breaking ties.
--min N skips paths held by fewer than N checkouts (default 2); --all also
prints byte-identical paths already in files/; --normalize compares after
replacing each repos/<name>.toml's name and SPELLINGS with __name__, so a file
that differs only by project name scores as identical. Output is plain text;
redirect it under local/. CI_SHARED_DIR, as for scripts/, names the tree whose repos/ and files/
it reads (default: this checkout).
"""
import difflib
import hashlib
import os
import re
import subprocess
import sys
from collections.abc import Iterator
from io import BufferedReader
from typing import TypeAlias

# one checkout's copy of a path: its short blob and its bytes
Copy: TypeAlias = tuple[str, bytes]
MATURITY: list[str] = ["say-hi", "sharerr-rs", "instadroid", "python-constricter", "homebrew-tap"]
HERE: str = os.environ.get("CI_SHARED_DIR") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# short forms a target's own name does not cover
SPELLINGS: list[str] = ["constricter", "sayhi", "sharerr"]


def targets() -> list[str]:
    return [
        f[:-5]
        for f in sorted(os.listdir(os.path.join(HERE, "repos")))
        if f.endswith(".toml") and not f.startswith("_")
    ]


def name_pattern() -> re.Pattern[str]:
    # longest first, so a short form never leaves the rest of a full name behind
    spellings: list[str] = sorted([*targets(), *SPELLINGS], key=len, reverse=True)
    return re.compile(
        "|".join(re.escape(s).replace(r"\-", "[-_]") for s in spellings),
        re.IGNORECASE,
    )


def tracked(repo: str) -> list[str]:
    out: str = subprocess.run(
        ["git", "-C", repo, "ls-files"], check=True, capture_output=True, text=True
    ).stdout
    return [p for p in out.splitlines() if os.path.isfile(os.path.join(repo, p))]


def blob(path: str) -> tuple[str, bytes]:
    fh: BufferedReader
    with open(path, "rb") as fh:
        data: bytes = fh.read()
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()[:7], data


def main(argv: list[str]) -> None:
    minimum: int
    show_all: bool
    normalize: bool
    args: list[str]
    minimum, show_all, normalize, args = 2, False, False, []
    it: Iterator[str] = iter(argv)
    a: str
    for a in it:
        if a == "--min":
            minimum = int(next(it))
        elif a == "--all":
            show_all = True
        elif a == "--normalize":
            normalize = True
        else:
            args.append(a)
    root: str = args[0] if args and os.path.isdir(args[0]) else os.path.dirname(HERE)
    names: list[str] = args[1:] if args and os.path.isdir(args[0]) else args
    if not names:
        names = targets()
    pattern: re.Pattern[str] = name_pattern()
    names = [n for n in names if os.path.isdir(os.path.join(root, n, ".git"))]
    rank: dict[str, int] = {n: i for i, n in enumerate(MATURITY)}
    names.sort(key=lambda n: rank.get(n, len(rank)))

    copies: dict[str, dict[str, Copy]] = {}  # path -> {repo: (blob, bytes)}
    n: str
    p: str
    b: str
    data: bytes
    for n in names:
        for p in tracked(os.path.join(root, n)):
            b, data = blob(os.path.join(root, n, p))
            if normalize:
                try:
                    data = pattern.sub("__name__", data.decode()).encode()
                except UnicodeDecodeError:
                    pass
                b = hashlib.sha1(data).hexdigest()[:7]
            copies.setdefault(p, {})[n] = (b, data)

    for p in sorted(copies):
        held: dict[str, Copy] = copies[p]
        if len(held) < minimum:
            continue
        groups: dict[str, list[str]] = {}
        for n, (b, _) in held.items():
            groups.setdefault(b, []).append(n)
        shared: bool = os.path.isfile(os.path.join(HERE, "files", p))
        if len(groups) == 1 and shared and not show_all:
            continue
        ref_blob: str = max(groups, key=lambda b: (len(groups[b]), -rank.get(groups[b][0], 99)))
        ref: bytes = held[groups[ref_blob][0]][1]
        tag: str = " (files/)" if shared else ""
        print(f"{p}{tag}")
        rs: list[str]
        for b, rs in sorted(groups.items(), key=lambda kv: (kv[0] != ref_blob, kv[1])):
            if b == ref_blob:
                print(f"  {b}  {' '.join(rs)}  [reference, {len(ref.splitlines())} lines]")
                continue
            other: bytes = held[rs[0]][1]
            c: str
            try:
                a, c = ref.decode(), other.decode()
            except UnicodeDecodeError:
                print(f"  {b}  {' '.join(rs)}  [binary]")
                continue
            al: list[str]
            cl: list[str]
            al, cl = a.splitlines(), c.splitlines()
            sm: difflib.SequenceMatcher[str] = difflib.SequenceMatcher(None, al, cl, autojunk=False)
            changed: int = sum(
                max(i2 - i1, j2 - j1) for op, i1, i2, j1, j2 in sm.get_opcodes() if op != "equal"
            )
            print(f"  {b}  {' '.join(rs)}  [{changed} lines differ of {len(cl)}, ratio {sm.ratio():.2f}]")


if __name__ == "__main__":
    main(sys.argv[1:])
