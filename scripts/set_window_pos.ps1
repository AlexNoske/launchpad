# Positions THIS console window so its VISIBLE frame lands at (X, Y, Width, Height).
#
# Windows draws an invisible resize border/drop-shadow around normal windows via DWM.
# MoveWindow/GetWindowRect operate on the OUTER window rect, which is padded outward by that
# invisible margin on some sides -- so aiming the outer rect at a target simply lands the
# VISIBLE frame a few pixels off, and the margin isn't necessarily equal on every side.
# Fix: place roughly, measure the real per-side margin by comparing GetWindowRect (outer) against
# DwmGetWindowAttribute's DWMWA_EXTENDED_FRAME_BOUNDS (the true visible bounds) on this actual
# window, then reposition precisely so the VISIBLE frame -- not the outer rect -- matches the request.
#
# -TargetPid: pass this when the calling process's own console attachment can't be trusted to be
# the visible terminal window -- e.g. register_self.ps1 invoked from a SessionStart hook, whose
# process tree doesn't share console inheritance the same way an ordinary spawned child does. In
# that case GetConsoleWindow() below could return zero or the wrong window. So instead we
# FreeConsole() (detach from whatever, if anything, this process currently has) then
# AttachConsole($TargetPid) to explicitly join the target's own console before calling
# GetConsoleWindow() -- $TargetPid must be a pid actually attached to that console (e.g. the
# ancestor `claude` process running in the terminal to move). Omit -TargetPid when this script is
# run as the literal first command inside a freshly-launched session's own command line (the
# goto_folder.ps1 path) -- there it already shares that console by ordinary inheritance.

param(
    [Parameter(Mandatory = $true)][int]$X,
    [Parameter(Mandatory = $true)][int]$Y,
    [Parameter(Mandatory = $true)][int]$Width,
    [Parameter(Mandatory = $true)][int]$Height,
    [Parameter(Mandatory = $false)][int]$TargetPid = 0
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class Win32 {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool FreeConsole();
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool AttachConsole(uint dwProcessId);
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
}
"@

$DWMWA_EXTENDED_FRAME_BOUNDS = 9

if ($TargetPid -gt 0) {
    [Win32]::FreeConsole() | Out-Null
    if (-not [Win32]::AttachConsole([uint32]$TargetPid)) {
        Write-Host "Warning: could not attach to console of pid $TargetPid; window will not be repositioned."
        exit 0
    }
}

$hwnd = [Win32]::GetConsoleWindow()
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Host "Warning: GetConsoleWindow() returned no window; skipping reposition."
    exit 0
}

# Rough placement so the window exists at approximately the right spot/size to measure from.
[Win32]::MoveWindow($hwnd, $X, $Y, $Width, $Height, $true) | Out-Null

$outer = New-Object RECT
$ext   = New-Object RECT
[Win32]::GetWindowRect($hwnd, [ref]$outer) | Out-Null
$hr = [Win32]::DwmGetWindowAttribute($hwnd, $DWMWA_EXTENDED_FRAME_BOUNDS, [ref]$ext, [Runtime.InteropServices.Marshal]::SizeOf([type]([RECT])))

if ($hr -eq 0) {
    $marginLeft   = $ext.Left    - $outer.Left
    $marginTop    = $ext.Top     - $outer.Top
    $marginRight  = $outer.Right  - $ext.Right
    $marginBottom = $outer.Bottom - $ext.Bottom

    $correctedX = $X - $marginLeft
    $correctedY = $Y - $marginTop
    $correctedW = $Width  + $marginLeft + $marginRight
    $correctedH = $Height + $marginTop  + $marginBottom

    [Win32]::MoveWindow($hwnd, $correctedX, $correctedY, $correctedW, $correctedH, $true) | Out-Null
}

if ($TargetPid -gt 0) {
    [Win32]::FreeConsole() | Out-Null
}
