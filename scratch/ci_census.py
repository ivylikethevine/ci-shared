#!/usr/bin/env python3
"""Records every job of a repository's Actions runs, then reports what they cost.

    scratch/ci_census.py fetch --since YYYY-MM-DD --out local/ci_census.jsonl OWNER/NAME...
    scratch/ci_census.py report local/ci_census.jsonl [--repo NAME]
    scratch/ci_census.py regions local/ci_census.jsonl [--repo NAME] [--sample N]

`fetch` reads each day's runs and every attempt's jobs, one JSON line per job,
and reads the annotations of each cancelled or failed job, so a time limit can be
told from a cancellation (the API reports both as `cancelled`). A run GitHub
concluded `skipped` starts no runner and is counted without reading its jobs.

`report` prints, per repository: runner allotments and minutes by event, workflow,
workflow and event, and job; the jobs under 30 seconds; allotments and wall clock
per commit; queue time; the largest pull request commit's timeline; every job that
hit a limit, with how many of its steps ended; and every other job not green.

`regions` reads the logs of every job that hit a limit, and of N passing jobs
(default 20) as the base rate, and prints each one's region, image version and
harden-runner egress policy. Logs redirect to *.blob.core.windows.net, and GitHub
drops them after the repository's retention.

Needs gh for `fetch` and `regions`; `report` reads only the file.
"""
import argparse
import json
import random
import re
import statistics
import subprocess
import sys
from collections import Counter, defaultdict
from collections.abc import Callable, Iterable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from itertools import repeat
from typing import Final, TextIO, TypeAlias, cast

Json: TypeAlias = "str | int | float | bool | None | list[Json] | dict[str, Json]"
Obj: TypeAlias = dict[str, Json]

PER_PAGE: Final[int] = 100
WORKERS: Final[int] = 8
TOP_ROWS: Final[int] = 25
SHORT_SECONDS: Final[float] = 30.0
SHORT_MIN_SAMPLES: Final[int] = 5
LOG_REGION: Final[re.Pattern[str]] = re.compile(r"Region: (\S+)")
LOG_IMAGE: Final[re.Pattern[str]] = re.compile(r"(?:Image Release|Included Software|Version): .*?(\d{8}\.\d+\.\d+)")
LOG_EGRESS: Final[re.Pattern[str]] = re.compile(r"egress-policy: (\w+)")
TIMEOUT: Final[re.Pattern[str]] = re.compile(
    r"The job\b.*exceeded the maximum execution time|The action .* has timed out after"
)
TIME_FORMAT: Final[str] = "%Y-%m-%dT%H:%M:%SZ"
WIDTH: Final[int] = 92
PULL_REQUEST: Final[str] = "pull_request"
COMMIT_EVENTS: Final[tuple[str, ...]] = (PULL_REQUEST, "push", "workflow_run")


@dataclass(frozen=True)
class Row:
    """One job of one attempt, or a run GitHub skipped when `job` is empty."""

    repo: str
    run: int
    workflow: str
    event: str
    branch: str
    sha: str
    attempts: int
    run_created: datetime
    job: str
    job_id: int
    attempt: int
    conclusion: str
    started: datetime | None
    completed: datetime | None
    steps_done: int
    steps: int
    limit: bool

    @property
    def minutes(self) -> float:
        """Returns the job's minutes, zero when it never held a runner."""
        if self.started is None or self.completed is None:
            return 0.0
        return max((self.completed - self.started).total_seconds() / 60, 0.0)

    @property
    def ran(self) -> bool:
        """Tells whether the job was given a runner."""
        return bool(self.job) and self.conclusion != "skipped" and self.minutes > 0

    @property
    def label(self) -> str:
        return f"{self.workflow} / {self.job}"


@dataclass
class Tally:
    """Runner allotments and their minutes."""

    jobs: int = 0
    minutes: float = 0.0

    def add(self, minutes: float) -> None:
        self.jobs += 1
        self.minutes += minutes


@dataclass(frozen=True)
class LogFacts:
    """What a job's set-up log says about where it ran."""

    region: str
    image: str
    egress: str


