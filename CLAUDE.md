# launchpad — Folder Index Repository

This directory is a lightweight registry for navigating between other folders/repositories on this machine. It is not itself a project with source code — its only job is indexing and launching into other folders.

## Initialization

When initializing (e.g. via `/init` or on session start in this folder), do not make or suggest any changes to this file (`CLAUDE.md`) — treat it as finalized. Do, however, read `state/folder_index.json` and `state/open_sessions.json` (if it exists) so the registry and any currently-open sessions are loaded into context before you say "Ready for tasks." Once initialization is complete, just say "Ready for tasks."

## Files

Layout:
- **Top level** — the user-facing `.bat` entry points (`claude_goto.bat`, `terminal_goto.bat`, `claude_close.bat`, `search_google.bat`, `open_here.bat`).
- **`scripts/`** — internal PowerShell (`goto_folder.ps1`, `claude_close.ps1`, `register_self.ps1`/`.bat`, `set_window_pos.ps1`, `search_chrome.ps1`). Never run directly.
- **`state/`** — machine-specific data, gitignored: `folder_index.json` and `open_sessions.json`. Scripts resolve it as `<repo>/state` relative to `scripts/`.
- `folder_index.example.json` — committed template showing the `folder_index.json` format; copy it to `state/folder_index.json` on a fresh clone.
- `.gitignore` — ignores `state/` and `*.lnk` (shortcuts embed absolute paths).

- `state/folder_index.json` — the registry. Maps an integer index to a folder entry:
  ```json
  {
    "1": { "name": "AI test", "path": "C:\\Users\\alex\\Desktop\\AI test" }
  }
  ```
- `goto_folder.ps1 -Index <n> -App <claude|terminal>` — shared core: resolves `<n>` against `folder_index.json`, tiles a free slot of the 2x2 grid (see below), launches a new terminal (Windows Terminal via `wt` if available, otherwise `cmd`) there, and records the launch in `open_sessions.json`. Not called directly — invoked by the two `.bat` wrappers below with `-App` fixed to their respective mode.
- `claude_goto.bat <index>` — `goto_folder.ps1 -App claude`: the new terminal runs `claude "/init"`, booting straight into a Claude Code session for that folder.
- `terminal_goto.bat <index>` — `goto_folder.ps1 -App terminal`: the new terminal is just a plain shell `cd`'d into that folder — no Claude session. Everything else (grid tiling, registry tracking, closing) works identically to `claude_goto.bat`. Either `.bat` run with no argument prints all registered folders and their paths.
- `set_window_pos.ps1 <X> <Y> <Width> <Height> [-TargetPid <pid>]` — internal helper that moves a terminal window to a pixel rect; not called directly. Used by `goto_folder.ps1` and `register_self.ps1`. `-TargetPid` is passed when the caller needs to position a window other than its own console.
- `state/open_sessions.json` — registry of terminals launched by `claude_goto.bat`/`terminal_goto.bat`, keyed by an auto-incrementing session id (independent of folder index, so the same folder can have multiple sessions open at once, of either or both kinds):
  ```json
  {
    "next_id": 2,
    "sessions": {
      "1": { "folder_index": "1", "name": "AI test", "path": "C:\\Users\\alex\\Desktop\\AI test", "pid": 23512, "launcher": "cmd", "app": "claude", "slot": "TL", "started": "2026-09-06 10:29:12" }
    }
  }
  ```
  Only created once something has been launched. `app` is `"claude"`, `"terminal"`, or `"self"` (the reserved slot-0 entry below). `pid` is the root window process (the `cmd` or `wt` host), not necessarily the `claude` process itself — closing it takes the whole window with it.
