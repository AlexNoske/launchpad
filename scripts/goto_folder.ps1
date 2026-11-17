param(
    [Parameter(Mandatory = $false)]
    [string]$Index,
    [Parameter(Mandatory = $false)]
    [ValidateSet('claude', 'terminal')]
    [string]$App = 'claude'
)

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateDir     = Join-Path (Split-Path -Parent $ScriptDir) 'state'
$IndexFile    = Join-Path $StateDir 'folder_index.json'
$SessionsFile = Join-Path $StateDir 'open_sessions.json'
$PosScript    = Join-Path $ScriptDir 'set_window_pos.ps1'

# Walks this process's own parent chain. Used to identify which tracked session (if any) this
# script is being run FROM, so the launching terminal's own window can be re-corrected below --
# creating a new tiled window can knock the launching terminal's size/font off, and unlike that
# new window's own font-swap correction, this isn't tied to a known async cause, so it's just
# reasserted immediately rather than after a delay.
function Get-AncestorPidChain {
    $chain = @()
    $walkPid = $PID
    for ($i = 0; $i -lt 20; $i++) {
        $chain += $walkPid
        $wmiProc = Get-CimInstance Win32_Process -Filter "ProcessId=$walkPid" -ErrorAction SilentlyContinue
        if (-not $wmiProc -or -not $wmiProc.ParentProcessId) { break }
        $walkPid = $wmiProc.ParentProcessId
    }
    return $chain
}

if (-not (Test-Path $IndexFile)) {
    Write-Host "Error: index file not found at $IndexFile"
    exit 1
}

$folders = Get-Content -Raw $IndexFile | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($Index)) {
    Write-Host "Usage: (claude_goto.bat|terminal_goto.bat) <folder-index>"
    Write-Host ""
    Write-Host "Available folders:"
    foreach ($prop in $folders.PSObject.Properties) {
        Write-Host ("  [{0}] {1} -> {2}" -f $prop.Name, $prop.Value.name, $prop.Value.path)
    }
    exit 1
}

$entry = $folders.$Index
if (-not $entry) {
    Write-Host "Error: no entry found for index '$Index' in $IndexFile"
    exit 1
}

$target = $entry.path
if (-not (Test-Path $target)) {
    Write-Host "Error: target folder does not exist: $target"
    exit 1
}

# --- load registry, self-healing prune of dead sessions (frees their grid slots too) ---
$nextId = 1
$sessionsHash = @{}
if (Test-Path $SessionsFile) {
    $registry = Get-Content -Raw $SessionsFile | ConvertFrom-Json
    if ($registry.next_id) { $nextId = $registry.next_id }
    if ($registry.sessions) {
        foreach ($p in $registry.sessions.PSObject.Properties) {
            $proc = Get-Process -Id $p.Value.pid -ErrorAction SilentlyContinue
            if ($proc) { $sessionsHash[$p.Name] = $p.Value }
        }
    }
}

# --- 2x2 grid on the primary monitor ---
Add-Type -AssemblyName System.Windows.Forms
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$halfW = [int]($bounds.Width / 2)
$halfH = [int]($bounds.Height / 2)

# Slots are the intended VISIBLE bounds of each quadrant. set_window_pos.ps1 measures this
# actual invisible-border margin per side (via DwmGetWindowAttribute) and compensates, so no
# manual pixel-fudge constant is needed here.
$slots = [ordered]@{
    'TL' = @{ X = $bounds.Left;          Y = $bounds.Top;          W = $halfW;                 H = $halfH }
    'TR' = @{ X = $bounds.Left + $halfW; Y = $bounds.Top;          W = $bounds.Width - $halfW; H = $halfH }
    'BL' = @{ X = $bounds.Left;          Y = $bounds.Top + $halfH; W = $halfW;                 H = $bounds.Height - $halfH }
    'BR' = @{ X = $bounds.Left + $halfW; Y = $bounds.Top + $halfH; W = $bounds.Width - $halfW; H = $bounds.Height - $halfH }
}

$occupied = @{}
foreach ($s in $sessionsHash.Values) {
    if ($s.slot) { $occupied[$s.slot] = $s }
}

$freeSlot = $null
foreach ($slotName in $slots.Keys) {
    if (-not $occupied.ContainsKey($slotName)) { $freeSlot = $slotName; break }
}