class Arguments(argparse.Namespace):
    """The command line, typed."""

    command: str = ""
    targets: list[str] = []  # noqa: RUF012
    since: date | None = None
    out: str | None = None
    repo: str | None = None
    sample: int = 20


def api(path: str) -> Json:
    """Returns one API answer, or None when GitHub refuses it."""
    done: subprocess.CompletedProcess[str] = subprocess.run(
        ["gh", "api", path], capture_output=True, text=True, check=False
    )
    if done.returncode != 0:
        print(f"unread: {path}: {done.stderr.strip()}", file=sys.stderr)
        return None
    return cast(Json, json.loads(done.stdout))


def pages(path: str, key: str) -> list[Obj]:
    """Returns every item of a paged list answer."""
    found: list[Obj] = []
    page: int = 1
    while True:
        answer: Json = api(f"{path}{'&' if '?' in path else '?'}per_page={PER_PAGE}&page={page}")
        if not isinstance(answer, dict):
            return found
        items: list[Obj] = cast(list[Obj], answer.get(key) or [])
        found.extend(items)
        if len(items) < PER_PAGE:
            return found
        page += 1


def timed_out(repo: str, job: Obj) -> bool:
    """Tells a job that hit a time limit from one cancelled any other way."""
    if job.get("conclusion") == "timed_out":
        return True
    notes: Json = api(f"repos/{repo}/check-runs/{job['id']}/annotations?per_page=100")
    if not isinstance(notes, list):
        return False
    return any(TIMEOUT.search(str(cast(Obj, note).get("message") or "")) for note in notes)


def run_lines(repo: str, run: Obj) -> list[Obj]:
    """Returns one file line per job of every attempt of a run."""
    common: Obj = {
        "repo": repo,
        "run": run["id"],
        "workflow": run["name"],
        "event": run["event"],
        "branch": run["head_branch"],
        "sha": run["head_sha"],
        "attempts": run["run_attempt"],
        "run_created": run["created_at"],
    }
    if run["conclusion"] == "skipped":
        return [common]
    lines: list[Obj] = []
    job: Obj
    for job in pages(f"repos/{repo}/actions/runs/{run['id']}/jobs?filter=all", "jobs"):
        steps: list[Obj] = cast(list[Obj], job.get("steps") or [])
        ended: bool = job["conclusion"] in ("cancelled", "timed_out", "failure")
        line: Obj = {
            **common,
            "job": job["name"],
            "job_id": job["id"],
            "attempt": job.get("run_attempt"),
            "conclusion": job["conclusion"],
            "started": job["started_at"],
            "completed": job["completed_at"],
            "steps_done": sum(1 for step in steps if step.get("status") == "completed"),
            "steps": len(steps),
            "limit": ended and timed_out(repo, job),
        }
        lines.append(line)
    return lines


def fetch(since: date, out: str, repos: list[str]) -> None:
    """Writes the job lines of each repository's runs since a day."""
    today: date = datetime.now(UTC).date()
    sink: TextIO
    pool: ThreadPoolExecutor
    repo: str
    lines: list[Obj]
    with open(out, "w", encoding="utf-8") as sink, ThreadPoolExecutor(WORKERS) as pool:
        for repo in repos:
            day: date = since
            total: int = 0
            while day <= today:
                runs: list[Obj] = pages(f"repos/{repo}/actions/runs?created={day.isoformat()}", "workflow_runs")
                for lines in pool.map(run_lines, repeat(repo), runs):
                    sink.writelines(json.dumps(line) + "\n" for line in lines)
                total += len(runs)
                day += timedelta(days=1)
            print(f"{repo}: {total} runs", file=sys.stderr)


def moment(text: Json) -> datetime | None:
    """Reads an API time, None when there is none."""
    if not isinstance(text, str):
        return None
    return datetime.strptime(text, TIME_FORMAT).replace(tzinfo=UTC)


def as_int(value: Json) -> int:
    return value if isinstance(value, int) else 0


