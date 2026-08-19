# cursor-quota

Menu bar gauge for your Cursor token usage and spend — inspired by
[claude-quota](https://github.com/grzegorz-raczek-unit8/claude-quota), but for
[Cursor](https://cursor.com).

- The menu bar shows the selected period's **spend and tokens**, e.g.
  `$4.12 · 1.2M` (tokens = input + output; cache tokens are in the dropdown).
- The dropdown lists **all periods** — Daily, Weekly, Monthly, 6 Months,
  1 Year — each with cost and tokens. **Click a period to make it the
  menu bar gauge.**
- A **Display** submenu switches what the menu bar shows for the selected
  period: `Total ($ · tokens)` (default), `$ / hour`, `$ / minute`,
  `tokens / hour`, or `tokens / minute`. Rates are the period's average
  (total ÷ window), so `Daily` gives the most current rate and longer
  periods give long-run averages.
- Below that, a **per-model breakdown** for the selected period: cost,
  input+output tokens, and cache tokens.
- Optional **spend ceilings** per period, just for visibility: the menu bar
  shows `$237/$250` and turns orange at 70% and red at 90% of the ceiling.
- A **dot-matrix sparkline** sits left of the numbers, showing the selected
  period's spend split into five equal buckets — so you can see at a glance
  whether usage is ramping up or tailing off. It animates as a travelling
  wave while a refresh is in flight, and takes the same orange/red tint as
  the gauge when a ceiling is set.
- Refreshes every 5 minutes plus a manual "Refresh now" entry.

**macOS only** — native menu bar app (macOS 13+). No SwiftBar required.

## Quick install

Build from a checkout (requires Xcode Command Line Tools / Swift):

```sh
git clone https://github.com/reinaldo-simoes-wp/cursor-quota.git
cd cursor-quota
./install.sh
```

This builds `CursorQuota.app`, installs it to `/Applications`, opens it, and
removes any legacy SwiftBar plugin symlink if present.

Once a version has been tagged you can instead download
`CursorQuota-<version>.zip` from the
[latest release](https://github.com/reinaldo-simoes-wp/cursor-quota/releases/latest),
move `CursorQuota.app` to `/Applications`, and open it.

## Updating

The app does not update itself — replace the copy in `/Applications`:

- **Installed from a checkout** — `git pull && ./install.sh`, which rebuilds,
  replaces `/Applications/CursorQuota.app`, and relaunches it.
- **Installed from a release** — quit CursorQuota, download the new
  `CursorQuota-<version>.zip`, and drag the app over the old one. Drag over,
  don't merge into, the existing bundle so nothing stale is left behind.

**About → Latest release** in the menu opens the download page.

Your settings live in `~/.config/cursor-quota/` and survive replacing the app.

## How it works

The app reads your Cursor login token from Cursor's local state database
(`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`,
**read-only** — it never modifies anything, so it can't log you out) and
queries the same usage endpoints that the [cursor.com usage
dashboard](https://cursor.com/dashboard/usage) uses
(`/api/dashboard/get-aggregated-usage-events` for longer windows, plus
`/api/dashboard/get-filtered-usage-events` for the last few days). No
passwords, no scraping, no third-party services.

Periods are rolling windows ending now: last 24 hours, 7 days, 30 days,
182 days, and 365 days. Long windows that span Cursor's backend shard
boundaries are split automatically and merged client-side (the API requires
it). Cursor's aggregate totals lag about five days, so a rolling 24-hour
window comes back empty; the app fills that gap (and the recent tail of
longer periods) from the usage-event log.

> **Note:** the endpoint is internal to Cursor's dashboard and undocumented,
> so a future Cursor change may require a small fix here.

> **Personal vs team usage:** the app always requests **your own usage**
> explicitly (even for team admins, whose dashboard defaults to team-wide
> data). Team admins additionally get a **Scope toggle** in the dropdown —
> `You` vs `Team (TeamName)` — to flip the gauges between personal and
> team-wide numbers. Members don't get the toggle because the API restricts
> team-wide usage to admins. The dropdown header always says which scope is
> shown: `Cursor usage (yours)` or `Cursor team usage (TeamName)`.

## Spend ceilings (optional)

Dollar ceilings per period — purely visual, nothing is enforced. Set them from
the **Limits** submenu in the dropdown: each scope+period has preset amounts
scaled to the cadence (daily $25–$1k up to 1-year $5k–$100k; team presets are
double) and an `Off` entry. Ceilings are kept **per scope**: `You` and — for
team admins — `Team (name)` have independent values.

Periods with a ceiling show `$X.XX/$LIMIT` in the menu bar and `N% of $LIMIT`
in the dropdown, colored orange at ≥70% and red at ≥90%.

Under the hood they live in `~/.config/cursor-quota/limits`, one
`<scope> <period> <dollars>` per line (`#` comment lines allowed; legacy
`<period> <dollars>` lines are read as scope `you`). Edit the file directly
for custom amounts that aren't in the presets — they show up the same way.
Picking a preset from the menu rewrites the recognized limit lines in
canonical form (standalone comment lines are kept; inline `#` comments on
limit lines are not):

```
you daily 375
you weekly 1000
team monthly 50000
```

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
| `~/.config/cursor-quota/display` | Menu bar display mode (`total`, `cost_hr`, `cost_min`, `tok_hr`, `tok_min`) |
| `~/.config/cursor-quota/limits` | Optional spend ceilings per scope+period (visibility only, editable from the Limits submenu) |
| `~/.config/cursor-quota/token` | Optional manual token override |

## Trend sparkline

The glyph buckets the selected period into five equal slices and scales each
bucket's spend against the busiest one, so whenever there is any spend the
tallest column is five dots. If every bucket is zero, all five sit at the
baseline.

Each bucket is resolved against Cursor's ~5-day aggregate lag rather than
blindly merged:

| Bucket | Source |
| --- | --- |
| Entirely newer than the lag | The usage-event log already in memory — no extra requests |
| Entirely older than the lag | One aggregate call for that slice |
| Straddling the boundary | Aggregate before the boundary plus event-log data after it |

So Daily costs nothing extra, and longer periods add at most five parallel
calls. Switching periods refetches **only** the sparkline (totals for every
period are already cached) and results are memoized per scope and period, so
flipping back and forth is free. Changing scope clears the cache.

If any bucket fails — or the usage-event log itself failed, which would make
recent buckets look empty — the glyph drops to a flat baseline instead of
drawing the failure as a dip. The baseline also shows while a token error is
displayed. On launch you get the loading wave rather than the baseline,
because the first refresh starts immediately.

The sparkline picks up the ceiling tint in the default `Total ($ · tokens)`
display. Rate displays never color the gauge, since a ceiling is a total.

## Building from source

```sh
./scripts/build-app.sh   # produces ./CursorQuota.app
open CursorQuota.app
```

Two helper scripts support the menu bar UI:

| Script | Purpose |
| --- | --- |
| `scripts/make-icon.swift` | Composites `assets/icon-source.png` onto the macOS icon grid and runs `iconutil` to write `CursorQuota/AppIcon.icns`. Run from the repo root. |
| `scripts/preview-menubar.sh` | Renders the menu bar label (trend sparkline, ceiling colors, loading frames) to `/tmp/menubar-preview.png` without needing screen-recording permission |

`AppIcon.icns` lives in the repo, so a normal build does not regenerate it —
only rerun `make-icon.swift` after changing the source art.

`build-app.sh` produces a universal Apple Silicon + Intel app and verifies the
bundle signature. Local builds use an ad-hoc signature. Release builds can set
`CODE_SIGN_IDENTITY` to a Developer ID Application identity.

## Releases

Releases are automated by `.github/workflows/release.yml`:

1. Update both `CFBundleShortVersionString` and `CFBundleVersion` in
   `CursorQuota/Info.plist`.
2. Merge and verify CI on `main` (the release workflow enforces both ancestry
   and a successful completed CI run for the tagged commit).
3. Create and push a matching tag, for example:

   ```sh
   git tag v2.0.0
   git push origin v2.0.0
   ```

The tag workflow validates the version, builds a universal app, packages a zip
and all available dSYMs, and publishes them through a draft so nobody can
download a half-uploaded release. Reruns safely replace existing assets.

Without Apple credentials the workflow signs ad-hoc, which means the first
launch of a downloaded build needs right-click → Open. For a warning-free
install, configure these repository secrets; the same workflow then signs with
Developer ID, submits the archive for notarization, and staples the ticket:

- `DEVELOPER_ID_APPLICATION_P12` — base64-encoded Developer ID Application
  certificate and private key
- `DEVELOPER_ID_APPLICATION_PASSWORD` — password for that `.p12`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`

## Legacy SwiftBar plugin

[`cursor-quota.5m.py`](cursor-quota.5m.py) is kept for reference. New installs
use the native app. If you still have the SwiftBar plugin symlinked in
`~/.swiftbar`, `./install.sh` removes it automatically.

## Troubleshooting

- **⚠ in the menu bar** — token missing or expired. Open the Cursor app once
  (it refreshes the token) and hit "Refresh now".
- **⚠ with an HTTP 401 message** — same cause: stale token, re-login in Cursor.
  A 401 on any period is treated as a session failure, so the whole dropdown
  switches to the error state rather than showing one bad row.
- **Daily shows $0.00 · 0** — Cursor's aggregate usage API lags about five
  days, so a rolling 24h query returns empty. The app fills that from the
  usage-event log; hit "Refresh now" after updating. If Daily still shows $0,
  there is no usage in that window (or the event log failed — look for ⚠ on
  the Daily row).
- **Gatekeeper blocks a source build** — `./install.sh` uses an ad-hoc
  signature and normally opens fine because it strips quarantine. If you copy
  that app some other way, right-click it and choose Open the first time.
- **Gatekeeper blocks a GitHub release** — releases are warning-free only
  when the repository's Developer ID and notarization secrets are configured.
  Without them, the first launch requires right-click → Open.

## Uninstall

Quit CursorQuota, then:

```sh
rm -rf /Applications/CursorQuota.app
```

Config in `~/.config/cursor-quota/` is left in place unless you remove it
yourself.
