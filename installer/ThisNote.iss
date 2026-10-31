#define MyAppName "此记 ThisNote"
#define MyAppVersion "1.1.1"
#define MyAppPublisher "ThisNote"
#define MyAppExeName "ThisNote.exe"
#define BuildDir "F:\ThisNote\app\build\windows\x64\runner\Release"

[Setup]
AppId={{8E1B2C3A-4F5D-4A6B-9C7E-2D3F4A5B6C7D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppVerName={#MyAppName} {#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} - 本地优先的写作空间
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
DefaultDirName={localappdata}\Programs\ThisNote
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=F:\ThisNote\dist
OutputBaseFilename=ThisNote-Setup-{#MyAppVersion}
SetupIconFile=F:\ThisNote\app\assets\brand\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Excludes: "this_note.exe"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#BuildDir}\this_note.exe"; DestDir: "{app}"; DestName: "{#MyAppExeName}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动此记"; Flags: nowait postinstall skipifsilent
