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

## 追加（2026-09-22 真机调试）
- Pixhawk 已插板卡 USB；SERVO5-8_FUNCTION 已纠 0、SERVO9-16_FUNCTION 显式 0、DISARM_DELAY=0、FRAME_CLASS=2、BRD_PWM_COUNT=6（后者重启才生效，未确认）。
- 网关重启必须 pkill -9 -f 'gateway.py'（deploy 的启动名与 launch 不同，杀错=旧代码永驻）。
- 新增网关 WS 命令：motor_test（测试窗口循环让出被测通道）、pixhawk_reboot（MAVLink 246，实测未触发真重启）。
- 电机不转真因待定：软件输出已逐路实测到位；用户电调为"上电自校中点"型，需在稳定 1500 信号下给电调重新上电；电调循环三声=看到信号但不认中点（或未收到信号）。

## 追加（2026-09-29 传感器调试）
- **40-pin 线号陷阱**：逻辑 GPIO 编号 ≠ lsio 控制器线号。I2C5 在 lsio_uart3 球上。1-Wire 权威映射（docs/PINMAP.md §4：官方 40pin 全表+出厂 RDK_X5_PIN+板卡 gpioinfo/pinmux 三源一致）：**37脚=线22/SOC401（BCM26）、15脚=线9/SOC388（BCM22）、线26/SOC405 不在 40-pin 排针上**。09-21 条目里"线26=37脚"系出厂表 CVM 名（BCM 名）误当 lsio 线号；其"线26 读到稳定高电平=探头1+上拉在线"与本文件同日"DS18B20 供电+上拉未完成"矛盾（悬空垫可被内部弱上拉读高），存疑保留。2026-09-29 overlay 已重绑：onewire-0=37脚（线22）/master1、onewire-1=15脚（线9）/master2，与探头实际接线（探头1=37脚、探头2=15脚）及 config.yaml 对应关系一致。
- DYP 电应普声纳协议（arduino_sensors_demo 范例考证）：ff_uart 分 auto（自动上报）/ctrl（传感器 RX 拉低≥500µs 触发一帧）两型；A02_IIC 型地址 0x74（写 0x02=0xB4，60ms 后读 0x03 两字节）。
- 声纳诊断判据：仅自身回波（00 00 00 00）= 收发器未驱动（未上电/损坏）；全静默 = 线不在该脚。DS18B20 无从机 = 查 VCC 3.3V + DQ-3.3V 4.7k 上拉。
- 工具（板卡 /home/sunrise/seaUI_rdk/scripts/）：super_query.sh（一键四路体检）、sensor_watch.sh（每分钟后台记录 /tmp/sensor_watch.log，用 setsid 启动否则随 SSH 死）、ms5837_selftest.py（CRC4 金标准）、uart_probe.py（--loopback/--trigger）。UART1=8/10脚 ttyS1、UART7=11/13脚 ttyS7、I2C5=3/5脚。
- 板内 i2c-7/8（DSP 域 320a0000）扫描刷超时属正常现象；板上 mawk 无 strtonum（awk 文本处理用 python 代替）。
- 四路传感器当前阻塞在硬件项：声纳模块电源输入脚供电、DS18B20 3.3V 供电+DQ 上拉 4.7k——完成即自动上线（gateway 每 5s 推遥测）。
- **声纳"应答"两义性（2026-09-29 判据修复）**：L08-V3.0 双路对每次 40ms 触发稳定回合法帧 `ff ff fd fb`（0xFFFD=65533），12+ 轮无一静默、无一真实距离。65533 远超 L08 量程上限（dypcn 产品页：UART 版 5~200cm、RS485/L08B 版 8~300cm），判状态码非测距；其确切语义规格书未定义（公开渠道无权威来源，datasheet 需向电应普获取；同族 0xFFFB=出水 为仓库转述），存疑记录。修复：l08_probe.py/sensors.py/watch_sensors.py 统一 ≥30000mm 判状态码——VERDICT 区分"协议应答（存活）"与"有效测距"，网关遥测由误导性 "out of range: 65.533 m" 改为 "status frame 0xFFFD（65533，非测距）"。**板卡 super_query 的 L08_OK=协议存活标记，声学验收须看"距离 = Nmm 且 <30000"**。
- **声纳 0xFFFD 物理层鉴别（2026-09-29 深挖）**：触发宽度扫描 20/40/60/100/150ms（含低于规格的 20ms）×共享/停网关独占两场景——双路恒回 0xFFFD、延迟恒定 ~5.2ms（< 规格 ~18ms 声学窗，属罐头应答，非触发协议问题）；独占下无触发被动收帧仍 ~1 帧/10s 自发 0xFFFD（模组持续自报状态）；9600 波特零字节排除双波特率。供电在规格内推测（官方 3.3~5.0V/≤20mA，UART TX 驱动正常）。**台架实况已由用户确认（2026-09-29）**：双模组均在空气中（8m 版对空无目标）、供电实测 5V 额定——结合规格书 §3.3.1（出水帧 0xFFFB 需 Modbus 0x0401 写 1+水下 30cm 标定，默认关闭；离水未标定输出无有效回波哨兵 0xFFFD），**判定 0xFFFD=空气无回波的规格预期，非故障**。软件侧已收口：探针/网关/看板/汇总统一按状态码如实标注。剩余为入水终验（静水槽 ≥50cm、探头入水 ≥10cm 对 ~30cm 壁应读 ≈300mm；水中仍 0xFFFD 才查供电/标定）与出水检测启用（水下按 §3.3.2 标定，本轮不做）。