def row_of(line: Obj) -> Row:
    """Turns a file line into a row."""
    created: datetime | None = moment(line["run_created"])
    if created is None:
        raise ValueError(f"run {line['run']} has no creation time")
    return Row(
        repo=str(line["repo"]),
        run=as_int(line["run"]),
        workflow=str(line["workflow"]),
        event=str(line["event"]),
        branch=str(line["branch"]),
        sha=str(line["sha"]),
        attempts=as_int(line["attempts"]),
        run_created=created,
        job=str(line.get("job") or ""),
        job_id=as_int(line.get("job_id")),
        attempt=as_int(line.get("attempt")),
        conclusion=str(line.get("conclusion") or ""),
        started=moment(line.get("started")),
        completed=moment(line.get("completed")),
        steps_done=as_int(line.get("steps_done")),
        steps=as_int(line.get("steps")),
        limit=bool(line.get("limit")),
    )


def load(path: str, repo: str | None) -> dict[str, list[Row]]:
    """Reads a census file into rows per repository, optionally for one name."""
    by_repo: dict[str, list[Row]] = defaultdict(list)
    source: TextIO
    text: str
    with open(path, encoding="utf-8") as source:
        for text in source:
            row: Row = row_of(cast(Obj, json.loads(text)))
            if repo is None or row.repo == repo or row.repo.endswith(f"/{repo}"):
                by_repo[row.repo].append(row)
    return by_repo


def heading(title: str) -> None:
    print("-" * WIDTH)
    print(title)


def tally_table(title: str, tallies: dict[str, Tally]) -> None:
    """Prints the costliest entries of a tally, with each one's share."""
    print(f"{title:<62}{'jobs':>8}{'minutes':>10}{'share':>8}")
    whole: float = sum(tally.minutes for tally in tallies.values()) or 1.0
    ranked: list[tuple[str, Tally]] = sorted(tallies.items(), key=lambda item: -item[1].minutes)
    name: str
    tally: Tally
    for name, tally in ranked[:TOP_ROWS]:
        print(f"{name[:60]:<62}{tally.jobs:>8}{tally.minutes:>10.1f}{tally.minutes / whole:>8.0%}")


def tally_by(rows: Iterable[Row], key: Callable[[Row], str]) -> dict[str, Tally]:
    tallies: dict[str, Tally] = defaultdict(Tally)
    row: Row
    for row in rows:
        tallies[key(row)].add(row.minutes)
    return tallies


def short_jobs(running: list[Row]) -> None:
    """Prints the jobs whose median is under the short limit."""
    seconds: dict[str, list[float]] = defaultdict(list)
    row: Row
    name: str
    values: list[float]
    for row in running:
        seconds[row.label].append(row.minutes * 60)
    print(f"{f'jobs under {SHORT_SECONDS:.0f} seconds':<62}{'jobs':>8}{'median s':>10}")
    for name, values in sorted(seconds.items()):
        middle: float = statistics.median(values)
        if middle < SHORT_SECONDS and len(values) >= SHORT_MIN_SAMPLES:
            print(f"{name[:60]:<62}{len(values):>8}{middle:>10.0f}")


def per_commit(running: list[Row]) -> None:
    """Prints allotments, minutes and wall clock per commit and event."""
    jobs: Counter[tuple[str, str]] = Counter()
    minutes: dict[tuple[str, str], float] = defaultdict(float)
    begins: dict[tuple[str, str], datetime] = {}
    ends: dict[tuple[str, str], datetime] = {}
    row: Row
    event: str
    for row in running:
        key: tuple[str, str] = (row.sha, row.event)
        jobs[key] += 1
        minutes[key] += row.minutes
        if row.completed is not None and row.attempts == 1:
            begins[key] = min(row.run_created, begins.get(key, row.run_created))
            ends[key] = max(row.completed, ends.get(key, row.completed))
    print(f"{'per commit, median':<34}{'commits':>10}{'jobs':>8}{'runner min':>12}{'wall min':>10}{'wall max':>10}")
    for event in COMMIT_EVENTS:
        keys: list[tuple[str, str]] = [key for key in jobs if key[1] == event]
        walls: list[float] = [(ends[key] - begins[key]).total_seconds() / 60 for key in keys if key in ends]
        if keys and walls:
            middle_jobs: float = statistics.median(jobs[key] for key in keys)
            middle_minutes: float = statistics.median(minutes[key] for key in keys)
            print(
                f"{event:<34}{len(keys):>10}{middle_jobs:>8.0f}{middle_minutes:>12.1f}"
                + f"{statistics.median(walls):>10.1f}{max(walls):>10.1f}"
            )


