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
from typing import NamedTuple

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


class Options(NamedTuple):
    minimum: int
    show_all: bool
    # the names --normalize folds, or None without it
    pattern: re.Pattern[str] | None
    root: str
    names: list[str]


def parse(argv: list[str]) -> Options:
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
    return Options(minimum, show_all, name_pattern() if normalize else None, root, names or targets())


def read_copy(path: str, pattern: re.Pattern[str] | None) -> tuple[str, bytes]:
    """A copy's short blob and its bytes, folded by the pattern when there is one."""
    fh: BufferedReader
    with open(path, "rb") as fh:
        data: bytes = fh.read()
    if pattern is None:
        return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()[:7], data
    try:
        data = pattern.sub("__name__", data.decode()).encode()
    except UnicodeDecodeError:
        pass
    return hashlib.sha1(data).hexdigest()[:7], data


def collect(options: Options, names: list[str]) -> dict[str, dict[str, str]]:
    """Each tracked path's {repository: short blob}, so no copy stays in memory."""
    copies: dict[str, dict[str, str]] = {}
    n: str
    p: str
    for n in names:
        for p in tracked(os.path.join(options.root, n)):
            copies.setdefault(p, {})[n] = read_copy(os.path.join(options.root, n, p), options.pattern)[0]
    return copies


def difference(ref: bytes, other: bytes) -> str:
    """How a copy differs from the reference, for its line of the report."""
    a: str
    c: str
    try:
        a, c = ref.decode(), other.decode()
    except UnicodeDecodeError:
        return "binary"
    al: list[str]
    cl: list[str]
    al, cl = a.splitlines(), c.splitlines()
    sm: difflib.SequenceMatcher[str] = difflib.SequenceMatcher(None, al, cl, autojunk=False)
    changed: int = sum(max(i2 - i1, j2 - j1) for op, i1, i2, j1, j2 in sm.get_opcodes() if op != "equal")
    return f"{changed} lines differ of {len(cl)}, ratio {sm.ratio():.2f}"


def report_path(options: Options, p: str, held: dict[str, str], rank: dict[str, int]) -> None:
    groups: dict[str, list[str]] = {}
    n: str
    b: str
    for n, b in held.items():
        groups.setdefault(b, []).append(n)
    shared: bool = os.path.isfile(os.path.join(HERE, "files", p))
    if len(groups) == 1 and shared and not options.show_all:
        return
    ref_blob: str = max(groups, key=lambda b: (len(groups[b]), -rank.get(groups[b][0], 99)))

    def copy_of(repo: str) -> bytes:
        return read_copy(os.path.join(options.root, repo, p), options.pattern)[1]

    ref: bytes = copy_of(groups[ref_blob][0])
    tag: str = " (files/)" if shared else ""
    print(f"{p}{tag}")
    rs: list[str]
    for b, rs in sorted(groups.items(), key=lambda kv: (kv[0] != ref_blob, kv[1])):
        note: str = f"reference, {len(ref.splitlines())} lines" if b == ref_blob else difference(ref, copy_of(rs[0]))
        print(f"  {b}  {' '.join(rs)}  [{note}]")


def main(argv: list[str]) -> None:
    options: Options = parse(argv)
    names: list[str] = [n for n in options.names if os.path.isdir(os.path.join(options.root, n, ".git"))]
    rank: dict[str, int] = {n: i for i, n in enumerate(MATURITY)}
    names.sort(key=lambda n: rank.get(n, len(rank)))
    copies: dict[str, dict[str, str]] = collect(options, names)
    p: str
    for p in sorted(copies):
        if len(copies[p]) >= options.minimum:
            report_path(options, p, copies[p], rank)


if __name__ == "__main__":
    main(sys.argv[1:])
