# SeaUI 硬规则基线（CONTEXT_BASELINE）

> 用户设定过的约束，任何任务先对照本文件。

## 铁律
1. **数据真实回传**：界面展示的每个数值必须溯源真实硬件链路（RDK X5→Pixhawk/传感器→backend→UI）；禁止合成/兜底/残影数据；断链显示"⚠ 信号丢失"（StaleBadge ≥5s）；sim 模式必须有黄色"仿真数据"角标。落库/查询只认 source='rdk'。
2. **风格保留**：界面保持原有风格（用户称 GitHub light），默认浅色主题；改动风格需用户明确同意。
3. **署名**：仓库身份 bertholetnadine159-prog；任何 AI（codex/gpt 等）不得成为贡献者；主仓库历史已压缩为单一 Initial commit（1cc31e5），不再展开历史。
4. **空壳不留**：无后端实现的功能入口一律隐藏/删除，不做假开关。
5. **测试套件不可删**：backend/tests(27)、rdkx5/tests(34)、rov_flutter/test(24) 是质量门禁；可删的是一次性探针（已清 rdkx5/tools）。

## 环境事实
- RDK 板卡实际地址：**192.168.5.127**，SSH root/root（旧地址 192.168.127.10/sunrise 已弃用，默认值已全量切换）。
- 本机 Mihomo TUN 会伪造 TCP 连通——链路判断必须用 rdkx5/scripts/check_rdk_link.py（金丝雀端口检测）。
- 板卡部署目录 /home/sunrise/seaUI_rdk；远程拉起用 rdkx5/scripts/launch_board_gateway.py。
- test_seaui.bat 必须 GBK+CRLF 编码（中文 cmd），已加 .gitattributes -text。
- 安全钩子（Mimosa）会拦提交：测试凭据用 os.environ.get 缺省模式、payload 用 pw() 构造；bat 编码问题用 iconv 转 GBK。
- 后端端口：REST 5000 / UI WS 8765；板卡网关 8080。打包态后端 SeaUIBackend.exe（installer/）。

## 当前状态（2026-09-20）
- v3.0.0 商用化已交付（D0..779293d/fcc7521）；真实链路已通：GATEWAY_ONLINE、rdk.connected=true、双摄像头枚举；Pixhawk 未插板卡 USB（插上自动重连）。
- 待办：真机逐字段回传验收（docs/VERIFICATION_STATUS.md 清单）；Inno Setup 编译安装包。
