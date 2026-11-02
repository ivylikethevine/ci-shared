#!/usr/bin/env python3
"""Measures how long each job takes when it passes, to size `timeout-minutes`.

    scripts/job_durations.py [--runs N] OWNER/NAME...

Reads each active workflow's newest N successful runs (default 20), the latest
attempt of each, and prints one tab-separated row per repository, workflow file
and job name: passing executions, median minutes, longest minutes, and the
limit that longest suggests, 1.5 times it rounded up to a multiple of 5. Rows
from a job seen fewer than 5 times suggest nothing. Redirect the output under
local/. Exits 1 when a repository or workflow could not be read, after printing
the rest; needs gh.
"""
import argparse
import math
import statistics
import sys
from datetime import datetime
from typing import Final, TypedDict, cast

from gh_api import PER_PAGE, GhError, gh, pages

MIN_SAMPLES: Final[int] = 5


class Workflow(TypedDict):
    id: int
    path: str
    state: str


class Run(TypedDict):
    id: int


class Job(TypedDict):
    name: str
    conclusion: str | None
    started_at: str
    completed_at: str | None


class WorkflowPage(TypedDict):
    workflows: list[Workflow]


class RunPage(TypedDict):
    workflow_runs: list[Run]


def job_minutes(job: Job) -> float:
    start: datetime = datetime.fromisoformat(job["started_at"])
    end: datetime = datetime.fromisoformat(job["completed_at"] or job["started_at"])
    return max((end - start).total_seconds(), 0) / 60


def row(repo: str, path: str, name: str, samples: list[float]) -> str:
    longest: float = max(samples)
    suggestion: str = str(5 * math.ceil(longest * 1.5 / 5)) if len(samples) >= MIN_SAMPLES else "-"
    median: float = statistics.median(samples)
    return f"{repo}\t{path}\t{name}\t{len(samples)}\t{median:.1f}\t{longest:.1f}\t{suggestion}"


def scan_workflow(repo: str, workflow: Workflow, runs: int) -> list[str]:
    endpoint: str = f"repos/{repo}/actions/workflows/{workflow['id']}/runs?status=success&per_page={runs}"
    samples: dict[str, list[float]] = {}
    run: Run
    for run in cast(RunPage, gh(endpoint))["workflow_runs"]:
        job: Job
        for job in pages(f"repos/{repo}/actions/runs/{run['id']}/jobs", Job, "jobs"):
            if job["conclusion"] == "success":
                samples.setdefault(job["name"], []).append(job_minutes(job))
    return [row(repo, workflow["path"], name, samples[name]) for name in sorted(samples)]


def scan_repo(repo: str, runs: int) -> int:
    """Prints the repository's rows, and returns 1 when one could not be read."""
    rc: int = 0
    listing: WorkflowPage = cast(WorkflowPage, gh(f"repos/{repo}/actions/workflows?per_page={PER_PAGE}"))
    workflow: Workflow
    for workflow in listing["workflows"]:
        if workflow["state"] != "active":
            continue
        try:
            rows: list[str] = scan_workflow(repo, workflow, runs)
            sys.stdout.writelines(f"{r}\n" for r in rows)
            sys.stdout.flush()
        except GhError as e:
            print(e, file=sys.stderr)
            rc = 1
    return rc


def main() -> int:
    parser: argparse.ArgumentParser = argparse.ArgumentParser(description="Measures passing job durations.")
    parser.add_argument("--runs", type=int, default=20)
    parser.add_argument("repos", nargs="+", metavar="OWNER/NAME")
    args: argparse.Namespace = parser.parse_args()
    rc: int = 0
    repo: str
    for repo in args.repos:
        try:
            rc |= scan_repo(repo, args.runs)
        except GhError as e:
            print(e, file=sys.stderr)
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
