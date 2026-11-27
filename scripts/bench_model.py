#!/usr/bin/env python3
"""Quick local benchmark for OpenAI-compatible servers (llama-server / mlx_lm.server)."""
import json
import sys
import time
import urllib.request

URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8080/v1/chat/completions"
MODEL = sys.argv[2] if len(sys.argv) > 2 else "inkling-2-mini"

PROMPT = (
    "Write a concise Python function implementing a 1D FDTD Yee-grid solver "
    "for Maxwell's equations with Mur first-order absorbing boundary conditions. "
    "Include stability (CFL) check."
)

payload = json.dumps({
    "model": MODEL,
    "messages": [{"role": "user", "content": PROMPT}],
    "max_tokens": 512,
    "temperature": 0.2,
}).encode("utf-8")

req = urllib.request.Request(
    URL,
    data=payload,
    headers={"Content-Type": "application/json", "Authorization": "Bearer local"},
)

print(f"Benchmarking {MODEL} at {URL} ...")
t0 = time.perf_counter()
try:
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read().decode("utf-8"))
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code}: {e.read().decode('utf-8', errors='replace')}")
    sys.exit(1)
elapsed = time.perf_counter() - t0

usage = data.get("usage", {})
timings = data.get("timings", {})

prompt_toks = usage.get("prompt_tokens", timings.get("prompt_n", "?"))
gen_toks = usage.get("completion_tokens", timings.get("predicted_n", "?"))
prompt_tps = timings.get("prompt_per_second")
gen_tps = timings.get("predicted_per_second")

print(f"\n--- Results ({MODEL}) ---")
print(f"Total wall time   : {elapsed:.2f} s")
print(f"Prompt tokens     : {prompt_toks}")
print(f"Generated tokens  : {gen_toks}")
if prompt_tps is not None:
    print(f"Prefill speed     : {prompt_tps:.1f} tok/s")
if gen_tps is not None:
    print(f"Decode speed      : {gen_tps:.1f} tok/s")
elif isinstance(gen_toks, int) and elapsed > 0:
    print(f"Effective speed   : {gen_toks / elapsed:.1f} tok/s")
