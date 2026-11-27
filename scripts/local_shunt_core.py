#!/usr/bin/env python3
"""
DietToken (Local Shunt) Core — hot-reloaded by local_shunt_mcp.py on every MCP call.
Edits to this file take effect immediately without restarting the MCP server.
"""
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def _env(primary: str, legacy: str, default: str) -> str:
    return os.getenv(primary) or os.getenv(legacy) or default


BASE_URL = _env("DIET_TOKEN_BASE_URL", "LOCAL_SHUNT_BASE_URL", "http://127.0.0.1:8080/v1")
EXPLICIT_MODEL = os.getenv("DIET_TOKEN_MODEL") or os.getenv("LOCAL_SHUNT_MODEL")
DEFAULT_MODEL = EXPLICIT_MODEL or "gemma-4-26b-a4b"
MAX_INPUT_CHARS = int(_env("DIET_TOKEN_MAX_CHARS", "LOCAL_SHUNT_MAX_CHARS", "160000"))
MAX_SEARCH_CHARS = int(_env("DIET_TOKEN_MAX_SEARCH_CHARS", "LOCAL_SHUNT_MAX_SEARCH_CHARS", "90000"))
TIMEOUT_SEC = int(_env("DIET_TOKEN_TIMEOUT", "LOCAL_SHUNT_TIMEOUT", "165"))
LOG_PATH = Path(
    _env(
        "DIET_TOKEN_LOG",
        "LOCAL_SHUNT_LOG",
        str(Path(__file__).resolve().parent.parent / "notes" / "shunt_usage.jsonl"),
    )
).expanduser()
CACHE_PATH = Path(
    _env(
        "DIET_TOKEN_CACHE",
        "LOCAL_SHUNT_CACHE",
        str(Path(__file__).resolve().parent.parent / "notes" / "shunt_cache.json"),
    )
).expanduser()

_DETECTED_MODEL: str | None = None

TOOLS = [
    {
        "name": "local_summarize_file",
        "description": (
            "Read a large file locally using the local Apple Silicon LLM (zero cloud quota) "
            "and return a concise, targeted summary with exact line-number citations (e.g., L120-L145) "
            "so the primary agent can then read only the exact lines needed."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute path to the text/code/log/PDF file."},
                "question": {
                    "type": "string",
                    "description": "What you want to find, summarize, or extract from the file.",
                },
            },
            "required": ["path", "question"],
        },
    },
    {
        "name": "local_search_files",
        "description": (
            "Scan multiple large files (docs, logs, scripts) locally using the local Apple Silicon LLM "
            "and return a concise cross-file answer with file paths and line numbers."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "paths": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "List of absolute file paths to inspect (up to 6 files).",
                },
                "question": {
                    "type": "string",
                    "description": "Specific question or extraction goal across these files.",
                },
            },
            "required": ["paths", "question"],
        },
    },
]


def resolve_model_name() -> str:
    """Use explicit model env var if set; otherwise auto-detect first model from /v1/models."""
    global _DETECTED_MODEL
    if EXPLICIT_MODEL:
        return EXPLICIT_MODEL
    if _DETECTED_MODEL:
        return _DETECTED_MODEL
    try:
        req = urllib.request.Request(
            f"{BASE_URL.rstrip('/')}/models",
            headers={"Authorization": "Bearer local"},
        )
        with urllib.request.urlopen(req, timeout=1.5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        models = data.get("data") or []
        if models and isinstance(models[0], dict) and models[0].get("id"):
            _DETECTED_MODEL = str(models[0]["id"])
            return _DETECTED_MODEL
    except Exception:
        pass
    return DEFAULT_MODEL


def call_local_llm(system_prompt: str, user_prompt: str) -> tuple[str, float, dict, str]:
    url = f"{BASE_URL.rstrip('/')}/chat/completions"
    req_model = resolve_model_name()
    payload = json.dumps({
        "model": req_model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": 0.2,
        "max_tokens": 1200,
        "reasoning_budget": 0,
        "chat_template_kwargs": {"enable_thinking": False},
    }).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json", "Authorization": "Bearer local"},
    )
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    elapsed = time.perf_counter() - t0
    content = data["choices"][0]["message"].get("content", "").strip()
    usage = data.get("usage") or {}
    actual_model = data.get("model") or req_model
    return content, elapsed, usage, actual_model


