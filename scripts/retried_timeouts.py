#!/usr/bin/env python3
"""Logs each GitHub Actions job that timed out and passed when rerun.

    scripts/retried_timeouts.py [--since YYYY-MM-DD] [--max-retries N] [--log PATH] [REPO...]

REPO is a name or owner/name the token's user owns; the default is every owned
repository that is neither a fork nor archived. --since (default: 30 days ago)
bounds when a run was created, in UTC. --max-retries (default 2) bounds the
failed executions before the pass. Each new job appends one JSON line to --log
(default: local/retried_timeouts.jsonl), so a rerun over the same days adds
nothing; the new rows and each repository's totals over the whole log print.

The API reports a job that hit `timeout-minutes` as `cancelled`, as it does a
job cancelled any other way, so a timeout is told by its annotation: "The job
has exceeded the maximum execution time", or "The action ... has timed out
after" for a step's limit. A job copied unchanged into a later attempt keeps
its `started_at` and counts once. A row's outcome is how far the first timed-out
execution's steps got as GitHub recorded them: `finished` (its `Complete job`
ended, yet the job stayed open until the limit), `stopped` (some steps ended) or
`no steps`. active_minutes runs to the last step recorded as done and
recorded_minutes to the job's end. CI_SHARED_DIR, as for scripts/, names the tree
whose local/ holds the log (default: this checkout). Exits 1 when a repository
or run could not be read, after logging the rest; needs gh.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from typing import Final, TextIO, TypeAlias, TypedDict, TypeVar, cast

Json: TypeAlias = "str | int | float | bool | None | list[Json] | dict[str, Json]"
T = TypeVar("T")

HERE: Final[str] = os.environ.get("CI_SHARED_DIR") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PER_PAGE: Final[int] = 100
# the runs endpoint returns at most this many runs for one filtered search
SEARCH_LIMIT: Final[int] = 1000
TIMEOUT: Final[re.Pattern[str]] = re.compile(
    r"The job\b.*exceeded the maximum execution time|The action .* has timed out after"
)
TIME_FORMAT: Final[str] = "%Y-%m-%dT%H:%M:%SZ"
# seconds before each new try of a call GitHub answered with a 5xx
RETRY_DELAYS: Final[tuple[int, ...]] = (1, 3)
SERVER_ERROR: Final[re.Pattern[str]] = re.compile(r"HTTP 5\d\d")


class Repo(TypedDict):
    name: str
    full_name: str
    fork: bool
    archived: bool


class Run(TypedDict):
    id: int
    name: str
    event: str
    head_branch: str
    head_sha: str
    html_url: str
    run_attempt: int


class Step(TypedDict):
    name: str
    conclusion: str | None
    completed_at: str | None


class Job(TypedDict):
    id: int
    name: str
    conclusion: str | None
    run_attempt: int
    started_at: str
    completed_at: str | None
    labels: list[str]
    steps: list[Step]


class Annotation(TypedDict):
    message: str | None


class Entry(TypedDict):
    repository: str
    run_id: int
    workflow: str
    job: str
    job_id: int
    event: str
    branch: str
    sha: str
    runner: str
    timed_out_at: str
    step: str
    message: str
    retries: int
    timeouts: int
    passed_attempt: int
    outcome: str
    active_minutes: float
    recorded_minutes: float
    failed_minutes: float
    delay_minutes: float
    url: str


class GhError(Exception):
    pass


def gh(endpoint: str) -> Json:
    delay: int
    for delay in RETRY_DELAYS:
        done: subprocess.CompletedProcess[str] = subprocess.run(
            ["gh", "api", endpoint], capture_output=True, text=True, check=False
        )
        if done.returncode == 0 or not SERVER_ERROR.search(done.stderr):
            break
        time.sleep(delay)
    else:
        done = subprocess.run(["gh", "api", endpoint], capture_output=True, text=True, check=False)
    if done.returncode != 0:
        raise GhError(f"{endpoint}: {done.stderr.strip()}")
    return cast(Json, json.loads(done.stdout))


def pages(path: str, _: type[T], key: str = "", query: str = "") -> list[T]:
    """Every item of a listing, from `key` of each page or the page itself."""
    items: list[T] = []
    page: int = 1
    while True:
        body: Json = gh(f"{path}?{query}per_page={PER_PAGE}&page={page}")
        batch: list[T] = cast("dict[str, list[T]]", body)[key] if key else cast("list[T]", body)
        items += batch
        if len(batch) < PER_PAGE:
            return items
        page += 1


def stamp(when: datetime) -> str:
    return when.strftime(TIME_FORMAT)


def minutes(start: str, end: str) -> float:
    span: timedelta = datetime.fromisoformat(end) - datetime.fromisoformat(start)
    return round(max(span.total_seconds(), 0) / 60, 1)


def runs_between(repo: str, start: datetime, end: datetime) -> list[Run]:
    """The runs created in the span, halving it while it passes the search limit."""
    path: str = f"repos/{repo}/actions/runs"
    query: str = f"created={stamp(start)}..{stamp(end)}&exclude_pull_requests=true&"
    probe: Json = gh(f"{path}?{query}per_page=1")
    if cast("dict[str, int]", probe)["total_count"] > SEARCH_LIMIT:
        middle: datetime = start + timedelta(seconds=(end - start).total_seconds() // 2)
        return runs_between(repo, start, middle) + runs_between(repo, middle + timedelta(seconds=1), end)
    return pages(path, Run, "workflow_runs", query)


def executions(jobs: list[Job]) -> dict[str, list[Job]]:
    """Each job name's real executions in attempt order, without copied ones or skips."""
    by_name: dict[str, dict[str, Job]] = {}
    job: Job
    for job in sorted(jobs, key=lambda j: j["run_attempt"]):
        if job["conclusion"] != "skipped":
            by_name.setdefault(job["name"], {}).setdefault(job["started_at"], job)
    return {name: list(runs.values()) for name, runs in by_name.items()}


