# cursor-quota

Menu bar gauge for your Cursor token usage and spend — inspired by
[claude-quota](https://github.com/grzegorz-raczek-unit8/claude-quota), but for
[Cursor](https://cursor.com).

- The menu bar shows the selected period's **spend and tokens**, e.g.
  `$4.12 · 1.2M` (tokens = input + output; cache tokens are in the dropdown).
- The dropdown lists **all periods** — Daily, Weekly, Monthly, 6 Months,
  1 Year — each with cost and tokens. **Click a period to make it the
  menu bar gauge.**
- Below that, a **per-model breakdown** for the selected period: cost,
  input+output tokens, and cache tokens.
- Optional **spend ceilings** per period, just for visibility: the menu bar
  shows `$237/$250` and turns orange at 70% and red at 90% of the ceiling.
- Refreshes every 5 minutes (SwiftBar filename convention) plus a manual
  "Refresh now" entry.

**macOS only** — it's a [SwiftBar](https://github.com/swiftbar/SwiftBar)
plugin, same as the original.

## Quick install

```sh
curl -fsSL https://raw.githubusercontent.com/reinaldo-simoes-wp/cursor-quota/main/install.sh | bash
```

## Install from a checkout

```sh
git clone https://github.com/reinaldo-simoes-wp/cursor-quota.git
cd cursor-quota
./install.sh
```

The installer sets up [SwiftBar](https://github.com/swiftbar/SwiftBar) via
Homebrew if you don't have it, then symlinks the plugin into your SwiftBar
plugin folder (`~/.swiftbar` by default).

## How it works

The plugin reads your Cursor login token from Cursor's local state database
(`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`,
**read-only** — it never modifies anything, so it can't log you out) and
queries the same usage endpoint that the [cursor.com usage
dashboard](https://cursor.com/dashboard/usage) uses
(`/api/dashboard/get-aggregated-usage-events`). No passwords, no scraping,
no third-party services.

Periods are rolling windows ending now: last 24 hours, 7 days, 30 days,
182 days, and 365 days. Long windows that span Cursor's backend shard
boundaries are split automatically and merged client-side (the API requires
it).

> **Note:** the endpoint is internal to Cursor's dashboard and undocumented,
> so a future Cursor change may require a small fix here.

> **Personal vs team usage:** the plugin always requests **your own usage**
> explicitly (even for team admins, whose dashboard defaults to team-wide
> data). Team admins additionally get a **Scope toggle** in the dropdown —
> `You` vs `Team (TeamName)` — to flip the gauges between personal and
> team-wide numbers. Members don't get the toggle because the API restricts
> team-wide usage to admins. The dropdown header always says which scope is
> shown: `Cursor usage (yours)` or `Cursor team usage (TeamName)`.

## Spend ceilings (optional)

To set a dollar ceiling per period — purely visual, nothing is enforced —
create `~/.config/cursor-quota/limits` with one `<period> <dollars>` per line
(`#` comments allowed):

```
daily 250
weekly 1000
monthly 2000
```

Periods with a ceiling show `$X.XX/$LIMIT` in the menu bar and `N% of $LIMIT`
in the dropdown, colored orange at ≥70% and red at ≥90%.

## Manual token (fallback)

If auto-detection fails (e.g. you don't run the Cursor app on this machine),
put a token in `~/.config/cursor-quota/token` — either:

- the full `WorkosCursorSessionToken` cookie value from
  [cursor.com/dashboard](https://cursor.com/dashboard) (DevTools >
  Application > Cookies), or
- a bare Cursor access JWT.

## Files

| Path | Purpose |
| --- | --- |
| `~/.config/cursor-quota/period` | Selected menu bar period (`daily`, `weekly`, `monthly`, `6months`, `1year`) |
| `~/.config/cursor-quota/scope` | Selected scope (`you` or `team`; `team` is admins-only) |
| `~/.config/cursor-quota/limits` | Optional spend ceilings per period (visibility only) |
| `~/.config/cursor-quota/token` | Optional manual token override |

## Troubleshooting

- **⚠ in the menu bar** — token missing or expired. Open the Cursor app once
  (it refreshes the token) and hit "Refresh now".
- **HTTP 401 on a period row** — same cause: stale token, re-login in Cursor.

## Uninstall

Delete `cursor-quota.5m.py` from your SwiftBar plugin folder
(`~/.swiftbar` by default).
