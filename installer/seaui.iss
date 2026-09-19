; ============================================================
; SeaUI 3.0.0 安装包脚本（Inno Setup 6）
; 编译（在仓库根执行）：
;   ISCC.exe installer\seaui.iss
;   默认 ISCC 路径：C:\Program Files (x86)\Inno Setup 6\ISCC.exe
; 前置产物：
;   rov_flutter\build\windows\x64\runner\Release\rov_flutter.exe
;     —— 由 `flutter build windows --release` 生成（未构建时先执行该命令）
;   dist\SeaUIBackend.exe
;     —— 由 installer\build_backend.bat（PyInstaller）生成
; 产物：installer\Output\SeaUI-Setup-3.0.0.exe
; ============================================================

#define MyAppName "SeaUI"
#define MyAppVersion "3.0.0"
#define MyAppPublisher "SeaUI"
#define MyAppExeName "SeaUI.exe"
#define FlutterRelease "..\rov_flutter\build\windows\x64\runner\Release"
#define BackendExe "..\dist\SeaUIBackend.exe"

[Setup]
AppId={{7A1C3E52-9B4D-4F68-8D2A-3C5E1B9F0A21}
AppName={#MyAppName} 水下机器人控制站
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
VersionInfoVersion=3.0.0.0
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\rov_flutter\windows\runner\resources\app_icon.ico
OutputDir=Output
OutputBaseFilename=SeaUI-Setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; 桌面快捷方式：默认勾选
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
; 开机自启动：可选项，默认不勾选；写入 HKCU Run（当前用户）
Name: "autostart"; Description: "开机自动启动 SeaUI（当前用户登录后拉起）"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
; Flutter 客户端全部运行时文件（排除原始 exe，单独改名安装为 SeaUI.exe）
Source: "{#FlutterRelease}\*"; DestDir: "{app}"; Excludes: "rov_flutter.exe"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{#FlutterRelease}\rov_flutter.exe"; DestDir: "{app}"; DestName: "{#MyAppExeName}"; Flags: ignoreversion
; PyInstaller 打包的后端（onefile，已内置 best.onnx）
Source: "{#BackendExe}"; DestDir: "{app}\backend"; Flags: ignoreversion
; 客户须知
Source: "README.txt"; DestDir: "{app}"; Flags: ignoreversion

[Registry]
; 开机自启动：HKCU Run 指向 SeaUI.exe，仅当勾选 autostart 任务时写入
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "SeaUI"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: autostart

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
