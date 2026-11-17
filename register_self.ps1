# Pins THIS session's own terminal window to the top-left grid slot and reserves
# slot "TL" for it in open_sessions.json (under the special session id "0"), so
# claude_goto.bat's next launch starts at TR instead of re-using this window's slot.

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$SessionsFile = Join-Path $ScriptDir 'open_sessions.json'

function Get-AncestorClaudePid {
    $walkPid = $PID
    for ($i = 0; $i -lt 10; $i++) {
        $procObj = Get-Process -Id $walkPid -ErrorAction SilentlyContinue
        if ($procObj -and $procObj.ProcessName -eq 'claude') { return $walkPid }
        $wmiProc = Get-CimInstance Win32_Process -Filter "ProcessId=$walkPid" -ErrorAction SilentlyContinue
        if (-not $wmiProc -or -not $wmiProc.ParentProcessId) { return $null }
        $walkPid = $wmiProc.ParentProcessId
    }
    return $null
}

$selfPid = Get-AncestorClaudePid
if (-not $selfPid) {
    Write-Host "Warning: could not locate an ancestor 'claude' process; skipping self-registration and window move."
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$halfW  = [int]($bounds.Width / 2)
$halfH  = [int]($bounds.Height / 2)

# Running from a SessionStart hook, this process's console attachment isn't guaranteed to be
# the visible terminal window -- so pass -TargetPid: set_window_pos.ps1 explicitly attaches to
# that pid's console via AttachConsole before calling GetConsoleWindow(), then measures and
# compensates for the invisible DWM border.
$PosScript = Join-Path $ScriptDir 'set_window_pos.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $PosScript $bounds.Left $bounds.Top $halfW $halfH -TargetPid $selfPid

# Unlike goto_folder.ps1's freshly-launched sessions, this single upfront placement is enough here
# in practice -- this hook runs very early (before claude's TUI does its UTF-8 codepage/font swap),
# so a follow-up poll loop isn't needed and was only adding repeated, visible resize/font churn to
# this terminal on every session start/resume. Do not re-add a repeated corrector here without
# confirming the font-swap race actually reappears for the self-registration path.

$sessionsHash = @{}
$nextId = 1
if (Test-Path $SessionsFile) {
    $registry = Get-Content -Raw $SessionsFile | ConvertFrom-Json
    if ($registry.next_id) { $nextId = $registry.next_id }
    if ($registry.sessions) {
        foreach ($p in $registry.sessions.PSObject.Properties) {
            if ($p.Name -eq '0') { continue }
            $proc = Get-Process -Id $p.Value.pid -ErrorAction SilentlyContinue
            if ($proc) { $sessionsHash[$p.Name] = $p.Value }
        }
    }
}

$sessionsHash['0'] = [PSCustomObject]@{
    folder_index = $null
    name         = 'test_claude (repository manager)'
    path         = $ScriptDir
    pid          = $selfPid
    launcher     = 'self'
    app          = 'self'
    slot         = 'TL'
    started      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
}

$outRegistry = @{ next_id = $nextId; sessions = $sessionsHash }
$outRegistry | ConvertTo-Json -Depth 6 | Set-Content -Path $SessionsFile -Encoding UTF8

Write-Host "Registered session 0 (this repository-manager terminal) -> slot TL, pid=$selfPid"