if (-not $freeSlot) {
    Write-Host "Error: all 4 grid slots are occupied. Close one first:"
    foreach ($key in ($sessionsHash.Keys | Sort-Object { [int]$_ })) {
        $e = $sessionsHash[$key]
        Write-Host ("  session {0}: slot {1}, app {2}, folder {3} ({4}), pid={5}" -f $key, $e.slot, $e.app, $e.folder_index, $e.name, $e.pid)
    }
    exit 1
}

$rect = $slots[$freeSlot]
$sessionId = $nextId
$haveWt = Get-Command wt -ErrorAction SilentlyContinue

if ($haveWt) {
    if ($App -eq 'claude') {
        $proc = Start-Process -FilePath 'wt' -ArgumentList @('-d', $target, 'claude', '/init') -PassThru
    } else {
        $proc = Start-Process -FilePath 'wt' -ArgumentList @('-d', $target) -PassThru
    }
    $launcher = 'wt'
    Write-Host "Note: launched via 'wt' -- grid tiling is only applied for the 'cmd' fallback launcher, this window was not repositioned."
} else {
    if ($App -eq 'claude') {
        $innerCmd = 'cd /d "{0}" && claude "/init"' -f $target
    } else {
        $innerCmd = 'cd /d "{0}"' -f $target
    }
    $cmdLine = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" {1} {2} {3} {4} & {5}' -f $PosScript, $rect.X, $rect.Y, $rect.W, $rect.H, $innerCmd
    $proc = Start-Process -FilePath 'cmd' -ArgumentList @('/k', $cmdLine) -PassThru
    $launcher = 'cmd'
}

if ($launcher -eq 'cmd') {
    # Re-assert the LAUNCHING terminal's own slot position/format, in case creating the new
    # window just knocked it out of place. This runs inside the launching terminal's own console
    # by ordinary inheritance (same as the new window's rough placement above), so no -TargetPid
    # is needed here -- GetConsoleWindow() already resolves to the right window.
    $ancestorChain = Get-AncestorPidChain
    $callerEntry = $null
    foreach ($v in $sessionsHash.Values) {
        if ($ancestorChain -contains [int]$v.pid) { $callerEntry = $v; break }
    }
    if ($callerEntry -and $slots.Contains($callerEntry.slot)) {
        $selfRect = $slots[$callerEntry.slot]
        & powershell -NoProfile -ExecutionPolicy Bypass -File $PosScript $selfRect.X $selfRect.Y $selfRect.W $selfRect.H | Out-Null
    }
}

if ($launcher -eq 'cmd' -and $App -eq 'claude') {
    # claude's TUI switches the console codepage to UTF-8 shortly after startup (needed for its
    # Unicode box-drawing/spinner glyphs), which forces a legacy-conhost font swap (raster ->
    # TrueType). That swap changes cell metrics, so conhost nudges the window's pixel size to keep
    # the same row/col count -- undoing the placement above (visible as a slight height shrink and
    # a different font). We can't control exactly when that happens inside claude's startup, so a
    # single fixed-delay reassert is a bet that can miss it -- but a repeated poll was hammering the
    # new window's placement/font every 400ms for ~3.6s, which is more disruptive than it's worth.
    # One delayed correction, well past where the swap typically lands, is the tradeoff here.
    $correctorCmd = "Start-Sleep -Milliseconds 2000; & '$PosScript' $($rect.X) $($rect.Y) $($rect.W) $($rect.H) -TargetPid $($proc.Id)"
    Start-Process -FilePath 'powershell' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $correctorCmd
    ) | Out-Null
}

$sessionEntry = [PSCustomObject]@{
    folder_index = $Index
    name         = $entry.name
    path         = $target
    pid          = $proc.Id
    launcher     = $launcher
    app          = $App
    slot         = $freeSlot
    started      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
}

$sessionsHash["$sessionId"] = $sessionEntry

$outRegistry = @{ next_id = $sessionId + 1; sessions = $sessionsHash }
$outRegistry | ConvertTo-Json -Depth 6 | Set-Content -Path $SessionsFile -Encoding UTF8

Write-Host "Launched session $sessionId ($App) -> [$Index] $($entry.name) ($target), slot=$freeSlot, pid=$($proc.Id)"
