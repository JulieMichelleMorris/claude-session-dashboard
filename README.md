# What Was I Working On

A session recovery board for people who run a lot of Claude Code sessions and lose track of them.

It builds a single HTML page on your desktop listing every real work session from the last 90 days, grouped by client, each with the first thing you asked, the last thing you said, and a click-to-copy command that drops you back into that exact session. After a crash, a closed terminal, or a week of chaos, you open one page and see exactly where you left off, everywhere.

## The problem it solves

The built-in resume picker shows only your most recent sessions, sorts by file-modified time, and mixes your real work in with scheduled automation. File times get re-stamped by tooling, so "recent" lies. And more than half the session files on disk turn out to be phantom fragments rather than real work. If you have ever known a session existed but could not find it, this board is for you.

## What it does

- Reads timestamps from inside each session transcript, never from file metadata
- Hides automation, sub-agent transcripts, and phantom queue fragments
- Folds duplicate retry fragments into one row
- Groups sessions into client and topic sections you define, with a tag bar of anchor links across the top
- Marks anything active in the last 48 hours with a green edge
- Gives every session a one-click resume command, copied to your clipboard
- Type-to-filter search across everything
- Rebuilds itself unattended: on a schedule, at logon, and every time a session ends

## Requirements

Windows with PowerShell 5.1 or later, and [Claude Code](https://claude.com/claude-code). No other dependencies. The output is one self-contained HTML file.

## Setup

1. Copy `working-on-board.ps1` somewhere permanent.
2. Open it and edit the `PERSONALIZE THESE BUCKETS` block: one bucket per client or project, with the names and words that identify each. The comments in that block explain the two-phase matching.
3. Run it once by hand to see your board:

    ```powershell
    powershell -NoProfile -ExecutionPolicy Bypass -File working-on-board.ps1 -Days 90
    ```

4. Schedule it (every 4 hours, plus at logon):

    ```powershell
    schtasks /create /tn "WorkingOnBoard" /tr "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\path\to\working-on-board.ps1 -Days 90 -NoOpen" /sc hourly /mo 4
    ```

    On a laptop, open Task Scheduler afterward and allow the task to run on battery; the Windows default silently skips it otherwise.

5. Optional but recommended: add a SessionEnd hook to your Claude Code `settings.json` so the board refreshes the moment any session ends:

    ```json
    {
      "hooks": {
        "SessionEnd": [{ "hooks": [{
          "type": "command",
          "command": "powershell",
          "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                   "C:\\path\\to\\working-on-board.ps1", "-Days", "90", "-NoOpen"],
          "async": true,
          "timeout": 300
        }]}]
      }
    }
    ```

6. Also recommended: set `"cleanupPeriodDays": 3650` in the same `settings.json`. The board can only show session files that still exist, and Claude Code deletes old transcripts by default.

## Reading the board

Sections sort by freshest activity, so whoever you touched last is on top. Within a section, newest first. The green left edge means active in the last 48 hours: those are open threads, not archaeology. Click a section title to fold it away; the fold sticks between visits.

## Full spec

`PRD.md` contains the complete product requirements, the acceptance tests, and the lessons that cost the most to learn, including why file times cannot be trusted, why the classifier reads assistant text and not just yours, and why half the session files on disk are phantoms. Read it if you are building your own version or adapting this to Mac or Linux.

## License

MIT. Built by [Julie Morris](https://github.com/) with Claude Code, and used every day on the machine it was built on.
