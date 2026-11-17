param(
    [Parameter(Mandatory = $false)]
    [string]$SessionId
)

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$SessionsFile = Join-Path (Join-Path (Split-Path -Parent $ScriptDir) 'state') 'open_sessions.json'

if (-not (Test-Path $SessionsFile)) {
    Write-Host "No sessions registry found at $SessionsFile (nothing has been launched yet)."
    exit 0
}

$registry = Get-Content -Raw $SessionsFile | ConvertFrom-Json

$alive = @{}
foreach ($p in $registry.sessions.PSObject.Properties) {
    $entry = $p.Value
    $proc = Get-Process -Id $entry.pid -ErrorAction SilentlyContinue
    if ($proc) {
        $alive[$p.Name] = $entry
    }
}

function Save-Registry([hashtable]$aliveMap) {
    $nextId = if ($registry.next_id) { $registry.next_id } else { 1 }
    $outRegistry = @{ next_id = $nextId; sessions = $aliveMap }
    $outRegistry | ConvertTo-Json -Depth 6 | Set-Content -Path $SessionsFile -Encoding UTF8
}

if ([string]::IsNullOrWhiteSpace($SessionId)) {
    if ($alive.Count -eq 0) {
        Write-Host "No open sessions."
    } else {
        Write-Host "Open sessions:"
        foreach ($key in ($alive.Keys | Sort-Object { [int]$_ })) {
            $e = $alive[$key]
            Write-Host ("  [{0}] slot {1}, app {2}, folder {3} ({4}) -> {5}, pid={6}, started {7}" -f $key, $e.slot, $e.app, $e.folder_index, $e.name, $e.path, $e.pid, $e.started)
        }
    }
    Save-Registry $alive
    exit 0
}

if ($SessionId -eq '0') {
    Write-Host "Error: session 0 is this repository-manager terminal itself and can't be closed via claude_close.bat."
    Save-Registry $alive
    exit 1
}

if (-not $alive.ContainsKey($SessionId)) {
    Write-Host "Error: session '$SessionId' is not open (already closed, or never existed)."
    Save-Registry $alive
    exit 1
}

$target = $alive[$SessionId]
taskkill /PID $target.pid /T /F | Out-Null

Write-Host "Closed session $SessionId (folder $($target.folder_index): $($target.name), pid=$($target.pid))"

$alive.Remove($SessionId)
Save-Registry $alive
