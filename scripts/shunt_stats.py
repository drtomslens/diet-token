#!/usr/bin/env python3
"""Print cumulative Local Shunt usage and estimated Gemini token savings."""
import json
import os
import sys
from pathlib import Path

LOG_PATH = Path(
    os.getenv(
        "LOCAL_SHUNT_LOG",
        str(Path(__file__).resolve().parent.parent / "notes" / "shunt_usage.jsonl"),
    )
).expanduser()


def main() -> None:
    if not LOG_PATH.is_file():
        print(f"No usage log found at {LOG_PATH}")
        sys.exit(0)

    entries = []
    with LOG_PATH.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    entries.append(json.loads(line))
                except json.JSONDecodeError:
                    pass

    if not entries:
        print("Usage log is empty.")
        return

    total_calls = len(entries)
    total_raw = sum(e.get("est_raw_tokens", 0) for e in entries)
    total_out = sum(e.get("est_summary_tokens", 0) for e in entries)
    total_saved = sum(e.get("est_gemini_tokens_saved", 0) for e in entries)
    avg_sec = sum(e.get("elapsed_sec", 0.0) for e in entries) / total_calls
    pct = (total_saved / total_raw * 100.0) if total_raw else 0.0

    print(f"Local Shunt Usage ({LOG_PATH.name})")
    print("-" * 48)
    print(f"Total calls:               {total_calls}")
    print(f"Est. raw tokens handled:   {total_raw:,}")
    print(f"Est. summary tokens sent:  {total_out:,}")
    print(f"Est. Gemini tokens saved:  {total_saved:,} ({pct:.1f}%)")
    print(f"Average latency:           {avg_sec:.1f}s")
    print("\nRecent calls:")
    for e in entries[-5:]:
        name = Path(e["paths"][0]).name if e.get("paths") else "?"
        print(
            f"  {e.get('ts', '')} | {name} | "
            f"saved ~{e.get('est_gemini_tokens_saved', 0):,} tok | "
            f"{e.get('elapsed_sec', 0):.1f}s"
            f"{' (truncated)' if e.get('truncated') else ''}"
        )


if __name__ == "__main__":
    main()
