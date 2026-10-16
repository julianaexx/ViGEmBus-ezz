param([string]$Version = '1.0.2', [string]$DriverVersion = '1.22.1.0')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$stage = Join-Path $root 'artifacts/setup-payload'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item "$root/bin/x64/ViGEmBus/ViGEmBus.sys" $stage
Copy-Item "$root/LICENSE" $stage
Copy-Item "$PSScriptRoot/Manage-Driver.ps1" $stage
Copy-Item "$PSScriptRoot/Driver-Status.ps1" $stage
Copy-Item "$PSScriptRoot/INSTALL.txt" $stage

$kits = "${env:ProgramFiles(x86)}/Windows Kits/10"
function Find-KitTool([string]$Name, [string]$Architecture) {
    $tool = Get-Item @("$kits/bin/*/$Architecture/$Name", "$kits/Tools/*/$Architecture/$Name", "$kits/bin/$Architecture/$Name", "$kits/Tools/$Architecture/$Name") -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $tool) { throw "WDK tool not found: $Architecture/$Name" }
    $tool.FullName
}
function Invoke-Checked([string]$Tool, [string[]]$Arguments) {
    Write-Host "Running $([IO.Path]::GetFileName($Tool))"
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed with exit code $LASTEXITCODE" }
}
Copy-Item (Find-KitTool 'devcon.exe' 'x64') "$stage/devcon.exe"
Copy-Item "$root/drivers/devcon-LICENSE" $stage

# Windows 10/11 contain KMDF in-box; no legacy co-installer is required.
$inf = Get-Content "$root/sys/ViGEmBus.inf" -Raw
$inf = $inf -replace '(?m)^.*WdfCoInstaller.*\r?\n', ''
$inf = $inf -replace '(?m)^ViGEmBus_Device_CoInstaller_CopyFiles = 11\r?\n', ''
$inf = $inf -replace '(?ms)^\[ViGEmBus_Device\.NT\.CoInstallers\].*?(?=^\[ViGEmBus_Device\.NT\.Wdf\])', ''
$inf = $inf -replace '(?m)^%ManufacturerName%=Standard,.*$', '%ManufacturerName%=Standard,NTamd64'
$inf = $inf -replace '(?ms)^\[Standard\.NTx86\].*?(?=^\[ViGEmBus_Device\.NT\])', ''
$inf | Set-Content "$stage/ViGEmBus.inf" -Encoding ascii
Invoke-Checked (Find-KitTool 'stampinf.exe' 'x64') @('-f', "$stage/ViGEmBus.inf", '-a', 'amd64', '-d', (Get-Date -Format 'MM/dd/yyyy'), '-v', $DriverVersion, '-k', '1.33')
if ((Get-Content "$stage/ViGEmBus.inf" -Raw) -match '\$KMDF|\$ARCH|DriverVer=\s*;') {
    throw 'Unresolved INF build placeholders.'
}

# This is a test build. Never imply that a self-signed certificate is WHQL signing.
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=ViGEmBus-ezz Test Build' -CertStoreLocation Cert:/CurrentUser/My -HashAlgorithm SHA256
$password = [guid]::NewGuid().ToString('N')
$pfx = Join-Path $env:RUNNER_TEMP 'ViGEmBus-test.pfx'
try {
    Export-PfxCertificate -Cert $cert -FilePath $pfx -Password (ConvertTo-SecureString $password -AsPlainText -Force) | Out-Null
    Export-Certificate -Cert $cert -FilePath "$stage/ViGEmBus-Test.cer" | Out-Null
    $signTool = Find-KitTool 'signtool.exe' 'x64'
    Invoke-Checked $signTool @('sign', '/fd', 'SHA256', '/f', $pfx, '/p', $password, "$stage/ViGEmBus.sys")
    Invoke-Checked (Find-KitTool 'Inf2Cat.exe' 'x86') @("/driver:$stage", '/os:10_X64', '/uselocaltime')
    Invoke-Checked $signTool @('sign', '/fd', 'SHA256', '/f', $pfx, '/p', $password, "$stage/ViGEmBus.cat")
    # CurrentUser/Root import can display a protected-root confirmation dialog.
    # The disposable elevated CI runner can use the machine store without UI.
    Invoke-Checked "$env:windir/System32/certutil.exe" @('-f', '-addstore', 'Root', "$stage/ViGEmBus-Test.cer")
    Invoke-Checked $signTool @('verify', '/pa', '/v', "$stage/ViGEmBus.sys")
    Invoke-Checked $signTool @('verify', '/pa', '/v', '/c', "$stage/ViGEmBus.cat", "$stage/ViGEmBus.sys")
    Invoke-Checked $signTool @('verify', '/pa', '/v', '/c', "$stage/ViGEmBus.cat", "$stage/ViGEmBus.inf")
} finally {
    Remove-Item $pfx -ErrorAction SilentlyContinue
    Remove-Item "Cert:/CurrentUser/My/$($cert.Thumbprint)" -ErrorAction SilentlyContinue
    Remove-Item "Cert:/LocalMachine/Root/$($cert.Thumbprint)" -ErrorAction SilentlyContinue
}

$compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
$iscc = if ($compiler) { $compiler.Source } else { "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe" }
if (-not (Test-Path $iscc)) { throw 'Inno Setup compiler not found.' }
Invoke-Checked $iscc @("/DAppVersion=$Version", "/DPayloadDir=$stage", "/DOutputDir=$root/artifacts", "$PSScriptRoot/ViGEmBus.iss")
$exe = Join-Path $root "artifacts/ViGEmBus_Setup_${Version}_x64_TEST_SIGNED.exe"
if (-not (Test-Path $exe)) { throw 'Setup EXE was not created.' }
Get-FileHash $exe -Algorithm SHA256 | Format-List
