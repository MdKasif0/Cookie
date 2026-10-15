; ==============================================================================
; Cookie Desktop Companion for Windows - Inno Setup Script
; Phase 5: Premium Polish, Distribution, Updates, and Release
; ==============================================================================

#define MyAppName "Cookie"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "Md Kasif Uddin"
#define MyAppURL "https://getcookie.app"
#define MyAppExeName "Cookie.exe"
#define MyAppId "{{B8B2E05A-8756-4279-843B-FDFBF7E8DFD1}}"

[Setup]
; Unique application GUID for upgrade detection and uninstallation
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/updates
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\..\dist\windows\installer
OutputBaseFilename=CookieSetup-{#MyAppVersion}
SetupIconFile=..\..\Cookie.Windows\Resources\Cookie.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

; Support non-administrative per-user installation without elevation prompts
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline

; Prevent accidental installation over a running instance
AppMutex=CookieDesktopCompanion_SingleInstance_Mutex_2026

; UI Polish
DisableWelcomePage=no
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startupicon"; Description: "Launch Cookie automatically when Windows starts"; GroupDescription: "Startup options:"

[Files]
; Distribute published self-contained application payload
Source: "..\..\dist\windows\win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\Resources\Cookie.ico"; AppUserModelID: "Cookie.DesktopCompanion"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\Resources\Cookie.ico"; Tasks: desktopicon; AppUserModelID: "Cookie.DesktopCompanion"

[Registry]
; Optional launch at startup task
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "CookieDesktopCompanion"; ValueData: """{app}\{#MyAppExeName}"""; Tasks: startupicon; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Clean up local application binaries on uninstall while strictly preserving user profile data in %APPDATA%\Cookie
Type: files; Name: "{app}\*.log"
Type: files; Name: "{app}\*.tmp"
