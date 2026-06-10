#!/usr/bin/env python3
"""cursor-quota — SwiftBar plugin showing Cursor token usage and spend.

Menu bar shows the selected period's cost and tokens; the dropdown lists all
periods (click one to make it the menu-bar period) plus a per-model breakdown.

Auth is read from Cursor's local state DB (read-only) — no setup needed while
you're logged in to the Cursor app. Manual fallback: put your
WorkosCursorSessionToken cookie value (or just the JWT) in
~/.config/cursor-quota/token.

<swiftbar.title>cursor-quota</swiftbar.title>
<swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
<swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>
"""

import base64
import json
import os
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

VERSION = "1.0.0"
REPO_URL = "https://github.com/reinaldo-simoes-wp/cursor-quota"

API_URL = "https://cursor.com/api/dashboard/get-aggregated-usage-events"
STATE_DB = os.path.expanduser(
    "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
)
CONFIG_DIR = os.path.expanduser("~/.config/cursor-quota")
PERIOD_FILE = os.path.join(CONFIG_DIR, "period")
TOKEN_FILE = os.path.join(CONFIG_DIR, "token")

DAY_MS = 86_400_000
# key -> (label, window length in days)
PERIODS = {
    "daily": ("Daily", 1),
    "weekly": ("Weekly", 7),
    "monthly": ("Monthly", 30),
    "6months": ("6 Months", 182),
    "1year": ("1 Year", 365),
}
DEFAULT_PERIOD = "daily"


# --- period selection ---------------------------------------------------


def read_period():
    try:
        with open(PERIOD_FILE) as f:
            key = f.read().strip()
        return key if key in PERIODS else DEFAULT_PERIOD
    except OSError:
        return DEFAULT_PERIOD


def write_period(key):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(PERIOD_FILE, "w") as f:
        f.write(key)


# --- auth ----------------------------------------------------------------


class TokenError(Exception):
    pass


def jwt_claims(token):
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload))


def cookie_from_jwt(token):
    try:
        sub = jwt_claims(token)["sub"]
    except Exception:
        raise TokenError("Could not parse Cursor access token (not a JWT?)")
    user_id = sub.split("|")[-1]
    return f"{user_id}%3A%3A{token}"


def session_cookie():
    """Return the WorkosCursorSessionToken cookie value."""
    # Manual override first.
    try:
        with open(TOKEN_FILE) as f:
            tok = f.read().strip()
        if tok:
            # Already a full cookie value (userId%3A%3Ajwt) or a bare JWT.
            return tok if "%3A%3A" in tok else cookie_from_jwt(tok)
    except OSError:
        pass

    if not os.path.exists(STATE_DB):
        raise TokenError("Cursor state DB not found — is Cursor installed?")
    try:
        con = sqlite3.connect(f"file:{STATE_DB}?mode=ro", uri=True, timeout=5)
        # Cursor writes to this DB while running; wait briefly instead of
        # failing with "database is locked".
        con.execute("PRAGMA busy_timeout=5000")
        row = con.execute(
            "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'"
        ).fetchone()
        con.close()
    except sqlite3.Error as e:
        raise TokenError(f"Could not read Cursor state DB: {e}")
    if not row or not row[0]:
        raise TokenError("No Cursor access token — log in to the Cursor app")

    token = row[0]
    try:
        token = json.loads(token)  # value may be JSON-quoted
    except (json.JSONDecodeError, TypeError):
        pass

    exp = jwt_claims(token).get("exp")
    if exp and exp < time.time():
        raise TokenError("Cursor token expired — open Cursor to refresh it")
    return cookie_from_jwt(token)


# --- API -----------------------------------------------------------------