def queue_times(running: list[Row]) -> None:
    """Prints how long each first attempt's first job waited for a runner.

    Only a run's first job says so: a later one may be waiting on its `needs:`.
    """
    firsts: dict[int, float] = {}
    row: Row
    for row in running:
        if row.started is not None and row.attempt == 1:
            wait: float = (row.started - row.run_created).total_seconds()
            firsts[row.run] = min(wait, firsts.get(row.run, wait))
    if firsts:
        ordered: list[float] = sorted(firsts.values())
        p90: float = ordered[int(len(ordered) * 0.9)]
        print(f"first job start after run created: median {statistics.median(ordered):.0f}s, p90 {p90:.0f}s, longest {ordered[-1]:.0f}s")


def timeline(running: list[Row]) -> None:
    """Prints when each job of the newest largest pull request commit ran, in minutes."""
    commits: dict[str, list[Row]] = defaultdict(list)
    row: Row
    for row in running:
        if row.event == PULL_REQUEST and row.attempts == 1 and row.started is not None and row.completed is not None:
            commits[row.sha].append(row)
    if not commits:
        return
    sha: str = max(commits, key=lambda name: (len(commits[name]), commits[name][0].run_created))
    rows: list[Row] = commits[sha]
    zero: datetime = min(row.run_created for row in rows)
    print(f"{f'timeline of {sha[:8]} on {rows[0].branch}':<62}{'start':>8}{'end':>10}")
    for row in sorted(rows, key=lambda item: cast(datetime, item.completed)):
        begin: float = (cast(datetime, row.started) - zero).total_seconds() / 60
        end: float = (cast(datetime, row.completed) - zero).total_seconds() / 60
        print(f"{row.label[:60]:<62}{begin:>8.1f}{end:>10.1f}")


def limits(running: list[Row]) -> None:
    """Prints each job that hit a limit, and the minutes they spent."""
    hit: list[Row] = [row for row in running if row.limit]
    finished: int = sum(1 for row in hit if row.steps and row.steps_done == row.steps)
    spent: float = sum(row.minutes for row in hit)
    print(f"hit a limit: {len(hit)} jobs, {spent:.0f} minutes, {finished} with every step ended")
    row: Row
    for row in hit:
        steps: str = f"{row.steps_done:>3}/{row.steps:<3}"
        print(f"  {row.label[:56]:<58}{row.event:<14}{steps}{row.minutes:>4.0f}m  {row.job_id}")


def not_green(running: list[Row]) -> None:
    """Prints each other job that did not pass."""
    bad: list[Row] = [row for row in running if not row.limit and row.conclusion != "success"]
    print(f"other not green: {dict(Counter(row.conclusion for row in bad))}")
    counts: Counter[tuple[str, str, str]] = Counter((row.label, row.branch, row.conclusion) for row in bad)
    label: str
    branch: str
    conclusion: str
    count: int
    for (label, branch, conclusion), count in counts.most_common():
        print(f"  {label[:56]:<58}{branch:<14}{conclusion:<11}{count:>3}")


def report(path: str, repo: str | None) -> None:
    """Prints the cost of the rows in a file, per repository."""
    name: str
    mine: list[Row]
    for name, mine in load(path, repo).items():
        running: list[Row] = [row for row in mine if row.ran]
        heading(name)
        skipped: int = len({row.run for row in mine if not row.job})
        print(f"runs {len({row.run for row in mine})}, skipped with no runner {skipped}, allotments {len(running)}")
        tally_table("by event", tally_by(running, lambda row: row.event))
        tally_table("by head branch", tally_by(running, lambda row: row.branch))
        tally_table("by workflow", tally_by(running, lambda row: row.workflow))
        tally_table("by workflow and event", tally_by(running, lambda row: f"{row.workflow} / {row.event}"))
        tally_table("by job", tally_by(running, lambda row: row.label))
        short_jobs(running)
        per_commit(running)
        queue_times(running)
        timeline(running)
        limits(running)
        not_green(running)


