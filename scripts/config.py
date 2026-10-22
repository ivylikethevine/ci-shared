#!/usr/bin/env python3
"""Reads and validates every repos/<name>.toml, and prints them as one JSON list.

    python3 -I scripts/config.py [ROOT]

ROOT is the tree holding repos/ and files/ (default: this checkout). Each entry is the file's table with `name` (the file's stem) and `token_secret`
(SYNC_TOKEN_<NAME>, the secret holding its sync token) added and every
optional key filled in, sorted by name. Any problem in any file, an unknown key
included, prints one line per problem to stderr and exits 1 with nothing on
stdout, so no caller acts on a partial or misread config. Needs Python 3.11+.
"""

import json
import re
import sys
import tomllib
from datetime import date, datetime, time
from pathlib import Path
from typing import BinaryIO, TypeAlias

# what tomllib reads: a table of these, nested
Toml: TypeAlias = "str | int | float | bool | date | datetime | time | list[Toml] | dict[str, Toml]"
Table: TypeAlias = dict[str, Toml]

ROOT: Path = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
SLUG: re.Pattern[str] = re.compile(r"[A-Za-z0-9-]+/[A-Za-z0-9._-]+")
TEMPLATE_KEY: re.Pattern[str] = re.compile(r"[A-Za-z_]+")
# ci_targets spells a value's spaces %20, so none holds a %; awk's gsub reads
# & and \ in a replacement, so none holds those either
TEMPLATE_VALUE: re.Pattern[str] = re.compile(r"[^\s%&\\]+( [^\s%&\\]+)*")
BRANCHES: tuple[str, str] = ("main", "dev")
COVERAGE_KEYS: set[str] = {"minimum_coverage", "max_coverage_drop"}
# the GitHub Actions app, which reports a required status check unless the
# check names another integration
ACTIONS_APP: int = 15368


def check_keys(where: str, table: Table, allowed: set[str], errors: list[str]) -> None:
    key: str
    for key in table.keys() - allowed:
        errors.append(f"{where}: unknown key {key!r}")


def read(path: Path, errors: list[str]) -> Table | None:
    where: str = str(path.relative_to(ROOT))
    data: Table
    f: BinaryIO
    try:
        with path.open("rb") as f:
            data = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as e:
        errors.append(f"{where}: {e}")
        return None
    name: str = path.stem
    check_keys(where, data, {"repository", "sync_branch", "files", "templates", "rulesets"}, errors)

    repository: Toml | None = data.get("repository")
    if not isinstance(repository, str) or not SLUG.fullmatch(repository):
        errors.append(f"{where}: repository must be 'owner/name'")
    elif repository.split("/")[1] != name:
        errors.append(f"{where}: repository {repository!r} does not end in the file's name")

    if data.get("sync_branch") not in BRANCHES:
        errors.append(f"{where}: sync_branch must be one of {', '.join(BRANCHES)}")

    files: Toml = data.get("files", [])
    if not isinstance(files, list) or not all(isinstance(p, str) for p in files):
        errors.append(f"{where}: files must be a list of paths")
        files = []
    p: str
    for p in sorted({p for p in files if files.count(p) > 1}):
        errors.append(f"{where}: {p} is listed twice")
    for p in files:
        if not (ROOT / "files" / p).is_file():
            errors.append(f"{where}: {p} is listed but files/{p} does not exist")

    templates: Toml = data.setdefault("templates", {})
    if not isinstance(templates, dict):
        errors.append(f"{where}: templates must be a table")
        templates = {}
    values: Toml
    k: str
    v: Toml
    for p, values in templates.items():
        if p not in files:
            errors.append(f"{where}: templates.{p!r} is not in files")
        if not isinstance(values, dict):
            errors.append(f"{where}: templates.{p!r} must be a table")
            continue
        for k, v in values.items():
            if not TEMPLATE_KEY.fullmatch(k):
                errors.append(f"{where}: templates.{p!r} key {k!r} is not letters and _")
            elif k == "repo":
                errors.append(f"{where}: templates.{p!r}.repo is set by the sync, from the file's name")
            if not isinstance(v, str) or not TEMPLATE_VALUE.fullmatch(v):
                errors.append(f"{where}: templates.{p!r}.{k} must be a string of single-spaced words without %, & or \\")

    rulesets: Toml = data.setdefault("rulesets", {})
    if not isinstance(rulesets, dict):
        errors.append(f"{where}: rulesets must be a table")
        rulesets = data["rulesets"] = {}
    check_keys(f"{where}: rulesets", rulesets, {"main"}, errors)
    main: Toml = rulesets.setdefault("main", {})
    if not isinstance(main, dict):
        errors.append(f"{where}: rulesets.main must be a table")
        main = rulesets["main"] = {}
    check_keys(
        f"{where}: rulesets.main",
        main,
        {"required_status_checks", "code_scanning_tools", "code_quality", "code_coverage"},
        errors,
    )
    checks: Toml = main.setdefault("required_status_checks", [])
    if not isinstance(checks, list):
        errors.append(f"{where}: rulesets.main.required_status_checks must be a list")
        checks = []
    c: Toml
    for c in checks:
        if (
            not isinstance(c, dict)
            or c.keys() - {"context", "integration_id"}
            or not isinstance(c.get("context"), str)
            or not isinstance(c.get("integration_id", 0), int)
        ):
            errors.append(f"{where}: each required status check is {{context, integration_id}}, not {c!r}")
        else:
            c.setdefault("integration_id", ACTIONS_APP)
    tools: Toml = main.setdefault("code_scanning_tools", [])
    if not isinstance(tools, list) or not all(isinstance(t, str) for t in tools):
        errors.append(f"{where}: rulesets.main.code_scanning_tools must be a list of names")
    if not isinstance(main.setdefault("code_quality", False), bool):
        errors.append(f"{where}: rulesets.main.code_quality must be true or false")
    coverage: Toml | None = main.setdefault("code_coverage", None)
    if coverage is not None and (
        not isinstance(coverage, dict)
        or coverage.keys() != COVERAGE_KEYS
        or not all(isinstance(v, int) for v in coverage.values())
    ):
        errors.append(f"{where}: rulesets.main.code_coverage must set minimum_coverage and max_coverage_drop")

    return {"name": name, "token_secret": token_secret(name), **data}


def token_secret(name: str) -> str:
    return "SYNC_TOKEN_" + re.sub(r"[^A-Za-z0-9]", "_", name).upper()


def main() -> int:
    errors: list[str] = []
    paths: list[Path] = sorted((ROOT / "repos").glob("*.toml"))
    if not paths:
        errors.append("repos/ holds no <name>.toml")
    configs: list[Table] = [c for c in (read(p, errors) for p in paths) if c is not None]
    # repositories cannot collide: each ends in its file's name
    secrets: dict[str, str] = {}
    c: Table
    for c in configs:
        if c["token_secret"] in secrets:
            errors.append(f"repos/{c['name']}.toml: its token secret {c['token_secret']} is also repos/{secrets[c['token_secret']]}.toml's")
        secrets.setdefault(c["token_secret"], c["name"])
    if errors:
        e: str
        for e in errors:
            print(e, file=sys.stderr)
        return 1
    json.dump(configs, sys.stdout)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
