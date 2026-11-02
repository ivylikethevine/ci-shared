"""The `gh api` client scripts/job_durations.py and scripts/retried_timeouts.py share."""
import json
import re
import subprocess
import time
from typing import Final, TypeAlias, TypeVar, cast

Json: TypeAlias = "str | int | float | bool | None | list[Json] | dict[str, Json]"
T = TypeVar("T")

PER_PAGE: Final[int] = 100
# seconds before each new try of a call GitHub answered with a 5xx
RETRY_DELAYS: Final[tuple[int, ...]] = (1, 3)
SERVER_ERROR: Final[re.Pattern[str]] = re.compile(r"HTTP 5\d\d")


class GhError(Exception):
    pass


def call(endpoint: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["gh", "api", endpoint], capture_output=True, text=True, check=False)


def gh(endpoint: str) -> Json:
    done: subprocess.CompletedProcess[str] = call(endpoint)
    delay: int
    for delay in RETRY_DELAYS:
        if done.returncode == 0 or not SERVER_ERROR.search(done.stderr):
            break
        time.sleep(delay)
        done = call(endpoint)
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