def post_usage(cookie, start_ms, end_ms):
    body = json.dumps({"startDate": str(start_ms), "endDate": str(end_ms)}).encode()
    req = urllib.request.Request(
        API_URL,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Origin": "https://cursor.com",
            "Cookie": f"WorkosCursorSessionToken={cookie}",
            "User-Agent": "cursor-quota (SwiftBar plugin)",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def merge_usage(a, b):
    """Combine two get-aggregated-usage-events responses."""
    merged = {}
    for field in (
        "totalInputTokens",
        "totalOutputTokens",
        "totalCacheWriteTokens",
        "totalCacheReadTokens",
    ):
        merged[field] = str(int(a.get(field) or 0) + int(b.get(field) or 0))
    merged["totalCostCents"] = (a.get("totalCostCents") or 0) + (
        b.get("totalCostCents") or 0
    )
    by_model = {}
    for resp in (a, b):
        for agg in resp.get("aggregations") or []:
            model = agg.get("modelIntent") or "unknown"
            cur = by_model.setdefault(model, {"modelIntent": model, "totalCents": 0})
            for field in (
                "inputTokens",
                "outputTokens",
                "cacheWriteTokens",
                "cacheReadTokens",
            ):
                cur[field] = str(int(cur.get(field) or 0) + int(agg.get(field) or 0))
            cur["totalCents"] += agg.get("totalCents") or 0
    merged["aggregations"] = list(by_model.values())
    return merged


def split_boundary_ms(http_error, start_ms, end_ms):
    """Long windows can span backend shards; the 400 response names the split
    dates ("Split the query at one of those dates"). The message also echoes
    the requested window, so only consider dates strictly inside it."""
    try:
        detail = http_error.read().decode()
    except Exception:
        return None
    if "Split the query" not in detail:
        return None
    stamps = [
        int(datetime.fromisoformat(d).replace(tzinfo=timezone.utc).timestamp() * 1000)
        for d in re.findall(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?)Z", detail)
    ]
    inside = [s for s in stamps if start_ms < s < end_ms]
    return max(inside) if inside else None


def fetch_range(cookie, start_ms, end_ms, depth=0):
    try:
        return post_usage(cookie, start_ms, end_ms)
    except urllib.error.HTTPError as e:
        if e.code != 400 or depth >= 3:
            raise
        split = split_boundary_ms(e, start_ms, end_ms)
        if not split:
            raise
        first = fetch_range(cookie, start_ms, split - 1, depth + 1)
        second = fetch_range(cookie, split, end_ms, depth + 1)
        return merge_usage(first, second)


def fetch_usage(cookie, days):
    now = int(time.time() * 1000)
    return fetch_range(cookie, now - days * DAY_MS, now)


# --- formatting ----------------------------------------------------------


def fmt_tokens(n):
    n = int(n)
    for div, suffix in ((1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")):
        if n >= div:
            v = n / div
            return f"{v:.1f}{suffix}" if v < 100 else f"{v:.0f}{suffix}"
    return str(n)


def fmt_cost(cents):
    return f"${cents / 100:,.2f}"


def io_tokens(d):
    return int(d.get("totalInputTokens") or 0) + int(d.get("totalOutputTokens") or 0)


def line(text, **params):
    opts = " ".join(f"{k}={quote_param(v)}" for k, v in params.items())
    print(f"{text} | {opts}" if opts else text)


def quote_param(v):
    s = str(v)
    return f'"{s}"' if " " in s else s


# --- main ----------------------------------------------------------------


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--set-period":
        if sys.argv[2] in PERIODS:
            write_period(sys.argv[2])
        return

    selected = read_period()
    plugin = os.path.realpath(__file__)

    try:
        cookie = session_cookie()
    except TokenError as e:
        print("⚠ Cursor")
        print("---")
        print(f"⚠ {e}")
        line("Refresh now", refresh="true")
        return

    results, errors = {}, {}
    with ThreadPoolExecutor(max_workers=len(PERIODS)) as pool:
        futures = {
            key: pool.submit(fetch_usage, cookie, days)
            for key, (_, days) in PERIODS.items()
        }
        for key, fut in futures.items():
            try:
                results[key] = fut.result()
            except urllib.error.HTTPError as e:
                errors[key] = f"HTTP {e.code}" + (
                    " — token rejected, re-login in Cursor" if e.code == 401 else ""
                )
            except Exception as e:
                errors[key] = str(e)

    # Menu bar line.
    label = PERIODS[selected][0]
    if selected in results:
        d = results[selected]
        print(f"{fmt_cost(d.get('totalCostCents') or 0)} · {fmt_tokens(io_tokens(d))}")
    else:
        print("⚠ Cursor")
    print("---")
    print(f"Cursor usage — {label} | size=12")
    print("---")

    # Period rows (click to select).
    for key, (name, _) in PERIODS.items():
        mark = "✓ " if key == selected else "   "
        if key in results:
            d = results[key]
            text = (
                f"{mark}{name}: {fmt_cost(d.get('totalCostCents') or 0)}"
                f" · {fmt_tokens(io_tokens(d))} tokens"
            )
        else:
            text = f"{mark}{name}: ⚠ {errors.get(key, 'no data')}"
        line(
            text,
            bash=plugin,
            param1="--set-period",
            param2=key,
            terminal="false",
            refresh="true",
        )

    # Per-model breakdown for the selected period.
    d = results.get(selected)
    if d:
        aggs = sorted(
            d.get("aggregations") or [],
            key=lambda a: a.get("totalCents") or 0,
            reverse=True,
        )
        if aggs:
            print("---")
            print(f"Models ({label.lower()}) | size=12")
            for a in aggs:
                tokens = int(a.get("inputTokens") or 0) + int(a.get("outputTokens") or 0)
                cache = int(a.get("cacheReadTokens") or 0) + int(
                    a.get("cacheWriteTokens") or 0
                )
                model = a.get("modelIntent") or "unknown"
                text = (
                    f"{model}: {fmt_cost(a.get('totalCents') or 0)}"
                    f" · {fmt_tokens(tokens)} io · {fmt_tokens(cache)} cache"
                )
                line(text, font="Menlo", size=11)
        cache_total = int(d.get("totalCacheReadTokens") or 0) + int(
            d.get("totalCacheWriteTokens") or 0
        )
        line(f"Cache tokens ({label.lower()}): {fmt_tokens(cache_total)}", size=11)

    print("---")
    line("Refresh now", refresh="true")
    line("Open Cursor dashboard", href="https://cursor.com/dashboard/usage")
    print("About")
    line(f"-- cursor-quota v{VERSION}", size=12)
    line("-- Token usage & spend for Cursor, in your menu bar", size=11)
    line("-- Inspired by claude-quota", size=11)
    print("-----")
    line("-- GitHub", href=REPO_URL)
    line("-- Report an issue", href=f"{REPO_URL}/issues")
    print("-----")
    line("-- Uses Cursor's undocumented dashboard API — may break without notice", size=11)
    line("-- Reads your Cursor login token locally (read-only); nothing leaves your Mac except calls to cursor.com", size=11)


if __name__ == "__main__":
    main()