def recoveries(runs: list[Job]) -> Iterator[tuple[list[Job], Job]]:
    """Each pass that follows failures, with those failures."""
    failed: list[Job] = []
    job: Job
    for job in runs:
        if job["conclusion"] != "success":
            failed.append(job)
        elif failed:
            yield failed, job
            failed = []


def timeout_message(repo: str, job: Job) -> str:
    """Why the job timed out, or "" when it did not."""
    notes: list[Annotation] = pages(f"repos/{repo}/check-runs/{job['id']}/annotations", Annotation)
    note: Annotation
    for note in notes:
        text: str = note["message"] or ""
        if TIMEOUT.match(text):
            return text
    return "conclusion: timed_out" if job["conclusion"] == "timed_out" else ""


def outcome(job: Job) -> str:
    """How far the steps GitHub heard about got: finished, stopped or no steps."""
    if not any(s["completed_at"] for s in job["steps"]):
        return "no steps"
    return "finished" if any(s["name"] == "Complete job" and s["completed_at"] for s in job["steps"]) else "stopped"


def active_minutes(job: Job) -> float:
    """From the job's start to the last step GitHub recorded as done."""
    ends: list[str] = [s["completed_at"] for s in job["steps"] if s["completed_at"]]
    return minutes(job["started_at"], max(ends, default=job["started_at"]))


def entry(repo: str, run: Run, failed: list[Job], timed_out: list[tuple[Job, str]], passed: Job) -> Entry:
    first: Job = timed_out[0][0]
    return {
        "repository": repo,
        "run_id": run["id"],
        "workflow": run["name"],
        "job": first["name"],
        "job_id": first["id"],
        "event": run["event"],
        "branch": run["head_branch"],
        "sha": run["head_sha"],
        "runner": ",".join(first["labels"]),
        "timed_out_at": first["started_at"],
        "step": next((s["name"] for s in first["steps"] if s["conclusion"] == "failure"), ""),
        "message": timed_out[0][1],
        "retries": len(failed),
        "timeouts": len(timed_out),
        "passed_attempt": passed["run_attempt"],
        "outcome": outcome(first),
        "active_minutes": active_minutes(first),
        "recorded_minutes": minutes(first["started_at"], first["completed_at"] or first["started_at"]),
        "failed_minutes": round(sum(minutes(j["started_at"], j["completed_at"] or j["started_at"]) for j in failed), 1),
        "delay_minutes": minutes(failed[0]["started_at"], passed["completed_at"] or passed["started_at"]),
        "url": run["html_url"],
    }


def scan_run(repo: str, run: Run, max_retries: int) -> list[Entry]:
    # one listing per attempt: the all-attempts one answers 502 past its first page on big runs
    jobs: list[Job] = [
        job
        for attempt in range(1, run["run_attempt"] + 1)
        for job in pages(f"repos/{repo}/actions/runs/{run['id']}/attempts/{attempt}/jobs", Job, "jobs")
    ]
    found: list[Entry] = []
    runs: list[Job]
    failed: list[Job]
    passed: Job
    for runs in executions(jobs).values():
        for failed, passed in recoveries(runs):
            if len(failed) <= max_retries:
                checked: list[tuple[Job, str]] = [(j, timeout_message(repo, j)) for j in failed]
                timed_out: list[tuple[Job, str]] = [c for c in checked if c[1]]
                if timed_out:
                    found.append(entry(repo, run, failed, timed_out, passed))
    return found


