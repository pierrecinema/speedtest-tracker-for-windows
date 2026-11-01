; Compile with: ISCC /DAppVersion=1.15.1-win.1 /DStageDir=..\build\out\stage /O..\build\out setup.iss
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef StageDir
  #define StageDir "..\build\out\stage"
#endif

[Setup]
AppId={{7E3B2C94-6B1F-4C59-9A9E-3F0F6C2D8A11}
AppName=Speedtest Tracker for Windows
AppVersion={#AppVersion}
AppPublisher=pierrecinema
AppPublisherURL=https://github.com/pierrecinema/speedtest-tracker-for-windows
DefaultDirName={autopf}\Speedtest Tracker
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputBaseFilename=SpeedtestTracker-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=Speedtest Tracker for Windows
CloseApplications=no

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Run]
Filename: "{code:GetLocalUrl}"; Description: "Web-Oberfläche öffnen"; Flags: postinstall shellexec nowait skipifsilent; Check: InstallSucceeded

[Code]
var
  SettingsPage: TInputQueryWizardPage;
  ProvisionOk: Boolean;

function PowerShellPath: String;
begin
  Result := ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe');
end;

function DataDir: String;
begin
  Result := ExpandConstant('{commonappdata}\SpeedtestTracker');
end;

function IsUpdate: Boolean;
begin
  Result := FileExists(DataDir + '\.env');
end;

function RunProvision(Arguments: String): Integer;
var
  Code: Integer;
begin
  if not Exec(PowerShellPath,
      '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\installer\provision.ps1') + '" -Root "' + ExpandConstant('{app}') + '" ' + Arguments,
      '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Code := -1;
  Result := Code;
end;

procedure InitializeWizard;
begin
  SettingsPage := CreateInputQueryPage(wpSelectTasks, 'Einstellungen',
    'Wie soll Speedtest Tracker laufen?',
    'Die Werte lassen sich später in der Datei .env ändern.');
  SettingsPage.Add('Port der Web-Oberfläche:', False);
  SettingsPage.Add('Zeitplan der Messungen (Cron):', False);
  SettingsPage.Values[0] := '8765';
  SettingsPage.Values[1] := '30 * * * *';
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = SettingsPage.ID) and IsUpdate;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Port: Integer;
begin
  Result := True;
  if CurPageID = SettingsPage.ID then
  begin
    Port := StrToIntDef(SettingsPage.Values[0], 0);
    if (Port < 1) or (Port > 65535) then
    begin
      MsgBox('Bitte einen Port zwischen 1 und 65535 eingeben.', mbError, MB_OK);
      Result := False;
    end
    else if Trim(SettingsPage.Values[1]) = '' then
    begin
      MsgBox('Bitte einen Zeitplan eingeben.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if FileExists(ExpandConstant('{app}\installer\provision.ps1')) then
    RunProvision('-Action StopService');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Code: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    WizardForm.StatusLabel.Caption := 'Microsoft-Laufzeitbibliotheken werden eingerichtet ...';
    Exec(ExpandConstant('{app}\vc_redist.x64.exe'), '/install /quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, Code);

    WizardForm.StatusLabel.Caption := 'Speedtest Tracker wird eingerichtet ...';
    Code := RunProvision('-Action Install -Port ' + SettingsPage.Values[0] + ' -Schedule "' + SettingsPage.Values[1] + '"');
    ProvisionOk := Code = 0;
    if not ProvisionOk then
      SuppressibleMsgBox('Die Einrichtung ist fehlgeschlagen. Der Dienst läuft nicht.' + #13#10 +
        'Details stehen in ' + ExpandConstant('{tmp}\..\SpeedtestTracker-install.log'), mbCriticalError, MB_OK, IDOK);
  end;
end;

function InstallSucceeded: Boolean;
begin
  Result := ProvisionOk;
end;

function GetLocalUrl(Param: String): String;
begin
  Result := 'http://localhost:' + SettingsPage.Values[0];
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Arguments: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    Arguments := '-Action Uninstall';
    if SuppressibleMsgBox('Sollen auch alle Messwerte und Einstellungen gelöscht werden?', mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES then
      Arguments := Arguments + ' -RemoveData';
    RunProvision(Arguments);
  end;
end;
