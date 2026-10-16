#!/usr/bin/env python3
"""Statement coverage of shell scripts from a kcov run, judged per statement.

    python3 -I tests/coverage.py <kcov cobertura.xml> <script.sh>...

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

import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# statements that run as one command; the compound ones only hold these
LEAVES = {"CallExpr", "DeclClause", "TestClause", "ArithmCmd", "LetClause"}
SUBSTS = {"CmdSubst", "ProcSubst"}


def kcov_lines(cobertura):
    """{script basename: {line: hits}} from kcov's report."""
    lines = {}
    for c in ET.parse(cobertura).getroot().iter("class"):
        lines[Path(c.get("filename", "")).name] = {
            int(x.get("number", 0)): int(x.get("hits", 0)) for x in c.iter("line")
        }
    return lines


class Stmt:
    def __init__(self, node, parent, in_subst):
        cmd = node.get("Cmd") or {}
        self.leaf = cmd.get("Type") in LEAVES
        self.first = node["Pos"]["Line"]
        self.last = node["End"]["Line"]
        self.parent = parent
        self.in_subst = in_subst
        self.next: "Stmt | None" = None
        self.ran: "bool | None" = None


def statements(script):
    """Every statement of the script, in source order."""
    with open(script, "rb") as f:
        tree = json.loads(subprocess.run(["shfmt", "--to-json"], stdin=f, capture_output=True, check=True).stdout)
    stmts = []

    def walk(node, parent, in_subst):
        if isinstance(node, list):
            prev = None
            for n in node:
                s = walk(n, parent, in_subst)
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
        inner = in_subst or node.get("Type") in SUBSTS
        for v in node.values():
            walk(v, parent, inner)
        return None

    walk(tree, None, False)
    return stmts


def judge(stmts, seen):
    """Sets each statement's .ran: True, False or None (not seen)."""
    done = {}

    def ran(s):
        if id(s) in done:
            return done[id(s)]
        span = range(s.first, s.last + 1) if s.leaf else range(s.first, s.first + 1)
        counted = [seen[n] for n in span if n in seen]
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
        done[id(s)] = verdict
        return verdict

    for s in stmts:
        s.ran = ran(s)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    hits = kcov_lines(sys.argv[1])
    ok = True
    for script in sys.argv[2:]:
        stmts = statements(script)
        judge(stmts, hits.get(Path(script).name, {}))
        leaves = [s for s in stmts if s.leaf]
        run = sum(1 for s in leaves if s.ran)
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