def log_usage(entry: dict) -> None:
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception:
        pass


def _file_sig(path_str: str) -> str:
    st = Path(path_str).expanduser().stat()
    return f"{Path(path_str).expanduser().resolve()}:{st.st_mtime_ns}:{st.st_size}"


def cache_get(key: str) -> str | None:
    try:
        if CACHE_PATH.is_file():
            data = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
            return data.get(key)
    except Exception:
        pass
    return None


def cache_set(key: str, value: str) -> None:
    try:
        CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        data = {}
        if CACHE_PATH.is_file():
            try:
                data = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
            except Exception:
                data = {}
        data[key] = value
        if len(data) > 100:
            for old_k in list(data.keys())[:-100]:
                del data[old_k]
        CACHE_PATH.write_text(json.dumps(data), encoding="utf-8")
    except Exception:
        pass


def extract_pdf_text(p: Path) -> str:
    if shutil.which("pdftotext"):
        res = subprocess.run(
            ["pdftotext", str(p), "-"],
            capture_output=True,
            text=True,
            check=True,
        )
        return res.stdout

    for mod_name in ("pypdf", "PyPDF2"):
        try:
            mod = __import__(mod_name)
            reader = mod.PdfReader(str(p))
            return "\n\n".join(
                f"--- Page {i} ---\n{page.extract_text() or ''}"
                for i, page in enumerate(reader.pages, start=1)
            )
        except ImportError:
            pass

    try:
        import fitz  # PyMuPDF

        with fitz.open(str(p)) as doc:
            return "\n\n".join(
                f"--- Page {i} ---\n{page.get_text()}"
                for i, page in enumerate(doc, start=1)
            )
    except ImportError:
        pass

    if sys.platform == "darwin" and shutil.which("osascript"):
        jxa = """
ObjC.import('Foundation');
ObjC.import('PDFKit');
function run(argv) {
    var url = $.NSURL.fileURLWithPath(argv[0]);
    var doc = $.PDFDocument.alloc.initWithURL(url);
    if (!doc || doc.isNil()) { throw new Error('Failed to open PDF'); }
    var n = doc.pageCount;
    var out = [];
    for (var i = 0; i < n; i++) {
        var page = doc.pageAtIndex(i);
        var txt = ObjC.unwrap(page.string) || '';
        out.push('--- Page ' + (i + 1) + ' ---\\n' + txt);
    }
    return out.join('\\n\\n');
}
"""
        res = subprocess.run(
            ["osascript", "-l", "JavaScript", "-e", jxa, str(p)],
            capture_output=True,
            text=True,
            check=True,
        )
        return res.stdout

    raise RuntimeError(
        "No PDF extractor available. Install poppler (`brew install poppler`) or `pip install pypdf`."
    )


def read_numbered(path_str: str, max_chars: int | None) -> tuple[str, int, int, bool]:
    p = Path(path_str).expanduser()
    if p.suffix.lower() == ".pdf":
        raw = extract_pdf_text(p)
    else:
        raw = p.read_text(encoding="utf-8", errors="replace")
    lines = raw.splitlines()
    numbered = "\n".join(f"L{i}: {line}" for i, line in enumerate(lines, start=1))
    truncated = False
    if max_chars is not None and len(numbered) > max_chars:
        truncated = True
        numbered = numbered[:max_chars] + f"\n... [truncated at {max_chars} chars of {len(numbered)}]"
    return numbered, len(lines), len(raw), truncated