## 追加（2026-09-29 晚·全链暗与陈旧缓存判定）
- **"网关遥测有帧"两义性**：网关进程被杀/读循环冻结时，`_readings` 冻结在最后一次值继续上报——遥测里 sonar=0xFFFD 可能是**已死进程的陈旧缓存**。判活三件套：①停网关后 fuser 确认串口无占用，再独占探针；②双快照 ts 是否前进；③报错文案是否随物理动作变化。本轮实测：0xFFFD 为旧进程缓存，实时（新网关）双声纳=「short frame」即真静默。
- **声纳当前定论（独占串口三重验证）**：被动监听 0 字节 + 规格触发 0 字节 + 网关实时轮询 short frame——双路模组当前**零输出**（今日早些时候还是 L08_OK 4/4，中间用户重接线）→ 首要嫌疑：接线时碰掉声纳 5V 供电/信号线。
- **I2C5 定论**：GPIO 读 3/5 脚 SDA/SCL 均高、i2cdetect 时 dmesg 无新 controller timeout（旧刷屏为开机早期日志）→ 总线健康；VEML×2+MS5837 实时 NACK（Errno 121）→ 器件不应答=没供电/SDA-SCL 接反（互换时线仍双高、同样 NACK）/接错脚/损坏。
- **1-Wire 定论**：双 master 正常、内核搜索 attempts 递增；37/15 脚 pad 均高电平（15脚从"稳定低"变"高"=用户所补上拉已作用到 pad）；但双探头无存在应答 → DQ 未真接 pad / 探头未供电 / 探头损坏。上拉环节已过，缺"芯片应答"环节。
- **平台行为**：w1-gpio unbind 后 sysfs `direction` 写 EPERM（pad 方向切换被拒），手动位敲存在脉冲在 RDK X5 不可行——内核搜索即为权威存在判据。诊断探针残留 sysfs export 会让后续 bind EBUSY（dmesg: gpio_request failed -16）→ 探针 finally 必须 unexport。
- **telemetry_snapshot.py 只取 hello 后第一条消息的坑**：WS 混推 video frame 与 telemetry，第一条多为帧消息→打印为空误判"网关无响应"。已修为循环过滤 type==telemetry。board_super_query 的 MARKER 同日修：只认 "VERDICT: L08_OK" 行。
- 板卡网关重启命令（经 paramiko）：`cd /home/sunrise/seaUI_rdk && nohup python3 -m gateway >/tmp/gateway_restart.log 2>&1 </dev/null & disown`（`</dev/null` 不可省，否则 SSH 通道挂起超时）。Pixhawk /dev/ttyACM0 当前不存在（USB 未接）。

