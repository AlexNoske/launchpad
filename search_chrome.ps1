# Opens (or reuses) a Google Chrome window with a Google search for -Query, then moves that
# window to a fixed secondary monitor and maximizes it there. Deliberately does NOT touch the
# 2x2 grid or open_sessions.json -- this is a one-off browser tab, not a tracked terminal session.
#
# Monitor targeting: uses [System.Windows.Forms.Screen]::AllScreens[$MonitorIndex] -- a fixed
# index into the OS's monitor list, not "whichever screen isn't primary". On this machine that
# was observed to be:
#   [0] Primary=True  Bounds=1920x1080 @ (0,0)        (DISPLAY1 -- the grid monitor)
#   [1] Primary=False Bounds=1920x1080 @ (1920,0)     (DISPLAY2 -- to the right; default target)
#   [2] Primary=False Bounds=1920x1080 @ (-1920,0)    (DISPLAY3 -- to the left)
# If monitors are added/removed/reordered by Windows, re-check indices with:
#   Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Screen]::AllScreens
# and pass -MonitorIndex to override.

param(
    [Parameter(Mandatory = $true)][string]$Query,
    [Parameter(Mandatory = $false)][int]$MonitorIndex = 1
)

function Resolve-ChromePath {
    $regPaths = @(
        'HKLM:\SOFTWARE\Clients\StartMenuInternet\Google Chrome\shell\open\command',
        'HKCU:\SOFTWARE\Clients\StartMenuInternet\Google Chrome\shell\open\command',
        'HKLM:\SOFTWARE\WOW6432Node\Clients\StartMenuInternet\Google Chrome\shell\open\command'
    )
    foreach ($rp in $regPaths) {
        try {
            $val = (Get-ItemProperty -Path $rp -ErrorAction Stop).'(default)'
            if ($val) {
                $exe = $val.Trim('"')
                if (Test-Path $exe) { return $exe }
            }
        } catch {}
    }
    $fallbacks = @(
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )
    foreach ($fp in $fallbacks) {
        if (Test-Path $fp) { return $fp }
    }
    return $null
}

$chromePath = Resolve-ChromePath
if (-not $chromePath) {
    Write-Host "Error: could not locate chrome.exe (checked registry App Paths and common install locations)."
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
$screens = [System.Windows.Forms.Screen]::AllScreens
if ($MonitorIndex -lt 0 -or $MonitorIndex -ge $screens.Count) {
    Write-Host "Error: -MonitorIndex $MonitorIndex is out of range (0..$($screens.Count - 1) available)."
    exit 1
}
$targetBounds = $screens[$MonitorIndex].Bounds

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32Search {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
}
"@

$SW_RESTORE  = 9
$SW_MAXIMIZE = 3

$searchUrl = 'https://www.google.com/search?q=' + [uri]::EscapeDataString($Query)

# Launching chrome.exe with a bare URL (no --new-window) reuses an already-running Chrome
# instance -- it opens a new tab there via IPC and the launched process exits almost immediately
# -- or starts a fresh window/process if Chrome wasn't running. Either way we can't trust
# Start-Process's own returned PID to be the browser window, so we poll for the foreground window
# afterward instead.
Start-Process -FilePath $chromePath -ArgumentList @($searchUrl) | Out-Null

$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 200
    $fg = [Win32Search]::GetForegroundWindow()
    if ($fg -ne [IntPtr]::Zero -and [Win32Search]::IsWindowVisible($fg)) {
        $procId = 0
        [Win32Search]::GetWindowThreadProcessId($fg, [ref]$procId) | Out-Null
        if ($procId -gt 0) {
            $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq 'chrome') {
                $hwnd = $fg
                break
            }
        }
    }
}

if ($hwnd -eq [IntPtr]::Zero) {
    Write-Host "Warning: opened the search but couldn't identify Chrome's window to reposition it (it may still be on whatever monitor it last used)."
    exit 0
}

# Restore first: MoveWindow on an already-maximized window won't relocate it, and maximizing
# affects whichever monitor the window is currently considered to be on -- so move while
# restored, then maximize.
[Win32Search]::ShowWindow($hwnd, $SW_RESTORE) | Out-Null
[Win32Search]::MoveWindow($hwnd, $targetBounds.X + 50, $targetBounds.Y + 50, 800, 600, $true) | Out-Null
[Win32Search]::ShowWindow($hwnd, $SW_MAXIMIZE) | Out-Null
[Win32Search]::SetForegroundWindow($hwnd) | Out-Null

Write-Host "Searched Google for '$Query' in Chrome, maximized on monitor [$MonitorIndex] ($($targetBounds.Width)x$($targetBounds.Height) @ $($targetBounds.X),$($targetBounds.Y))."