def scan_repo(repo: str, start: datetime, end: datetime, max_retries: int) -> tuple[list[Entry], int]:
    """What the repository's retried runs hold, and 1 when one could not be read."""
    runs: list[Run] = runs_between(repo, start, end)
    retried: list[Run] = [r for r in runs if r["run_attempt"] > 1]
    print(f"{repo}: {len(retried)} retried runs of {len(runs)}", file=sys.stderr)
    found: list[Entry] = []
    rc: int = 0
    run: Run
    for run in retried:
        try:
            found += scan_run(repo, run, max_retries)
        except GhError as e:
            print(e, file=sys.stderr)
            rc = 1
    return found, rc


def key(item: Entry) -> tuple[str, int, str, int]:
    return item["repository"], item["run_id"], item["job"], item["passed_attempt"]


def read_log(path: str) -> list[Entry]:
    f: TextIO
    try:
        with open(path, encoding="utf-8") as f:
            return [cast(Entry, json.loads(line)) for line in f]
    except FileNotFoundError:
        return []


def table(headers: list[str], rows: list[list[str]]) -> None:
    widths: list[int] = [max(len(r[i]) for r in [headers, *rows]) for i in range(len(headers))]
    row: list[str]
    for row in [headers, ["-" * w for w in widths], *rows]:
        print("  ".join(cell.ljust(w) for cell, w in zip(row, widths, strict=True)).rstrip())


def print_new(new: list[Entry]) -> None:
    table(
        ["Timed out (UTC)", "Repository", "Workflow", "Job", "Retries", "Active minutes", "Recorded minutes", "Outcome"],
        [
            [
                e["timed_out_at"],
                e["repository"].split("/")[-1],
                e["workflow"],
                e["job"],
                str(e["retries"]),
                str(e["active_minutes"]),
                str(e["recorded_minutes"]),
                e["outcome"],
            ]
            for e in new
        ],
    )


def print_totals(logged: list[Entry]) -> None:
    rows: list[list[str]] = []
    repo: str
    for repo in sorted({e["repository"] for e in logged}):
        mine: list[Entry] = [e for e in logged if e["repository"] == repo]
        rows.append(
            [
                repo.split("/")[-1],
                str(len(mine)),
                *[str(sum(e["outcome"] == o for e in mine)) for o in ("finished", "stopped", "no steps")],
                str(round(sum(e["failed_minutes"] for e in mine), 1)),
                str(round(sum(e["delay_minutes"] for e in mine), 1)),
            ]
        )
    table(["Repository", "Jobs", "Finished", "Stopped", "No steps", "Failed minutes", "Delay minutes"], rows)


def select_repos(names: list[str]) -> list[str]:
    owned: list[Repo] = pages("user/repos", Repo, query="affiliation=owner&")
    if not names:
        return [r["full_name"] for r in owned if not (r["fork"] or r["archived"])]
    known: dict[str, str] = {k: r["full_name"] for r in owned for k in (r["name"], r["full_name"])}
    unknown: list[str] = [n for n in names if n not in known]
    if unknown:
        raise GhError(f"not an owned repository: {', '.join(unknown)}")
    return [known[n] for n in names]


def parse_args() -> argparse.Namespace:
    parser: argparse.ArgumentParser = argparse.ArgumentParser(description="Logs jobs that timed out and passed on rerun.")
    parser.add_argument("--since", type=datetime.fromisoformat, help="YYYY-MM-DD (default: 30 days ago)")
    parser.add_argument("--max-retries", type=int, default=2)
    parser.add_argument("--log", default=os.path.join(HERE, "local", "retried_timeouts.jsonl"))
    parser.add_argument("repos", nargs="*", metavar="REPO")
    return parser.parse_args()


def main() -> int:
    args: argparse.Namespace = parse_args()
    now: datetime = datetime.now(timezone.utc).replace(microsecond=0)
    start: datetime = args.since.replace(tzinfo=timezone.utc) if args.since else now - timedelta(days=30)
    try:
        repos: list[str] = select_repos(args.repos)
    except GhError as e:
        print(e, file=sys.stderr)
        return 1
    logged: list[Entry] = read_log(args.log)
    seen: set[tuple[str, int, str, int]] = {key(e) for e in logged}
    os.makedirs(os.path.dirname(os.path.abspath(args.log)), exist_ok=True)
    new: list[Entry] = []
    rc: int = 0
    repo: str
    f: TextIO
    for repo in repos:
        try:
            found: list[Entry]
            failed: int
            found, failed = scan_repo(repo, start, now, args.max_retries)
            rc |= failed
        except GhError as e:
            print(e, file=sys.stderr)
            rc = 1
            continue
        fresh: list[Entry] = sorted((e for e in found if key(e) not in seen), key=lambda e: e["timed_out_at"])
        with open(args.log, "a", encoding="utf-8") as f:
            f.writelines(json.dumps(e) + "\n" for e in fresh)
        new += fresh
    if new:
        print_new(new)
    print(f"{len(new)} new, {len(logged) + len(new)} in {args.log}")
    if logged or new:
        print_totals(logged + new)
    return rc


if __name__ == "__main__":
    sys.exit(main())