## 追加（2026-09-30 泵/舵机重接线 AUX1/2/3）
- **通道映射变更（用户重接线）**：泵（吸捕电机 1/2）AUX5/6→**AUX1/AUX2（通道 9/10）**；抓取舵机 AUX4→**AUX3（通道 11）**。改动点：config.yaml（suction_channels/servo_channel）、pixhawk_link.py（ENSURE_FUNCTION_ZERO_CHANNELS 加通道 9）、SimulatedPixhawk、test_auto_arm 夹具与断言、pixhawk_param_tool.py / restore_sub_params.py / test_all_motors.py / pump_signal_probe.py / pixhawk_raw_probe.py。
- **AUX 防截断锚点随迁 SERVO9→SERVO12**：AUX 组内必须保留一个非 None 功能位通道（Lights1=11），否则飞控出站包 AUX 字段整组截断（2026-09-29 实测硬规则）。锚点原在 SERVO9（当时 AUX1 未接外设）；泵改接 AUX1/ch9 后，若 SERVO9 保持 Lights1 功能位会吞掉泵的 DO_SET_SERVO——锚点挪到未接外设的 SERVO12（AUX4）。BRD_PWM_COUNT=6 不变（泵/舵机均在 AUX1-6）。
- 主控页控制条已有"吸泵"开关（suction power 0-100，力度跟随推进器动力滑块）；操作页方向卡/Q 键为按住式吸捕。
- **泵输出 20% 硬钳位（2026-09-30 事故后新增）**：用户报告泵过热烧毁。网关 suction 命令加 `suction_max_power_percent`（config.yaml，默认 20）网关侧硬钳位——UI/后端任何路径都无法超过，下水作业前由用户调高。事故成因分析：部署新通道映射前，防截断锚点 SERVO9=Lights1（≈1500us≈单向泵 50% 常转）恰落在用户新接的 AUX1 泵线上（auto-armed 状态、UI 无法停——UI 泵命令当时还走旧通道 13/14）；22:55 部署后 SERVO9=0+1000 才真正切断。教训：**硬件改接线前必须先部署对应通道映射并重启网关**。

## 追加（2026-09-30 晚·I2C5 控制器卡死与可信扫描）
- **I2C 控制器卡死与 NACK 的鉴别（关键判据）**：Errno 121=事务正常完成、器件 NACK（总线健康）；**Errno 110=控制器级超时**（事务根本没完成）——后者出现时任何"扫描无应答"全部作废。判别法：读任意地址看 errno + dmesg 是否刷 `controller timed out`。卡死诱因（本轮实证）：用户在传感器侧断电/复电操作期间总线被拉住，控制器"总线忙"锁死，sysfs unbind 可解绑但 **bind 的 probe 会永久挂死**（卡死 shell 进程为证）——**唯一复位手段是重启板卡**。9-clock+STOP（i2c_bus_recover.py）曾在卡死后恢复过一次 NACK，但不可靠，重启才是终解。
- **I2C5 终局扫描（重启后、验证健康总线）**：全地址 0x03-0x77 读探测 117/117 全部规范 NACK、零超时——**深度计在 I2C5 上电气缺席**（没供电/SDA-SCL 接反/非 I2C 器件/损坏四选一）。断电/复电监听（i2c5_power_watch.py：75s/300s 窗口，线电平+全地址轮询+0x76 errno 追踪）全程零事件——复电瞬间亦无应答。用户澄清 I2C5 仅深度计一个器件（VEML7700 未装，config 已禁用）。
- 板卡 2026-09-30 18:11 重启过（I2C 控制器复位）；重启后需手动拉起：gateway（nohup 配方）+ sensor_watch.sh（setsid）。USB 摄像头当前未接（vision: camera start failed）。