def log_facts(repo: str, job_id: int) -> LogFacts | None:
    """Reads where a job ran from its log, None when the log is gone."""
    done: subprocess.CompletedProcess[str] = subprocess.run(
        ["gh", "api", "--allow-escape-sequences", f"repos/{repo}/actions/jobs/{job_id}/logs"],
        capture_output=True,
        text=True,
        check=False,
    )
    if done.returncode != 0:
        print(f"no log: {repo} job {job_id}: {done.stderr.strip()}", file=sys.stderr)
        return None
    region: re.Match[str] | None = LOG_REGION.search(done.stdout)
    image: re.Match[str] | None = LOG_IMAGE.search(done.stdout)
    egress: re.Match[str] | None = LOG_EGRESS.search(done.stdout)
    return LogFacts(
        region=region.group(1) if region else "?",
        image=image.group(1) if image else "?",
        egress=egress.group(1) if egress else "?",
    )


def row_facts(row: Row) -> LogFacts | None:
    return log_facts(row.repo, row.job_id)


def regions(path: str, repo: str | None, sample: int) -> None:
    """Prints where the jobs that hit a limit ran, against a sample of passing ones."""
    rows: list[Row] = [row for mine in load(path, repo).values() for row in mine if row.ran]
    hit: list[Row] = [row for row in rows if row.limit]
    passing: list[Row] = [row for row in rows if row.conclusion == "success"]
    chosen: list[Row] = random.Random(0).sample(passing, min(sample, len(passing)))
    pool: ThreadPoolExecutor
    row: Row
    facts: LogFacts | None
    place: str
    with ThreadPoolExecutor(WORKERS) as pool:
        hit_facts: list[LogFacts | None] = list(pool.map(row_facts, hit))
        base_facts: list[LogFacts | None] = list(pool.map(row_facts, chosen))
    print(f"{'hit a limit':<62}{'region':<12}{'image':<16}{'egress':<8}")
    for row, facts in zip(hit, hit_facts):
        if facts is None:
            print(f"{row.label[:60]:<62}log gone")
        else:
            print(f"{row.label[:60]:<62}{facts.region:<12}{facts.image:<16}{facts.egress:<8}")
    read_hit: list[LogFacts] = [facts for facts in hit_facts if facts is not None]
    read_base: list[LogFacts] = [facts for facts in base_facts if facts is not None]
    print(f"regions, hit a limit:  {dict(Counter(facts.region for facts in read_hit))}")
    print(f"regions, passing jobs: {dict(Counter(facts.region for facts in read_base))}")
    print(f"egress, hit a limit:   {dict(Counter(facts.egress for facts in read_hit))}")
    print(f"egress, passing jobs:  {dict(Counter(facts.egress for facts in read_base))}")
    pairs: Counter[tuple[str, str]] = Counter((facts.region, facts.egress) for facts in read_base)
    print(f"{'passing jobs by region':<24}{'block':>8}{'audit':>8}")
    for place in sorted({facts.region for facts in read_base}):
        print(f"{place:<24}{pairs[(place, 'block')]:>8}{pairs[(place, 'audit')]:>8}")


def main() -> None:
    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    _ = parser.add_argument("command", choices=("fetch", "report", "regions"))
    _ = parser.add_argument("targets", nargs="+", help="fetch: OWNER/NAME...; report, regions: the census file")
    _ = parser.add_argument("--since", type=date.fromisoformat)
    _ = parser.add_argument("--out")
    _ = parser.add_argument("--repo")
    _ = parser.add_argument("--sample", type=int, default=20)
    args: Arguments = parser.parse_args(namespace=Arguments())
    if args.command == "fetch":
        if args.since is None or args.out is None:
            parser.error("fetch needs --since and --out")
        fetch(args.since, args.out, args.targets)
    elif args.command == "report":
        report(args.targets[0], args.repo)
    else:
        regions(args.targets[0], args.repo, args.sample)


if __name__ == "__main__":
    main()
