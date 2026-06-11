#!/usr/bin/env python3
"""cursor-quota — SwiftBar plugin showing Cursor token usage and spend.

Menu bar shows the selected period's cost and tokens; the dropdown lists all
periods (click one to make it the menu-bar period) plus a per-model breakdown.

Auth is read from Cursor's local state DB (read-only) — no setup needed while
you're logged in to the Cursor app. Manual fallback: put your
WorkosCursorSessionToken cookie value (or just the JWT) in
~/.config/cursor-quota/token.

<xbar.title>cursor-quota</xbar.title>
<xbar.version>v1.0.0</xbar.version>
<xbar.author>Reinaldo Simoes</xbar.author>
<xbar.author.github>reinaldo-simoes-wp</xbar.author.github>
<xbar.desc>Cursor token usage and spend in your menu bar: per-period cost/tokens with a per-model breakdown, read straight from your local Cursor session.</xbar.desc>
<xbar.dependencies>python3</xbar.dependencies>
<xbar.abouturl>https://github.com/reinaldo-simoes-wp/cursor-quota</xbar.abouturl>

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
TEAMS_URL = "https://cursor.com/api/dashboard/teams"
ME_URL = "https://cursor.com/api/dashboard/get-me"
STATE_DB = os.path.expanduser(
    "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
)
CONFIG_DIR = os.path.expanduser("~/.config/cursor-quota")
PERIOD_FILE = os.path.join(CONFIG_DIR, "period")
SCOPE_FILE = os.path.join(CONFIG_DIR, "scope")
TOKEN_FILE = os.path.join(CONFIG_DIR, "token")
LIMITS_FILE = os.path.join(CONFIG_DIR, "limits")

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

SCOPES = ("you", "team")
DEFAULT_SCOPE = "you"


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


def read_scope():
    try:
        with open(SCOPE_FILE) as f:
            key = f.read().strip()
        return key if key in SCOPES else DEFAULT_SCOPE
    except OSError:
        return DEFAULT_SCOPE


def write_scope(key):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(SCOPE_FILE, "w") as f:
        f.write(key)


# Preset ceilings scale with the period; team scope doubles them.
LIMIT_PRESETS = {
    "daily": (25, 50, 100, 250, 500, 1000),
    "weekly": (100, 250, 500, 1000, 2500, 5000),
    "monthly": (500, 1000, 2500, 5000, 10000, 25000),
    "6months": (2500, 5000, 10000, 25000, 50000, 75000),
    "1year": (5000, 10000, 25000, 50000, 75000, 100000),
}


def limit_presets(scope, period):
    base = LIMIT_PRESETS[period]
    return tuple(v * 2 for v in base) if scope == "team" else base


def parse_dollars(s):
    try:
        v = float(s.lstrip("$").replace(",", ""))
        return v if v > 0 else None
    except ValueError:
        return None


def read_limits():
    """Optional spend ceilings for visibility, one '<scope> <period> <dollars>'
    per line in ~/.config/cursor-quota/limits, e.g. 'you daily 250'. Legacy
    '<period> <dollars>' lines count as scope 'you'. '#' comments ok."""
    limits = {}
    try:
        with open(LIMITS_FILE) as f:
            for raw in f:
                parts = raw.split("#")[0].split()
                if len(parts) >= 3 and parts[0] in SCOPES and parts[1] in PERIODS:
                    dollars = parse_dollars(parts[2])
                    if dollars:
                        limits[(parts[0], parts[1])] = dollars
                elif len(parts) >= 2 and parts[0] in PERIODS:
                    dollars = parse_dollars(parts[1])
                    if dollars:
                        limits[("you", parts[0])] = dollars
    except OSError:
        pass
    return limits


def is_limit_line(raw):
    parts = raw.split("#")[0].split()
    return (len(parts) >= 3 and parts[0] in SCOPES and parts[1] in PERIODS) or (
        len(parts) >= 2 and parts[0] in PERIODS
    )


def write_limits(limits):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    # Keep the user's comments and unrecognized lines; rewrite only the
    # recognized limit entries (in canonical '<scope> <period> <dollars>'
    # form). Write atomically so a crash can't truncate the file.
    kept = []
    try:
        with open(LIMITS_FILE) as f:
            kept = [ln.rstrip("\n") for ln in f if ln.strip() and not is_limit_line(ln)]
    except OSError:
        pass
    tmp = LIMITS_FILE + ".tmp"
    with open(tmp, "w") as f:
        for ln in kept:
            f.write(ln + "\n")
        for (scope, period), dollars in sorted(limits.items()):
            f.write(f"{scope} {period} {dollars:g}\n")
    os.replace(tmp, LIMITS_FILE)


def set_limit(scope, period, action):
    """action: 'off' or a dollar amount."""
    limits = read_limits()
    key = (scope, period)
    if action == "off":
        limits.pop(key, None)
    else:
        dollars = parse_dollars(action)
        if dollars:
            limits[key] = dollars
    write_limits(limits)


def limit_color(pct):
    if pct >= 90:
        return "red"
    if pct >= 70:
        return "orange"
    return None


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


def api_post(cookie, url, payload):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            "Origin": "https://cursor.com",
            "Cookie": f"WorkosCursorSessionToken={cookie}",
            "User-Agent": "cursor-quota (SwiftBar plugin)",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def post_usage(cookie, start_ms, end_ms, extras=None):
    payload = {"startDate": str(start_ms), "endDate": str(end_ms)}
    payload.update(extras or {})
    return api_post(cookie, API_URL, payload)


def identity(cookie):
    """Who are we, and can we see team-wide usage? Team admins can query the
    whole team; members are limited to their own usage by the API.

    Raises TokenError when the numeric user id can't be determined: without
    an explicit userId the API falls back to the dashboard default (team-wide
    for admins), which would show team data under a personal label."""
    try:
        me = api_post(cookie, ME_URL, {})
    except Exception as e:
        raise TokenError(f"Could not fetch Cursor identity: {e}")
    if not me.get("userId"):
        raise TokenError("Cursor identity has no user id — API change?")

    teams = []
    try:
        teams = api_post(cookie, TEAMS_URL, {}).get("teams") or []
    except Exception:
        pass
    # Admin status must come from the team the dashboard is scoped to, not
    # just any team the user belongs to.
    team_id = me.get("teamId")
    team = next((t for t in teams if t.get("id") == team_id), None)
    role = (team or {}).get("role") or ""
    return {
        "user_id": me["userId"],
        "team_id": team_id,
        "team_name": (team or {}).get("name") or me.get("teamName") or "team",
        "is_admin": "ADMIN" in role or "OWNER" in role,
    }


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


def fetch_range(cookie, start_ms, end_ms, extras=None, depth=0):
    try:
        return post_usage(cookie, start_ms, end_ms, extras)
    except urllib.error.HTTPError as e:
        if e.code != 400 or depth >= 3:
            raise
        split = split_boundary_ms(e, start_ms, end_ms)
        if not split:
            raise
        first = fetch_range(cookie, start_ms, split - 1, extras, depth + 1)
        second = fetch_range(cookie, split, end_ms, extras, depth + 1)
        return merge_usage(first, second)


def fetch_usage(cookie, days, extras=None):
    now = int(time.time() * 1000)
    return fetch_range(cookie, now - days * DAY_MS, now, extras)


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


def trigger_refresh():
    # Refresh only after the config write; a refresh=true on the menu item
    # would race with the write and read the old value (requiring two clicks).
    import subprocess

    subprocess.run(
        ["open", "-g", f"swiftbar://refreshplugin?name={os.path.basename(__file__)}"],
        check=False,
    )


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--set-period":
        if sys.argv[2] in PERIODS:
            write_period(sys.argv[2])
            trigger_refresh()
        return
    if len(sys.argv) >= 3 and sys.argv[1] == "--set-scope":
        if sys.argv[2] in SCOPES:
            write_scope(sys.argv[2])
            trigger_refresh()
        return
    if len(sys.argv) >= 5 and sys.argv[1] == "--set-limit":
        if sys.argv[2] in SCOPES and sys.argv[3] in PERIODS:
            set_limit(sys.argv[2], sys.argv[3], sys.argv[4])
            trigger_refresh()
        return

    selected = read_period()
    plugin = os.path.realpath(__file__)

    try:
        cookie = session_cookie()
        who = identity(cookie)
    except TokenError as e:
        print("⚠ Cursor")
        print("---")
        print(f"⚠ {e}")
        line("Refresh now", refresh="true")
        return

    scope = read_scope()
    # Team-wide data is admin-only; fall back to personal for members.
    if scope == "team" and not (who["is_admin"] and who["team_id"]):
        scope = "you"
    if scope == "team":
        extras = {"teamId": who["team_id"]}
        header = f"Cursor team usage ({who['team_name']})"
    else:
        # Explicit userId guarantees personal usage even for admins, whose
        # dashboard defaults to team-wide data.
        extras = {"userId": who["user_id"]}
        header = "Cursor usage (yours)"

    results, errors = {}, {}
    with ThreadPoolExecutor(max_workers=len(PERIODS)) as pool:
        futures = {
            key: pool.submit(fetch_usage, cookie, days, extras)
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

    limits = read_limits()

    # Menu bar line.
    label = PERIODS[selected][0]
    if selected in results:
        d = results[selected]
        cost_cents = d.get("totalCostCents") or 0
        cost = fmt_cost(cost_cents)
        limit = limits.get((scope, selected))
        params = {}
        if limit:
            cost = f"{cost}/${limit:,.0f}"
            color = limit_color(cost_cents / limit)
            if color:
                params["color"] = color
        line(f"{cost} · {fmt_tokens(io_tokens(d))}", **params)
    else:
        print("⚠ Cursor")
    print("---")
    print(f"{header} — {label} | size=12")
    print("---")

    # Scope toggle (admins only — the API limits members to their own usage).
    if who["is_admin"] and who["team_id"]:
        for key, name in (
            ("you", "You"),
            ("team", f"Team ({who['team_name']})"),
        ):
            mark = "✓ " if key == scope else "   "
            line(
                f"{mark}Scope: {name}",
                bash=plugin,
                param1="--set-scope",
                param2=key,
                terminal="false",
            )
        print("---")

    # Period rows (click to select).
    for key, (name, _) in PERIODS.items():
        mark = "✓ " if key == selected else "   "
        params = {}
        if key in results:
            d = results[key]
            cost_cents = d.get("totalCostCents") or 0
            text = (
                f"{mark}{name}: {fmt_cost(cost_cents)}"
                f" · {fmt_tokens(io_tokens(d))} tokens"
            )
            limit = limits.get((scope, key))
            if limit:
                pct = cost_cents / limit
                text += f" · {pct:.0f}% of ${limit:,.0f}"
                color = limit_color(pct)
                if color:
                    params["color"] = color
        else:
            text = f"{mark}{name}: ⚠ {errors.get(key, 'no data')}"
        line(
            text,
            bash=plugin,
            param1="--set-period",
            param2=key,
            terminal="false",
            **params,
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

    # Limits editor: SwiftBar has no real sliders, so each scope+period gets
    # a submenu with Off / − / + steppers and preset amounts.
    print("---")
    print("Limits")
    scope_rows = [("you", "You")]
    if who["is_admin"] and who["team_id"]:
        scope_rows.append(("team", f"Team ({who['team_name']})"))
    for scope_key, scope_name in scope_rows:
        for period_key, (period_name, _) in PERIODS.items():
            current = limits.get((scope_key, period_key))
            shown = f"${current:,.0f}" if current else "off"
            print(f"-- {scope_name} · {period_name}: {shown}")

            def limit_row(text, action, depth="----"):
                line(
                    f"{depth} {text}",
                    bash=plugin,
                    param1="--set-limit",
                    param2=scope_key,
                    param3=period_key,
                    param4=action,
                    terminal="false",
                )

            if current:
                limit_row("Off", "off")
                print("-------")
            for preset in limit_presets(scope_key, period_key):
                mark = "✓ " if current == preset else ""
                limit_row(f"{mark}${preset:,.0f}", str(preset))

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