## 追加（2026-09-29 夜·飞控重刷与电机测试）
- **铁则（用户明确要求，永远生效）：任何让电机转动前必须预告并倒计时 10 秒。**
- **电机测试转速上限 20%（用户 2026-09-29 指定）**：主推 20% = **1660us**（换算约定：1580us=10%，80us/10%）；泵（单向，1000=停，量程 1000-2000）20% = **1200us**（与 control/ 模块 `_percent_to_pwm` 一致）。
- **飞控掉固件判据（一锤定音）**：`udevadm info -n /dev/ttyACM0` 的 ID_MODEL 含 **PX4_BL**（Bootloader 态）+ 裸串口 0 字节 + 假心跳 srcSystem=0。恢复：`rdkx5/scripts/flash_ardusub_bootloader.py`（固件 rdkx5/firmware/ardusub_410_pixhawk1.apj）；刷后必跑 `restore_sub_params.py`（SERVO5-8_FUNCTION=0/DISARM_DELAY=0/FRAME_CLASS=2/BRD_PWM_COUNT=6）。
- **auto-arm 新语义**：必须 COMMAND_ACK(400) result=0 才算解锁完成；被拒/丢 ACK 3s 限频重发；操作员 disarm/急停终结 auto-arm 使命（红线）。
- **网关已 systemd 化**：`systemctl restart seaul-gateway`，日志 `journalctl -u seaul-gateway -o cat`；nohup 手动方式作废（上节"手动拉起"条目过时）。
- MAIN1-4 逐机测试流程（FUNCTION=33-36 混控占用 DO_SET_SERVO）：先 correct_param SERVO1-4_FUNCTION→0 → 逐台 motor_test → **测完必须恢复 33/34/35/36**。MAIN5-8/泵 13/14（FUNCTION=0）可直接 motor_test。

## 追加（2026-09-29 深夜·全电机测试与 IOMCU 掉电缺陷）
- **电机测试转速上限 20% 已实测**：主推 1660us×8 路 SERVO_OUTPUT_RAW 全部确认输出；泵 1200us 闭环 PUMP_PWM_OK（ch13/14 实达 1200）。**用户声明电调当前未上电——以上均为信号级证据，物理转动须上电后目视复验（先倒计时 10 秒）**。
- **重大板级缺陷（实测两轮重启确认）：本克隆板 IOMCU 参数掉电不保持**——SERVO5-8_FUNCTION 每次飞控重启回默认 37-40，auto-arm 后 ArduSub 4.1 混控缺陷把 MAIN5-8 打到满推 1900（中性值！）。**网关已自愈**：`_ensure_output_functions()` 每次链路建立先重发 SERVO5-16_FUNCTION=0（PARAM_SET 对 RAM 即时生效）→ 初始化电调 → auto-arm。验证：auto-arm 后 motors_pwm=[1500×8]。操作员 disarm 即停（auto-arm 不会重解锁）。
- **AUX 出站截断陷阱**：ArduPilot 的 SERVO_OUTPUT_RAW 按"活跃通道"截断——AUX 无值时包里根本没有 servo9-16 字段（pymavlink 无该属性，getattr 默认 0 会伪装成"输出 0"）。判定 AUX 存活要么看 port=1/16 字段包是否出现，要么主动 DO_SET_SERVO 后看包是否长出 AUX 字段。重启#1 后 AUX 活（包带 AUX 值），重启#2/#3 后 AUX 字段消失且发 DO_SET_SERVO 也不长出来——**BRD_PWM_COUNT 读回 6 但本次开机 AUX 未激活，疑似板级参数存储/引脚配置缺陷，机制未明**。泵通道时好时坏即此因。
- 246 重启在本次刷机后可用（每次都有 bootloader→固件的 USB 重枚举佐证）；但重启后 FC 可能出现 armed=True 的异常状态（克隆板怪癖，未解）。
- 工具新增：test_all_motors.py（20% 全电机测试+倒计时+逐台采样）、pixhawk_param_tool.py（--mode read/fix）、ch13_probe.py（AUX 激活判定）、pump_signal_probe.py（泵闭环）、pixhawk_raw_probe.py（SERVO_OUTPUT_RAW 按端口聚合）。