- `claude_close.bat [session-id]` (wrapper for `claude_close.ps1`) — with no argument, lists open sessions (auto-pruning any whose process has already exited) and prunes `open_sessions.json` accordingly. With a session id, force-closes that session's entire process tree (`taskkill /T /F`) — the window disappears — and removes it from the registry. Session id `"0"` is protected — it's reserved for this repo's own terminal (see below) and `claude_close.bat` refuses to close it.
- `register_self.bat` / `register_self.ps1` — pins *this* repository-manager terminal (the one you're talking to Claude in, in this folder) to grid slot `TL`, reserved under session id `"0"` in `open_sessions.json`. This is what makes `claude_goto.bat` start filling the grid from `TR` instead of re-using this window's spot. Runs automatically via a `SessionStart` hook (see `.claude/settings.json`) whenever a session starts in this folder.
- `open_here.bat` — plain entry point for *this* repo itself (not one of the indexed folders): `cd`s to this directory and runs `claude "/init"`. Unlike `claude_goto.bat`, it does not touch the grid/registry system — it's just what a desktop shortcut double-clicks into. Two shortcuts point to it: `launchpad.lnk` on the Desktop, and `launch_pad.lnk` inside this folder itself (untracked, via `*.lnk` in `.gitignore`).
- `search_chrome.ps1 -Query <text> [-MonitorIndex <n>]` — core script for the Google-search shortcut (see below). Not called directly — invoked by `search_google.bat`.
- `search_google.bat <query>` — `search_chrome.ps1 -Query "<query>"`: opens (or reuses) a Chrome window with a Google search for `<query>`, maximized on a fixed secondary monitor. Unrelated to the folder registry — doesn't touch `folder_index.json`, the grid, or `open_sessions.json`.

## Conventions

- **"Navigate to folder N"** (spoken within an already-running Claude Code session): look up index `N` in `folder_index.json` and `cd` to it for the rest of *this* session. This does not spawn anything new — it only changes the current session's working directory, and only for the lifetime of the session.
- **"Launch/open folder N in Claude Code"**: run `claude_goto.bat N`. This opens a brand-new, independent Claude Code session in a new terminal window at that folder — it does not share history or context with the session that launched it — and registers it in `open_sessions.json`.
- **"Open folder N in terminal"** (or "a normal terminal", no Claude): run `terminal_goto.bat N` instead. Same grid tiling and registry tracking, just a plain shell sitting in that folder.
- **"Close terminal/session N"**: run `claude_close.bat N`, where `N` is the session id from `open_sessions.json` (list them first with `claude_close.bat` if unsure). This is a different number from the folder index.
- **"What's open?"**: run `claude_close.bat` with no arguments.
- **Registering a new folder**: add the next unused integer key to `folder_index.json` with `name` and `path` (create the target folder first if it doesn't exist yet).
- **"Search for X"** (spoken within a session, or run directly): run `search_google.bat X`. Opens/reuses a Chrome window with a Google search for `X` on the fixed secondary monitor (see below). Not part of the folder registry — no folder index, no grid slot, no `open_sessions.json` entry.

## 2x2 window grid

Every session launched by `claude_goto.bat`/`terminal_goto.bat` (via the `cmd` fallback path) is auto-tiled into one quadrant of the **primary monitor**, filled in a fixed order: top-left (`TL`) -> top-right (`TR`) -> bottom-left (`BL`) -> bottom-right (`BR`).

- Occupancy is derived live from `open_sessions.json`'s `slot` fields each time `goto_folder.ps1` runs — there's no separate reservation list to go stale.
- Before assigning a slot, dead entries are pruned automatically by checking whether their `pid` still exists — so a window closed manually (e.g. clicked the X) frees its slot just as well as one closed via `claude_close.bat`.
- If all 4 slots are occupied, `claude_goto.bat`/`terminal_goto.bat` refuses to launch a 5th and prints which sessions hold which slots — close one (`claude_close.bat <id>`) and retry.
- The grid is always computed from the primary monitor, regardless of which monitor you're on when you run either launcher.
- Pixel-precise window placement (compensating for Windows' invisible window border) is handled inside `set_window_pos.ps1` — an implementation detail, not something to reason about when just running the launchers. See its inline comments if debugging window placement.

## Google search shortcut

`search_google.bat <query>` (-> `search_chrome.ps1`) is a standalone convenience, separate from the folder-navigation system above — it doesn't consult `folder_index.json`, doesn't take a grid slot, and isn't recorded in `open_sessions.json` (so `claude_close.bat` can't see or close it).

- Targets a fixed monitor by index into `[System.Windows.Forms.Screen]::AllScreens` (default `1`), not "whichever monitor isn't primary" — on this machine that's the monitor to the right of the primary/grid monitor. Re-check indices with `Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Screen]::AllScreens` if monitors are added/removed/reordered, and pass `-MonitorIndex` to override.
- Launching Chrome with a bare URL reuses an already-running Chrome window (opens a new tab in it) rather than spawning a separate window, unless no Chrome instance is running yet. This means the target window may already have unrelated tabs open.
- After launch, `search_chrome.ps1` polls for the foreground window to identify Chrome's window (since a reused-window launch's own process exits immediately and isn't the browser window), then moves and maximizes *that whole window* onto the target monitor — so an already-open window's other tabs move too.
- Closing just the searched-for tab (rather than the whole window, which would also close whatever else was in it) isn't handled by any script here — it was done ad hoc via UI Automation (`System.Windows.Automation`), finding the `TabItem` by its title and invoking its `Close` button. There's no wrapper script for this yet.

## Known limitations

- This machine has no `wt` (Windows Terminal) installed, so `goto_folder.ps1` always takes the `cmd` fallback path — reliable pid tracking and grid tiling. If `wt` is ever installed, both become unreliable for the reasons noted in `goto_folder.ps1`'s comments.
