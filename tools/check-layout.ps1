param(
    [ValidateSet(0, 1)]
    [int]$Debug = 1,

    [string]$OutPrefix = "target\eth-layout"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path "target")) {
    New-Item -ItemType Directory -Path "target" | Out-Null
}

$asmOutput = & .\64tass.exe -D "DEBUG=$Debug" .\src\eth.asm --nostart -L "$OutPrefix.lst" -o "$OutPrefix.bin" 2>&1
$asmExit = $LASTEXITCODE
$asmOutput | ForEach-Object { Write-Output $_ }

if ($asmExit -ne 0) {
    exit $asmExit
}

function Fail-Layout($message) {
    Write-Error $message
    exit 1
}

$ranges = @()
foreach ($line in $asmOutput) {
    if ($line -match 'Data:\s+\d+\s+\$([0-9a-fA-F]{4})-\$([0-9a-fA-F]{4})') {
        $ranges += [pscustomobject]@{
            Start = [Convert]::ToInt32($matches[1], 16)
            End = [Convert]::ToInt32($matches[2], 16)
        }
    }
}

$api = $ranges | Where-Object { $_.Start -eq 0x2000 } | Select-Object -First 1
if (-not $api) { Fail-Layout "Missing API jump-table range at `$2000." }
if ($api.End -ge 0x2100) { Fail-Layout ("API jump table reaches `${0:x4}; it overlaps the state block at `$2100." -f $api.End) }

$runtime = $ranges | Where-Object { $_.Start -eq 0x2100 } | Select-Object -First 1
if (-not $runtime) { Fail-Layout "Missing state/buffer/runtime range at `$2100." }
if ($runtime.End -ge 0x7000) { Fail-Layout ("Runtime block reaches `${0:x4}; it overlaps the ML helper table at `$7000." -f $runtime.End) }

foreach ($requiredStart in 0x7000, 0x71c0, 0x7200) {
    if (-not ($ranges | Where-Object { $_.Start -eq $requiredStart } | Select-Object -First 1)) {
        Fail-Layout ("Missing public helper range at `${0:x4}." -f $requiredStart)
    }
}

$fixedOrgPattern = '^\s*\*\s*=\s*\$(4b0b|682c|6a00)\s*$'
foreach ($file in Get-ChildItem -Path "src" -Filter "*.asm") {
    $hits = Select-String -Path $file.FullName -Pattern $fixedOrgPattern
    if ($hits) {
        Fail-Layout ("Unsafe internal fixed org remains in {0}: {1}" -f $file.Name, $hits[0].Line.Trim())
    }
}

$ringStorage = Select-String -Path "src\*.asm" -Pattern '^\s*RING_BUFFER:\s*$'
if ($ringStorage) {
    Fail-Layout ("RX ring payload must stay in bank 5, not assembled into bank 4 ({0}: {1})." -f $ringStorage[0].Path, $ringStorage[0].LineNumber)
}

Write-Output ("Layout OK (DEBUG={0}): API `$2000-`${1:x4}, state/buffers/runtime `$2100-`${2:x4}, helper tables preserved." -f $Debug, $api.End, $runtime.End)
