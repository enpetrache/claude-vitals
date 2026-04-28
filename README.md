# claude-vitals

> **A single-line, always-on health bar for your Claude Code session — context, branch, tokens, duration, and rate limits.**

```
Opus xhigh ✦  │  ⎇ main ~1  │  42.5k↑ 79.8k↓  │  █░░░░░░░░░ 17%  │  51m12s  │  5h ████░ 90%  │  7d ██░░░ 56%
```

Warm Claude-themed palette (truecolor), terminal-native glyphs, dim `│` dividers between segments. Best in a terminal with truecolor support and a font that includes `⎇` and `✦` (most modern terminals do).

## What it shows

- **Model · effort · thinking** indicator (`✦` when extended thinking is on).
- **Git branch** with `+staged ~modified` counts.
- **Cumulative session tokens** in / out, in human format (`1.2M`, `12.3k`).
- **Context window bar** with percent — coloured by threshold (sage / amber / red).
- **Wall-clock duration** since session start.
- **5-hour and 7-day rate-limit bars** with time until reset in dim parens (Pro/Max subscribers), e.g. `5h ████░ 90% (4h17m)`.

Single bash script, single dependency (`jq`). Runs only in your terminal — no network, no telemetry.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/enpetrache/claude-vitals/main/install.sh | bash
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

`refreshInterval: 5` keeps the duration ticking while you are idle. Drop it if you only want updates after assistant messages.

## Customise

Set environment variables before launching `claude`:

| Variable                    | Effect                                            |
|-----------------------------|---------------------------------------------------|
| `CLAUDE_VITALS_NO_GIT=1`    | Hide the git branch / staged / modified segment. |
| `CLAUDE_VITALS_NO_RATE=1`   | Hide the 5-hour / 7-day rate-limit bars.         |
| `CLAUDE_VITALS_NO_COLOR=1`  | Disable ANSI colours (also honours `NO_COLOR`).  |

## How it works

Claude Code's [statusLine](https://code.claude.com/docs/en/statusline) feature pipes a JSON blob to your script after every assistant message and (with `refreshInterval`) on a timer. `claude-vitals.sh` parses that JSON and prints one line, padded above and below with a blank row so it breathes against the surrounding Claude Code UI.

| Segment             | Source field                                                                     |
|---------------------|----------------------------------------------------------------------------------|
| Model · effort · ✦  | `model.display_name`, `effort.level`, `thinking.enabled`                         |
| `⎇` branch + counts | `git branch --show-current` and `git diff --numstat` in `workspace.current_dir`  |
| `↑↓` tokens         | `context_window.total_input_tokens`, `total_output_tokens`                       |
| Context bar / `%`   | `context_window.used_percentage`                                                 |
| Duration            | `cost.total_duration_ms`                                                         |
| `5h` / `7d` bars    | `rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage` |
| `(4h17m)` reset     | `rate_limits.five_hour.resets_at`, `rate_limits.seven_day.resets_at` (Unix epoch) |

Git status is cached in `/tmp/claude-vitals-git-<session_id>` for ~5 seconds so large repos stay responsive.

## Troubleshooting

- **The bar is blank** — run `claude --debug` and look for the statusLine command's exit code and stderr. Usually it is the workspace trust prompt; restart Claude Code and accept it.
- **`jq: command not found`** — install jq.
- **No `5h` / `7d` bars** — those fields are only present for Pro/Max subscribers, after the first API response.
- **Want different thresholds / colours** — edit `claude-vitals.sh`; the colour and threshold logic is in `color_for_pct()` near the top.

## Tested with

- Claude Code 2.1.x on Linux and macOS (`bash` 4+ and `bash` 5).
- Both single-window and tmux sessions.

## License

MIT — see [LICENSE](./LICENSE).

## Credits

- [`claude-pulse`](https://github.com/samirpatil2000/claude-pulse) by Samir Patil — the browser-extension inspiration.
- Anthropic's Claude Code statusLine docs for the rich JSON contract that makes this possible.
