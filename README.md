# claude-vitals

> **A single-line, always-on health bar for your Claude Code session — context, branch, tokens, duration, and rate limits.**

```
Opus xhigh ✦  │  ⎇ main ~1  │  142.3k↑ 95.2k↓  │  ▓▓▓▓▓▓░░░░ 60%  │  51m12s  │  5h ▓▓▓▓░ 88% (4h17m)  │  7d ▓▓░░░ 23% (2d 14h)
```

> The block above is a plain-text mockup; in the terminal the bars are **coloured** by threshold (sage → amber → red) and the dividers are dim warm-gray. This README sample uses `▓░` instead of `█░` because heavy block characters look unbalanced without colour.

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

The installer:

- drops `claude-vitals.sh` into `~/.claude/claude-vitals/`,
- adds a `statusLine` block to `~/.claude/settings.json` (existing keys are preserved; any prior `statusLine` is backed up next to the file), and
- sets `refreshInterval: 5` so time-based segments tick while you're idle.

Then restart Claude Code (or open a new session). Accept the workspace trust prompt the first time.

> **Windows**: run the same one-liner from **Git Bash** — that's the shell Claude Code itself uses to invoke statusLine commands on Windows.

### Manual install

1. Make sure `jq` is on your PATH (`brew install jq` / `sudo apt install jq`).
2. Copy `claude-vitals.sh` to `~/.claude/claude-vitals/claude-vitals.sh` and `chmod +x` it.
3. Add this to `~/.claude/settings.json` (replace `/home/you` with your actual home; the auto-installer writes the absolute path):
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "/home/you/.claude/claude-vitals/claude-vitals.sh",
       "padding": 1,
       "refreshInterval": 5
     }
   }
   ```

Drop `refreshInterval` if you only want updates after assistant messages.

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
- **`bash 4+ required` (macOS)** — Apple still ships bash 3.2; run `brew install bash` and re-run the installer.
- **No `5h` / `7d` bars** — those fields are only present for Pro/Max subscribers, after the first API response.
- **Want different thresholds / colours** — edit `claude-vitals.sh`; the colour and threshold logic is in `color_for_pct()` near the top.

## Supported platforms

- **Linux**, **macOS**, and **Windows via Git Bash** — the same shell Claude Code itself uses to run statusLine commands. Requires bash 4+ (so on macOS, install with `brew install bash` since the system ships bash 3.2).
- Best in a terminal that supports 24-bit truecolor (modern Windows Terminal, iTerm2, kitty, GNOME Terminal, VS Code's integrated terminal). Without truecolor, set `CLAUDE_VITALS_NO_COLOR=1`.
- tmux sessions work fine.

## License

MIT — see [LICENSE](./LICENSE).

## Credits

- [`claude-pulse`](https://github.com/samirpatil2000/claude-pulse) by Samir Patil — the browser-extension inspiration.
- Anthropic's Claude Code statusLine docs for the rich JSON contract that makes this possible.