def _split_chunks(numbered: str, chunk_chars: int) -> list[str]:
    chunks: list[str] = []
    cur: list[str] = []
    cur_len = 0
    for line in numbered.splitlines():
        line_len = len(line) + 1
        if cur and cur_len + line_len > chunk_chars:
            chunks.append("\n".join(cur))
            cur = [line]
            cur_len = line_len
        else:
            cur.append(line)
            cur_len += line_len
    if cur:
        chunks.append("\n".join(cur))
    return chunks


def _summarize_chunked(
    sys_prompt: str, path_str: str, n_lines: int, numbered: str, question: str, chunk_chars: int
) -> tuple[str, float, dict, str, int]:
    chunks = _split_chunks(numbered, chunk_chars)
    partials: list[str] = []
    total_elapsed = 0.0
    total_prompt_tok = 0
    total_comp_tok = 0
    actual_model = DEFAULT_MODEL
    for idx, ch in enumerate(chunks, start=1):
        prompt = (
            f"File: {path_str} ({n_lines} lines, chunk {idx}/{len(chunks)})\n\n"
            f"{ch}\n\nQuestion: {question}"
        )
        part, el, us, actual_model = call_local_llm(sys_prompt, prompt)
        total_elapsed += el
        total_prompt_tok += int(us.get("prompt_tokens") or 0)
        total_comp_tok += int(us.get("completion_tokens") or 0)
        partials.append(f"--- Chunk {idx}/{len(chunks)} ---\n{part}")

    if len(partials) == 1:
        merged = partials[0].split("\n", 1)[1]
        usage = {"prompt_tokens": total_prompt_tok, "completion_tokens": total_comp_tok}
        return merged, total_elapsed, usage, actual_model, 1

    merge_prompt = (
        f"File: {path_str} ({n_lines} lines, {len(chunks)} chunks summarized)\n\n"
        + "\n\n".join(partials)
        + f"\n\nMerge these chunk summaries into one concise bullet-point answer to: {question}. "
        "Preserve all exact line citations (e.g., L42-L68) and remove duplicates."
    )
    merged, el, us, actual_model = call_local_llm(sys_prompt, merge_prompt)
    total_elapsed += el
    total_prompt_tok += int(us.get("prompt_tokens") or 0)
    final_comp_tok = int(us.get("completion_tokens") or max(1, round(len(merged) / 4)))
    usage = {"prompt_tokens": total_prompt_tok, "completion_tokens": final_comp_tok}
    return merged, total_elapsed, usage, actual_model, len(chunks)


