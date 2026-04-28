# claude-vitals

> **Always-on token, cost, cache, and rate-limit metrics inside Claude Code.**
> Inspired by [`claude-pulse`](https://github.com/samirpatil2000/claude-pulse) (browser extension for claude.ai), built for the terminal.

```
[Opus·high·🧠] · 📁 my-repo · 🌿 main +2 ~5 · 152.3k↑ 45.2k↓
███████░░░ 78% ctx · $1.24 · ⏱ 12m18s · ⚡cache 4:21 · 5h ▓▓▓░░ 41% · 7d ▓░░░░ 23%
```

## What it shows

- **Context window bar** — coloured by threshold (green / yellow / red).
- **Cumulative tokens** in / out for the session, in human format (`1.2M`, `12.3k`).
- **Session cost** in USD.
- **Wall-clock duration** since session start.
- **Cache TTL countdown** — how many seconds until the 5-minute prompt cache expires (the unique trick from claude-pulse, ported to the CLI).
- **5-hour and 7-day rate-limit usage** for Pro/Max subscribers, with mini-bars.
- **Model · effort · thinking** indicator, working directory, and git branch with `+staged ~modified` counts.

Single bash script, single dependency (`jq`). Runs only in your terminal — no network, no telemetry.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/REPLACE_ME/claude-vitals/main/install.sh | bash
```

Then restart Claude Code (or open a new session). Accept the workspace trust prompt the first time.

### Manual install

1. Make sure `jq` is on your PATH (`brew install jq` / `sudo apt install jq`).
2. Copy `claude-vitals.sh` to `~/.claude/claude-vitals/claude-vitals.sh` and `chmod +x` it.
3. Add this to `~/.claude/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/claude-vitals/claude-vitals.sh",
       "padding": 1,
       "refreshInterval": 5
     }
   }
   ```

`refreshInterval: 5` keeps the cache countdown ticking while you are idle. Drop it if you only want updates after assistant messages.

## Customise

Set environment variables before launching `claude`:

| Variable               | Effect                                               |
|------------------------|------------------------------------------------------|
| `CLAUDE_VITALS_NO_GIT=1`  | Hide the git branch / staged / modified segment.     |
| `CLAUDE_VITALS_NO_RATE=1` | Hide the 5-hour / 7-day rate-limit bars.             |
| `CLAUDE_VITALS_NO_CACHE=1`| Hide the prompt-cache TTL countdown.                 |
| `CLAUDE_VITALS_NO_COLOR=1` | Disable ANSI colours (also honours `NO_COLOR`).     |

## How it works

Claude Code's [statusLine](https://code.claude.com/docs/en/statusline) feature pipes a JSON blob to your script after every assistant message and (with `refreshInterval`) on a timer. `claude-vitals.sh` parses that JSON and prints two lines.

| Segment                | Source field                                                                |
|------------------------|-----------------------------------------------------------------------------|
| Model / effort / 🧠    | `model.display_name`, `effort.level`, `thinking.enabled`                    |
| `📁` directory          | `workspace.current_dir`                                                     |
| `🌿` branch             | `git branch --show-current` in `workspace.current_dir`                      |
| `↑↓` tokens             | `context_window.total_input_tokens`, `total_output_tokens`                  |
| Context bar / `% ctx`  | `context_window.used_percentage`                                            |
| `$cost`                | `cost.total_cost_usd`                                                       |
| `⏱`                    | `cost.total_duration_ms`                                                    |
| `⚡cache M:SS`          | inferred from changes in `cost.total_api_duration_ms` (5-min TTL)           |
| `5h`/`7d` bars         | `rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage` |

The cache countdown deserves a note: Claude Code does not expose a "last API request" timestamp directly, but `cost.total_api_duration_ms` strictly increases each time the model is hit. `claude-vitals` records the value plus the wall-clock time in `/tmp/claude-vitals-<session_id>.state`; whenever the value changes, the timer resets. Idle ticks (every `refreshInterval` seconds) read the same state and decrement the displayed countdown.

Git status is cached in `/tmp/claude-vitals-git-<session_id>` for ~5 seconds so large repos stay responsive.

## Troubleshooting

- **The bar is blank** — run `claude --debug` and look for the statusLine command's exit code and stderr. Usually it is the workspace trust prompt; restart Claude Code and accept it.
- **`jq: command not found`** — install jq.
- **`⚡cache` never appears** — the segment only shows once Claude Code has made at least one API call in the session.
- **No `5h` / `7d` bars** — those fields are only present for Pro/Max subscribers, after the first API response.
- **Want different thresholds / colours** — edit `claude-vitals.sh`; the colour and threshold logic is in `color_for_pct()` and the cache section near the top.

## Tested with

- Claude Code 2.1.x on Linux and macOS (`bash` 4+ and `bash` 5).
- Both single-window and tmux sessions.

## License

MIT — see [LICENSE](./LICENSE).

## Credits

- [`claude-pulse`](https://github.com/samirpatil2000/claude-pulse) by Samir Patil — the browser-extension inspiration.
- Anthropic's Claude Code statusLine docs for the rich JSON contract that makes this possible.
