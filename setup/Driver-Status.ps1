function Get-DriverInstallationStatus {
    param([string]$PackageDir, [bool]$RebootRequested = $false)
    $hardwareId = 'Nefarius\ViGEmBus\Gen1'
    $inf = Get-Content "$PackageDir/ViGEmBus.inf" -Raw
    if ($inf -notmatch '(?m)^DriverVer\s*=\s*[^,\r\n]+,\s*([\d.]+)') {
        throw 'Cannot read the expected driver version from the package.'
    }
    $expectedVersion = $Matches[1]
    $infHash = (Get-FileHash "$PackageDir/ViGEmBus.inf" -Algorithm SHA256).Hash
    $oemInfs = @(Get-ChildItem "$env:windir/INF/oem*.inf" | Where-Object {
        (Get-FileHash $_.FullName -Algorithm SHA256).Hash -eq $infHash
    })
    if ($oemInfs.Count -eq 0) { throw 'The matching driver package was not found in the Windows driver store.' }
    $devices = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.HardwareID -contains $hardwareId })
    if ($devices.Count -eq 0) { throw 'The ViGEmBus device was not found in Device Manager.' }
    $bindings = @(Get-CimInstance Win32_PnPSignedDriver)
    foreach ($device in $devices) {
        $code = $device.ConfigManagerErrorCode
        # A restart flag must never hide an actual device error, such as code 52.
        if ($null -eq $code -or $code -notin @(0, 14)) {
            throw "Device Manager reports error code $code for $($device.PNPDeviceID)."
        }
        if ($code -eq 14) { $RebootRequested = $true }
        $binding = @($bindings | Where-Object {
            $_.DeviceID -eq $device.PNPDeviceID -and $_.InfName -in $oemInfs.Name -and
            $_.DriverVersion -eq $expectedVersion
        })
        if ($binding.Count -eq 0 -and -not $RebootRequested) {
            throw "The device is not using this package's driver version $expectedVersion; an older driver may still be active."
        }
    }
    $service = Get-CimInstance Win32_SystemDriver -Filter "Name='ViGEmBus'"
    $installedBinary = "$env:windir/System32/drivers/ViGEmBus.sys"
    $binaryMatches = (Test-Path $installedBinary) -and
        ((Get-FileHash $installedBinary -Algorithm SHA256).Hash -eq
         (Get-FileHash "$PackageDir/ViGEmBus.sys" -Algorithm SHA256).Hash)
    if ($RebootRequested) {
        return [pscustomobject]@{ State = 'RestartRequired'; Version = $expectedVersion; Devices = $devices.Count }
    }
    if (-not $service -or $service.State -ne 'Running') { throw 'The ViGEmBus kernel driver is not running.' }
    if (-not $binaryMatches) { throw 'The installed driver binary does not match this installer.' }
    [pscustomobject]@{ State = 'Ready'; Version = $expectedVersion; Devices = $devices.Count }
}
