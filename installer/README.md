# SeaUI 3.0.0 打包交付指南（维护者向）

本文说明如何在开发机上产出客户可直接安装使用的 SeaUI 安装包（客户机器**无需 Python 环境**）。

## 一、前置条件

| 依赖 | 用途 | 备注 |
| --- | --- | --- |
| Flutter SDK（Windows desktop 已启用） | 编译客户端 | `flutter build windows --release` |
| Python 3.10+ 与 `backend/requirements.txt` 依赖 | 打包后端 | 开发机已装（含 CUDA torch 亦可，见下） |
| pyinstaller ≥ 6.17 | 后端 onefile 打包 | `pip install pyinstaller`（失败用 `-i https://pypi.tuna.tsinghua.edu.cn/simple`） |
| Inno Setup 6（ISCC.exe） | 生成安装包 | 默认路径 `C:\Program Files (x86)\Inno Setup 6\ISCC.exe` |
| 仓库根 `best.onnx` | local 模式推理权重 | 打包时自动打入后端 exe |

## 二、打包步骤（按顺序）

```bat
:: 1) 客户端（生成 rov_flutter\build\windows\x64\runner\Release\rov_flutter.exe）
cd rov_flutter
flutter build windows --release
cd ..

:: 2) 后端 onefile（生成 dist\SeaUIBackend.exe，git 未忽略，勿提交）
installer\build_backend.bat
:: 等价于：python -m PyInstaller --noconfirm --clean installer\SeaUIBackend.spec

:: 3) 后端冒烟（返回 ok 即通过；验证完 Ctrl+C 结束）
set ROV_BACKEND_MODE=sim&& set ROV_WS_PORT=18799&& set ROV_API_PORT=15099&& dist\SeaUIBackend.exe
curl http://127.0.0.1:15099/api/health

:: 4) 安装包（生成 installer\Output\SeaUI-Setup-3.0.0.exe）
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\seaui.iss
```

### 后端打包要点（installer/SeaUIBackend.spec）

- **onefile**：单个 `SeaUIBackend.exe`，含 `best.onnx`（解包目录根）。
- **CUDA 过滤**：开发机 torch 为 CUDA 版（>4GB），spec 在 Analysis 后剔除全部 CUDA
  运行库，仅保留 `torch_cpu` 等 CPU 部件；推理实际由 onnxruntime 承担，
  torch 仅用于 ultralytics 的 CPU 后处理，打包体积与功能均正常。
- **路径纠偏**：app.py 用 `__file__` 推导模型/数据库路径，onefile 下指向临时解包目录；
  运行时钩子 `installer/pyi_rth_seaui_paths.py` 通过环境变量 setdefault 修正：
  - `ROV_MODEL_PATH` → 解包目录内 best.onnx；
  - `ROV_DB_PATH` → `%LOCALAPPDATA%\SeaUI\data\seaUI.db`（持久化，客户数据不随临时目录丢失）。
  显式设置的环境变量优先，部署方可覆盖。

### Inno Setup 脚本要点（installer/seaui.iss）

- 布局：`{app}\SeaUI.exe`（rov_flutter.exe 改名）+ 客户端运行时文件、
  `{app}\backend\SeaUIBackend.exe`、`{app}\README.txt`。
- 任务：桌面快捷方式（默认勾选）；开机自启动（可选，HKCU Run，卸载自动清理）。
- 界面语言：简体中文优先（`compiler:Languages\ChineseSimplified.isl`，Inno 6 自带），
  英文兜底；若本机 Languages 目录缺失中文语言文件，删除 [Languages] 中对应行即可。
- 版本：3.0.0；`ArchitecturesInstallIn64BitMode=x64`（Inno 6.3+ 可改 `x64compatible`）。

## 三、产物清单

| 产物 | 路径 | 说明 |
| --- | --- | --- |
| 客户端 | `rov_flutter/build/windows/x64/runner/Release/rov_flutter.exe`（及其 `data/`、`flutter_windows.dll`） | Flutter release 构建，git 已忽略 |
| 后端 | `dist/SeaUIBackend.exe` | onefile，含 best.onnx；git 未忽略，**勿提交** |
| 安装包 | `installer/Output/SeaUI-Setup-3.0.0.exe` | 客户交付物 |
| 交付文档 | `installer/README.txt` | 随安装包落至 `{app}\README.txt`（客户向） |

## 四、客户安装后的首次启动

1. 运行 `SeaUI-Setup-3.0.0.exe`，按向导安装（默认装至 `C:\Program Files\SeaUI`）。
2. 双击 `SeaUI.exe`：客户端自动拉起 `backend\SeaUIBackend.exe`
   （仅监听 127.0.0.1；防火墙提示选择允许）。
3. 登录：初始超管口令由交付方部署时提供（部署方可通过环境变量
   `ROV_SUPER_ADMIN_PASSWORD` 设置随机初始口令，交付物与文档均不含明文口令）。
4. **超管首登强制改密**：super_admin 使用初始口令登录时，后端返回
   `must_change_password=true`，客户端弹出强制改密对话框，改密成功前不进入主界面。
5. 详细说明见随包 `README.txt`（运行模式、端口、数据位置、常见问题）。

## 五、已知注意事项

- onefile 首次启动需解包到临时目录，冷启动比 onedir 慢数秒，属正常现象；
  如需更快启动，可将 spec 的 onefile 布局改为 onedir（EXE 去 binaries/datas + COLLECT），
  并同步调整 seaui.iss 的 backend 段打包方式。
- `dist/`、`installer/Output/` 为构建产物，均不提交 git。
- 卸载不会删除 `%LOCALAPPDATA%\SeaUI` 下的客户数据库。