def handle_tool_call(name: str, args: dict) -> str:
    sys_prompt = (
        "You are a precise local code/document reader assisting a primary coding agent. "
        "Answer the question concisely in bullet points. ALWAYS cite exact line ranges "
        "(e.g., L42-L68) for every function, class, bug, or fact you reference. "
        "Do not invent code or facts not present in the provided text."
    )
    if name == "local_summarize_file":
        path_str = args["path"]
        question = args["question"]
        cache_key = f"sum|{_file_sig(path_str)}|{question.strip()}"
        cached = cache_get(cache_key)
        if cached is not None:
            return cached.replace("[Local Shunt | ", "[Local Shunt (cached) | ", 1)
        numbered, n_lines, raw_chars, _ = read_numbered(path_str, None)
        n_chunks = 1
        if len(numbered) <= MAX_INPUT_CHARS:
            # Put file content BEFORE question so llama-server reuses the KV-cache prefix across follow-up questions
            user_prompt = f"File: {path_str} ({n_lines} lines)\n\n{numbered}\n\nQuestion: {question}"
            try:
                summary, elapsed, usage, actual_model = call_local_llm(sys_prompt, user_prompt)
            except urllib.error.HTTPError as e:
                if e.code == 400:
                    # Context window exceeded (e.g., 32K model on a huge file) -> auto-chunk safely
                    fallback_chunk = min(MAX_INPUT_CHARS // 2, 70000)
                    summary, elapsed, usage, actual_model, n_chunks = _summarize_chunked(
                        sys_prompt, path_str, n_lines, numbered, question, fallback_chunk
                    )
                else:
                    raise
        else:
            summary, elapsed, usage, actual_model, n_chunks = _summarize_chunked(
                sys_prompt, path_str, n_lines, numbered, question, MAX_INPUT_CHARS
            )
        raw_tok = max(1, round(raw_chars / 4))
        out_tok = int(usage.get("completion_tokens") or max(1, round(len(summary) / 4)))
        saved_tok = max(0, raw_tok - out_tok)
        saved_pct = max(0.0, (1.0 - out_tok / max(raw_tok, 1)) * 100.0)
        log_usage({
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "tool": name,
            "model": actual_model,
            "paths": [path_str],
            "lines": n_lines,
            "raw_chars": raw_chars,
            "summary_chars": len(summary),
            "est_raw_tokens": raw_tok,
            "est_summary_tokens": out_tok,
            "est_gemini_tokens_saved": saved_tok,
            "local_prompt_tokens": usage.get("prompt_tokens"),
            "local_completion_tokens": usage.get("completion_tokens"),
            "elapsed_sec": round(elapsed, 2),
            "chunks": n_chunks,
        })
        chunk_tag = f" | {n_chunks} chunks" if n_chunks > 1 else ""
        header = (
            f"[Local Shunt | {actual_model} | {elapsed:.1f}s | "
            f"{n_lines} lines | ~{raw_tok:,} -> ~{out_tok:,} tok (~{saved_tok:,} cloud tok saved, {saved_pct:.0f}%)"
            f"{chunk_tag}]\n\n"
        )
        result = header + summary
        cache_set(cache_key, result)
        return result

    if name == "local_search_files":
        paths = args["paths"][:6]
        question = args["question"]
        cache_key = "search|" + "|".join(_file_sig(p) for p in paths) + f"|{question.strip()}"
        cached = cache_get(cache_key)
        if cached is not None:
            return cached.replace("[Local Shunt | ", "[Local Shunt (cached) | ", 1)
        per_file_budget = MAX_SEARCH_CHARS // max(len(paths), 1)
        blocks = []
        total_chars = 0
        for p_str in paths:
            numbered, n_lines, raw_chars, _ = read_numbered(p_str, per_file_budget)
            total_chars += raw_chars
            blocks.append(f"=== FILE: {p_str} ({n_lines} lines) ===\n{numbered}")
        # Put file contents BEFORE question for KV-cache prefix reuse
        user_prompt = "\n\n".join(blocks) + f"\n\nQuestion: {question}"
        summary, elapsed, usage, actual_model = call_local_llm(sys_prompt, user_prompt)
        raw_tok = max(1, round(total_chars / 4))
        out_tok = int(usage.get("completion_tokens") or max(1, round(len(summary) / 4)))
        saved_tok = max(0, raw_tok - out_tok)
        saved_pct = max(0.0, (1.0 - out_tok / max(raw_tok, 1)) * 100.0)
        log_usage({
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "tool": name,
            "model": actual_model,
            "paths": paths,
            "raw_chars": total_chars,
            "summary_chars": len(summary),
            "est_raw_tokens": raw_tok,
            "est_summary_tokens": out_tok,
            "est_gemini_tokens_saved": saved_tok,
            "local_prompt_tokens": usage.get("prompt_tokens"),
            "local_completion_tokens": usage.get("completion_tokens"),
            "elapsed_sec": round(elapsed, 2),
        })
        header = (
            f"[Local Shunt | {actual_model} | {elapsed:.1f}s | "
            f"{len(paths)} files | ~{raw_tok:,} -> ~{out_tok:,} tok (~{saved_tok:,} cloud tok saved, {saved_pct:.0f}%)]\n\n"
        )
        result = header + summary
        cache_set(cache_key, result)
        return result

    raise ValueError(f"Unknown tool: {name}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: local_shunt_core.py <file_path> [question]", file=sys.stderr)
        sys.exit(1)
    q = sys.argv[2] if len(sys.argv) > 2 else "Summarize this file with line-number citations."
    print(handle_tool_call("local_summarize_file", {"path": sys.argv[1], "question": q}))
