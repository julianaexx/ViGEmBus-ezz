#ifndef AppVersion
  #define AppVersion "1.0.2"
#endif

[Setup]
AppId={{D354E729-E449-44D6-92FB-467D04B2F4A0}
AppName=ViGEmBus-ezz (Xbox Series identity, test build)
AppVersion={#AppVersion}
AppPublisher=ViGEmBus-ezz contributors
AppPublisherURL=https://github.com/julianaexx/ViGEmBus-ezz
DefaultDirName={autopf}\ViGEmBus-ezz
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0.22000
PrivilegesRequired=admin
DisableProgramGroupPage=yes
DisableDirPage=yes
LicenseFile=..\LICENSE
InfoBeforeFile=INSTALL.txt
OutputDir={#OutputDir}
OutputBaseFilename=ViGEmBus_Setup_{#AppVersion}_x64_TEST_SIGNED
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
UninstallDisplayName=ViGEmBus-ezz test driver
CloseApplications=no

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion
Source: "Manage-Driver.ps1"; Flags: dontcopy

[Code]
var
  DriverNeedsRestart: Boolean;

function RunDriver(Mode: String; Script: String; var ResultCode: Integer): Boolean;
begin
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + Script + '" -Mode ' + Mode,
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  ExtractTemporaryFile('Manage-Driver.ps1');
  if not RunDriver('Check', ExpandConstant('{tmp}\Manage-Driver.ps1'), ResultCode) or (ResultCode <> 0) then
    Result := 'This is a TEST-SIGNED driver. Enable Windows test-signing mode and restart first. Setup has not changed your boot settings. See INSTALL.txt and %TEMP%\ViGEmBus-ezz-setup.log.'
  else
    Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then begin
    if not RunDriver('Install', ExpandConstant('{app}\Manage-Driver.ps1'), ResultCode) then
      RaiseException('Unable to start driver installation.');
    if (ResultCode <> 0) and (ResultCode <> 3010) then
      RaiseException('Driver installation failed. See %TEMP%\ViGEmBus-ezz-setup.log and C:\Windows\INF\setupapi.dev.log.');
    DriverNeedsRestart := ResultCode = 3010;
  end;
end;

function NeedRestart(): Boolean;
begin
  Result := DriverNeedsRestart;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then begin
    if not RunDriver('Uninstall', ExpandConstant('{app}\Manage-Driver.ps1'), ResultCode) then
      RaiseException('Unable to start driver removal.');
    if (ResultCode <> 0) and (ResultCode <> 3010) then
      RaiseException('Driver removal failed. See %TEMP%\ViGEmBus-ezz-setup.log.');
  end;
end;
