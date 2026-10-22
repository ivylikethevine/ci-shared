#!/usr/bin/env python3
"""Statement coverage of shell scripts from kcov runs, judged per statement.

    python3 -I tests/coverage.py <kcov cobertura.xml>... <script.sh>...

Each report's hits are added together, a line counted in any of them counted.

kcov's lines are bash's $LINENO, which misplaces three kinds of statement:
a command spanning several lines is recorded on its last line alone (so an
embedded awk or jq program, or a `\\` continuation, reads as code never run);
a command inside a `$( )` or `<( )` can be recorded on the enclosing loop's
last line; and kcov's parser skips some statements (`x=()`) altogether.

So this reads each script's statements from shfmt's syntax tree
(`shfmt --to-json`) and judges every simple statement:

- run when kcov hit any line it spans;
- inside a substitution, otherwise: as the statement holding that
  substitution (for a loop or `if`, its first line);
- with no line kcov counts, otherwise: as the next statement in its block;
- not run when kcov counts its lines and hit none.

The second rule credits a branch inside a substitution whenever the
substitution ran, so keep conditionals out of them.

Prints each script's figure and every statement not run or not seen, and
exits 1 unless every statement of every script ran.
"""

import functools
import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from io import BufferedReader
from pathlib import Path
from typing import TypeAlias

# statements that run as one command; the compound ones only hold these
LEAVES: set[str] = {"CallExpr", "DeclClause", "TestClause", "ArithmCmd", "LetClause"}
SUBSTS: set[str] = {"CmdSubst", "ProcSubst"}
# what json reads from shfmt's syntax tree
Json: TypeAlias = "str | int | float | bool | None | list[Json] | dict[str, Json]"
Hits: TypeAlias = dict[int, int]


def kcov_lines(reports: list[str]) -> dict[str, Hits]:
    """{script basename: {line: hits}} from kcov's reports, summed."""
    lines: dict[str, Hits] = {}
    report: str
    c: ET.Element[str]
    x: ET.Element[str]
    for report in reports:
        for c in ET.parse(report).getroot().iter("class"):
            seen: Hits = lines.setdefault(Path(c.get("filename", "")).name, {})
            for x in c.iter("line"):
                n: int = int(x.get("number", 0))
                seen[n] = seen.get(n, 0) + int(x.get("hits", 0))
    return lines


class Stmt:
    def __init__(self, node: dict[str, Json], parent: "Stmt | None", in_subst: bool) -> None:
        cmd: dict[str, Json] = node.get("Cmd") or {}
        self.leaf: bool = cmd.get("Type") in LEAVES
        self.first: int = node["Pos"]["Line"]
        self.last: int = node["End"]["Line"]
        self.parent: Stmt | None = parent
        self.in_subst: bool = in_subst
        self.next: "Stmt | None" = None
        self.ran: "bool | None" = None


def statements(script: str) -> list[Stmt]:
    """Every statement of the script, in source order."""
    f: BufferedReader
    with open(script, "rb") as f:
        tree: Json = json.loads(subprocess.run(["shfmt", "--to-json"], stdin=f, capture_output=True, check=True).stdout)
    stmts: list[Stmt] = []

    def walk(node: Json, parent: Stmt | None, in_subst: bool) -> Stmt | None:
        n: Json
        v: Json
        if isinstance(node, list):
            prev: Stmt | None = None
            for n in node:
                s: Stmt | None = walk(n, parent, in_subst)
                if s is not None:
                    if prev is not None:
                        prev.next = s
                    prev = s
            return None
        if not isinstance(node, dict):
            return None
        if "Cmd" in node and "Pos" in node:
            s = Stmt(node, parent, in_subst)
            stmts.append(s)
            # a compound statement's own statements share its place
            for v in node.values():
                walk(v, s, in_subst and not s.leaf)
            return s
        inner: bool = in_subst or node.get("Type") in SUBSTS
        for v in node.values():
            walk(v, parent, inner)
        return None

    walk(tree, None, False)
    return stmts


def judge(stmts: list[Stmt], seen: Hits) -> None:
    """Sets each statement's .ran: True, False or None (not seen)."""
    @functools.cache  # a Stmt hashes by identity
    def ran(s: Stmt) -> bool | None:
        span: range = range(s.first, s.last + 1) if s.leaf else range(s.first, s.first + 1)
        counted: list[int] = [seen[n] for n in span if n in seen]
        verdict: bool | None
        if any(counted):
            verdict = True
        elif s.in_subst and s.parent is not None:
            verdict = ran(s.parent)
        elif counted:
            verdict = False
        elif s.next is not None:
            verdict = ran(s.next)
        else:
            verdict = None
        return verdict

    s: Stmt
    for s in stmts:
        s.ran = ran(s)


def main() -> int:
    reports: list[str] = [a for a in sys.argv[1:] if a.endswith(".xml")]
    scripts: list[str] = sys.argv[1 + len(reports) :]
    if not reports or not scripts:
        sys.exit(__doc__)
    hits: dict[str, Hits] = kcov_lines(reports)
    ok: bool = True
    stmts: list[Stmt]
    leaves: list[Stmt]
    s: Stmt
    script: str
    for script in scripts:
        stmts = statements(script)
        judge(stmts, hits.get(Path(script).name, {}))
        leaves = [s for s in stmts if s.leaf]
        run: int = sum(1 for s in leaves if s.ran)
        print(f"{script}: {run}/{len(leaves)} statements ({100 * run / max(len(leaves), 1):.1f}%)")
        for s in leaves:
            if s.ran is False:
                print(f"  {script}:{s.first}: not run")
            elif s.ran is None:
                print(f"  {script}:{s.first}: not seen by kcov")
        ok = ok and run == len(leaves)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
