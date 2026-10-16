param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference = 'Stop'
$report = Join-Path $env:TEMP ('ViGEmBus-startup-' + [guid]::NewGuid().ToString('N') + '.txt')
$process = Start-Process -FilePath $Path -ArgumentList @('/CURRENTUSER', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/COMPATIBILITYCHECK=1', "/COMPATIBILITYREPORT=`"$report`"") -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(30000)) {
    $process.Kill()
    throw 'Installer startup check timed out.'
}
if (-not (Test-Path -LiteralPath $report)) {
    throw "Installer did not pass Windows compatibility startup check (exit $($process.ExitCode))."
}
try {
    $result = Get-Content -LiteralPath $report -Raw
    if ($result -notmatch '^PASS:') { throw $result }
    Write-Host $result
} finally {
    Remove-Item -LiteralPath $report -Force
}
