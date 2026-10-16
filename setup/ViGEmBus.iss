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
DefaultGroupName=ViGEmBus-ezz
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

[Icons]
Name: "{group}\检查安装状态"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Manage-Driver.ps1"" -Mode Verify -ShowResult"; IconFilename: "{sys}\shell32.dll"; IconIndex: 21

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\Manage-Driver.ps1"" -Mode Verify -ShowResult"; Description: "再次检查驱动安装状态"; Flags: postinstall skipifsilent runhidden; Check: CanVerifyNow

[Code]
var
  DriverNeedsRestart: Boolean;
  InstallReport: String;
  ReportLines: TArrayOfString;

function ResultFile(): String;
begin
  Result := ExpandConstant('{tmp}\driver-result.txt');
end;

function RunDriver(Mode: String; Script: String; var ResultCode: Integer): Boolean;
begin
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + Script + '" -Mode ' + Mode + ' -ResultPath "' + ResultFile() + '"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  ExtractTemporaryFile('Manage-Driver.ps1');
  if not RunDriver('Check', ExpandConstant('{tmp}\Manage-Driver.ps1'), ResultCode) or (ResultCode <> 0) then
    Result := '当前无法安装：这是测试签名驱动，需要先开启 Windows 测试模式并重启。安装器没有修改启动设置。详细信息见 %TEMP%\ViGEmBus-ezz-setup.log。'
  else
    Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode, I: Integer;
begin
  if CurStep = ssPostInstall then begin
    WizardForm.StatusLabel.Caption := '正在安装并检查驱动，请稍候……';
    if not RunDriver('Install', ExpandConstant('{app}\Manage-Driver.ps1'), ResultCode) then
      RaiseException('无法启动驱动安装。');
    if not LoadStringsFromFile(ResultFile(), ReportLines) then
      RaiseException('没有收到驱动安装检查结果，不能确认安装成功。');
    InstallReport := '';
    for I := 0 to GetArrayLength(ReportLines) - 1 do
      InstallReport := InstallReport + ReportLines[I] + #13#10;
    if (ResultCode <> 0) and (ResultCode <> 3010) then
      RaiseException(InstallReport);
    DriverNeedsRestart := ResultCode = 3010;
    SaveStringsToUTF8File(ExpandConstant('{app}\安装结果.txt'), ReportLines, False);
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then begin
    if DriverNeedsRestart then
      WizardForm.FinishedHeadingLabel.Caption := '需要重启，尚未确认新驱动正常运行'
    else
      WizardForm.FinishedHeadingLabel.Caption := '安装成功，驱动正在运行';
    WizardForm.FinishedLabel.Caption := InstallReport;
  end;
end;

function CanVerifyNow(): Boolean;
begin
  Result := not DriverNeedsRestart;
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
