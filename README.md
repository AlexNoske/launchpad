# launchpad

A small Windows toolkit for jumping between project folders. Register your folders once, then open any of them by number, either as a new [Claude Code](https://claude.com/claude-code) session or as a plain terminal. Each new window is tiled automatically into a 2x2 grid on your primary monitor.

There's no source code to build here. It's just batch files and PowerShell scripts.

## Requirements

- Windows 10/11 with Windows PowerShell 5.1
- [Claude Code](https://claude.com/claude-code) on your `PATH` (for `claude_goto.bat` and `open_here.bat`)
- Google Chrome (only for `search_google.bat`)

## Setup

1. Clone or copy this folder anywhere. All the scripts locate each other relative to their own location, so the folder name and location don't matter.
2. Create the registry from the template:
   ```bat
   mkdir state
   copy folder_index.example.json state\folder_index.json
   ```
3. Edit `state\folder_index.json` to list your folders. Keys are integers, and backslashes in paths must be doubled:
   ```json
   {
     "1": { "name": "my-app",  "path": "C:\\Users\\you\\projects\\my-app" },
     "2": { "name": "scratch", "path": "C:\\Users\\you\\Desktop\\scratch" }
   }
   ```
4. Optional: create a desktop shortcut to `open_here.bat` so you can open launchpad with a double-click.

## Usage

| Command | What it does |
|---|---|
| `claude_goto.bat <n>` | Opens a new window at folder `n` running `claude "/init"` |
| `terminal_goto.bat <n>` | Opens a new window at folder `n` with a plain shell (no Claude) |
| `claude_goto.bat` (no argument) | Lists all registered folders |
| `claude_close.bat` | Lists open sessions and removes any whose windows are already closed |
| `claude_close.bat <id>` | Closes that session's window and its whole process tree |
| `search_google.bat <query>` | Opens a Google search in Chrome, maximized on a secondary monitor |
| `open_here.bat` | Starts Claude Code in this folder (what the desktop shortcut runs) |

Folder numbers (`<n>`) and session ids (`<id>`) are different numbers. Session ids count up with every launch, so you can have the same folder open more than once.

### Talking to Claude in this folder

If you start Claude Code in launchpad (via `open_here.bat`), you can just ask:

- "Open folder 2 in Claude Code" runs `claude_goto.bat 2`
- "Open folder 2 in terminal" runs `terminal_goto.bat 2`
- "What's open?" runs `claude_close.bat`
- "Close session 5" runs `claude_close.bat 5`
- "Navigate to folder 2" switches the *current* session to that folder without opening a window
- "Register C:\path\to\folder" adds the next free number to `folder_index.json`
- "Search for X" runs `search_google.bat X`

## Window grid

New windows fill the quadrants of the primary monitor in this order: top-left, top-right, bottom-left, bottom-right.

- The launchpad window itself is pinned to top-left as session `0`. A `SessionStart` hook in `.claude/settings.json` does this, so launched sessions start at top-right. `claude_close.bat` won't close session 0.
- Before each launch, the scripts check which quadrants are taken. A window you closed with the X button frees its quadrant automatically.
- If all four quadrants are full, the launch is refused. Close a session first.

## Layout

```
launchpad/
├── claude_goto.bat            # entry points
├── terminal_goto.bat
├── claude_close.bat
├── search_google.bat
├── open_here.bat
├── folder_index.example.json  # registry template
├── scripts/                   # internal PowerShell; don't run directly
│   ├── goto_folder.ps1        #   launch, tile, and record a session
│   ├── claude_close.ps1       #   list or close sessions
│   ├── register_self.ps1/.bat #   pin this window to the top-left quadrant (SessionStart hook)
│   ├── set_window_pos.ps1     #   move a window to an exact pixel position
│   └── search_chrome.ps1      #   Chrome search and monitor placement
└── state/                     # machine-specific, gitignored
    ├── folder_index.json      #   your folder registry
    └── open_sessions.json     #   live sessions (created on first launch)
```

## Limitations

- Windows only.
- If Windows Terminal (`wt`) is installed, the launcher uses it instead of `cmd`. In that case, process tracking and grid tiling become unreliable, so the `cmd` fallback is the tested path.
- `search_google.bat` targets the monitor at index `1` in `[System.Windows.Forms.Screen]::AllScreens`. Pass `-MonitorIndex` to `scripts\search_chrome.ps1` if your monitors are arranged differently. Searches open as a tab in an existing Chrome window when Chrome is running, and that whole window is moved.
- Shortcuts (`*.lnk`) store full paths. Recreate them if you move or rename this folder.
