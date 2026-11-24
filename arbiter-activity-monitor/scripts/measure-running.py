"""Measure the already-open release app; never launch or control other apps."""
import json
import subprocess
import time


def running_pid() -> int:
    lines = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True).splitlines()
    matches = [int(line.split()[0]) for line in lines
               if line.strip().endswith("/arbiter-activity-monitor.app/Contents/MacOS/arbiter-activity-monitor")]
    if len(matches) != 1:
        raise SystemExit("Open exactly one release arbiter-activity-monitor window first.")
    return matches[0]


def sample(pid: int) -> tuple[float, float]:
    fields = subprocess.check_output(["ps", "-p", str(pid), "-o", "time=,rss="], text=True).split()
    parts = fields[0].split(":")
    seconds = sum(float(value) * 60 ** index for index, value in enumerate(reversed(parts)))
    return seconds, int(fields[1]) / 1024


if __name__ == "__main__":
    pid = running_pid()
    time.sleep(5)  # Exclude launch/layout warmup.
    start, rss = sample(pid)
    began = time.monotonic()
    time.sleep(30)
    end, final = sample(pid)
    duration = time.monotonic() - began
    print(json.dumps({"pid": pid, "seconds": round(duration, 2),
                      "cpuPercentOneCore": round((end - start) / duration * 100, 2),
                      "rssMiBStart": round(rss, 2), "rssMiBEnd": round(final, 2)}, indent=2))
