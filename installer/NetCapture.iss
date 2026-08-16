#define MyAppName "Crazy_Batto NetCapture"
#define MyAppVersion "0.6.9"
#define MyAppPublisher "Crazy_Batto Software"
#define MyAppExeName "NetCapture.exe"
#define MyAppIconName "NetCapture-v0.6.9.ico"

[Setup]
AppId={{9C92E21A-0C28-4B19-B8DC-6DF70E859B11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=Netzwerk-Capture-Karte für OBS
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
DefaultDirName={autopf}\Crazy_Batto\NetCapture
DefaultGroupName=Crazy_Batto
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
DisableWelcomePage=no
WizardStyle=classic
WizardSizePercent=100
WizardImageFile=..\assets\WizardImage.bmp
WizardSmallImageFile=..\assets\WizardSmallImage.bmp
WizardImageStretch=yes
WizardKeepAspectRatio=yes
Compression=lzma2/ultra64
SolidCompression=yes
UseSetupLdr=no
OutputDir=..\installer-output
OutputBaseFilename=CrazyBatto-NetCapture-Setup-v0.6.9
SetupIconFile=..\assets\NetCapture.ico
LicenseFile=..\LICENSE.txt
UninstallDisplayIcon={app}\{#MyAppIconName}
UninstallDisplayName={#MyAppName}
Uninstallable=yes
CreateUninstallRegKey=yes
CloseApplications=yes
RestartApplications=no
ChangesEnvironment=no
ChangesAssociations=yes
SetupLogging=yes
AllowNoIcons=yes
UsePreviousAppDir=no
UsePreviousTasks=yes

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
german.WelcomeLabel1=Willkommen beim Installations-Assistenten für [name]
german.WelcomeLabel2=Dieser Assistent wird Sie durch die Installation von [name/ver] begleiten.%n%nEs wird empfohlen, vor der Installation alle anderen Programme zu schließen, damit benötigte Systemdateien ohne Neustart ersetzt werden können.%n%nKlicken Sie auf "Weiter", um fortzufahren.

[Tasks]
Name: "desktopicon"; Description: "Desktop-Verknüpfung erstellen"; GroupDescription: "Verknüpfungen:"; Flags: checkedonce
Name: "startmenuicon"; Description: "Startmenü-Verknüpfung erstellen"; GroupDescription: "Verknüpfungen:"; Flags: checkedonce

[Files]
Source: "..\NetCapture.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\third_party\launcher\NetCapture.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\RELEASE-NOTES-v0.6.9.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD-PARTY-NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\NetCapture.ico"; DestDir: "{app}"; DestName: "{#MyAppIconName}"; Flags: ignoreversion
Source: "..\third_party\ffmpeg\ffmpeg.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\third_party\ffmpeg\FFMPEG-LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\third_party\naudio\NAudio.Core.dll"; DestDir: "{app}\audio"; Flags: ignoreversion
Source: "..\third_party\naudio\NAudio.Wasapi.dll"; DestDir: "{app}\audio"; Flags: ignoreversion
Source: "..\third_party\naudio\AudioPipeCapture.dll"; DestDir: "{app}\audio"; Flags: ignoreversion
Source: "..\third_party\naudio\NAUDIO-LICENSE.txt"; DestDir: "{app}\audio"; Flags: ignoreversion

[InstallDelete]
Type: files; Name: "{autodesktop}\{#MyAppName}.lnk"
Type: files; Name: "{group}\{#MyAppName}.lnk"
Type: files; Name: "{app}\NetCapture.ico"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppIconName}"; IconIndex: 0; Tasks: startmenuicon
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppIconName}"; IconIndex: 0; Tasks: desktopicon
Name: "{group}\NetCapture deinstallieren"; Filename: "{uninstallexe}"; Tasks: startmenuicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{#MyAppName} starten"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\CrazyBatto\NetCapture"
Type: filesandordirs; Name: "{localappdata}\CrazyBatto\NetCapture"
