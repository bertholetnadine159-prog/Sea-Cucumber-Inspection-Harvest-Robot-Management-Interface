# RDK X5 40-Pin 权威脚位表（docs/PINMAP.md）

> 生成：2026-09-29（三源考古整合：官方文档 / 板卡实证 / 仓库考据）
> 适用板卡：**D-Robotics RDK X5 V1.0**（出厂库 `G.model=RDK_X5` 命中 `RDK_X5_PIN` 表；
> 出厂库另有 `EVB_X5_PIN`（X5 EVB 载板）布局完全不同——如 UART7_RX=29脚、I2C1=27/28脚
> （`gpio_pin_data.py:226-253`），**勿与本表混用**）。

## 0. 快速结论（本项目四路）

| 接口 | 球名(lsio线号) | 物理脚 | 判定 |
|---|---|---|---|
| UART7 TXD（前视声纳触发） | LSIO_UART7_TX（**线1**，gpiochip4 line1，SOC380） | **11**（BCM17/GPIO17） | ✅ config.yaml 正确；探针脚本注释相反，已证伪 |
| UART7 RXD（前视声纳数据） | LSIO_UART7_RX（**线0**，gpiochip4 line0，SOC379） | **13**（BCM27/GPIO27） | ✅ 声纳TX实测驱动13脚恰接对板RX；探针脚本注释相反，已证伪 |
| UART1（下视声纳） | TXD=LSIO_UART1_TX（线5，SOC383）／RXD=LSIO_UART1_RX（线4，SOC384） | **8**（BCM14）／**10**（BCM15） | ✅ 三方一致，无争议 |
| I2C5（VEML7700前视 0x10 + MS5837 0x76） | SDA=LSIO_UART3_TX球复用ALT1（线11，SOC390）／SCL=LSIO_UART3_RX球复用ALT1（线10，SOC389） | **3**（BCM2）／**5**（BCM3） | ✅ 官方+出厂+dts+debugfs 四方一致 |
| 1-Wire master1（onewire-0，config记"探头1/37脚"） | lsio_gpio0_**26**（LSIO_SPI3_MISO球，SOC405） | **不在 40-pin 排针上**（官方全表与出厂表均无 SOC405） | ❌ 绑定从排针不可达；"37脚"标注错误（37脚垫=线22/SOC401） |
| 1-Wire master2（onewire-1，config记"探头2/15脚"） | lsio_gpio0_**22**（LSIO_SPI2_MISO球，SOC401） | **37**（BCM26）——非 15脚（15脚垫=线9/SOC388，当前无任何 master 绑定） | ❌ "15脚"标注错误；探头若接 37脚 将枚举在 master2，与 config 映射对调 |

**一句话**：config.yaml 的 UART7/UART1/I2C5 脚号全部正确；真实错误集中在 **1-Wire 的 lsio 线号↔物理脚标注**
（疑把 BCM26/22 与 lsio线26/22 数字巧合混淆）和 **pwm_probe_cdev.py 的 TX/RX 脚号注释**。

## 1. 40-pin 全表

证据等级：**A**＝官方 40pin 引脚表（rdk-doc 图，视觉读取）+ 出厂库 `RDK_X5_PIN`
（本机存档 `C:/Users/Zmm/AppData/Local/Temp/gpio_pin_data.py:196-224`，SFTP 取自板卡
`/usr/local/lib/python3.10/dist-packages/Hobot/GPIO/`）双源逐行一致；
**A+板**＝A 之外另有板卡 dts / gpioinfo / pinmux-pins 一手输出佐证（存档 `rdk_probe*_out.txt`）；
**B**＝仅官方图（电源/GND 行，出厂表无此行）。

| 脚号 | 功能 | BCM | SOC | lsio 球/线 | 默认状态与复用备注 | 证据 |
|---|---|---|---|---|---|---|
| 1 | 3.3V 电源（最大 800mA） | — | — | — | | B |
| 2 | 5V 电源（最大 500mA） | — | — | — | | B |
| 3 | I2C5_SDA | 2 | 390 | 线11（LSIO_UART3_TX 球） | **X5 默认使能**；复用0=UART3_TXD，i2c5grp 用 ALT1 | A+板 |
| 4 | 5V 电源 | — | — | — | | B |
| 5 | I2C5_SCL | 3 | 389 | 线10（LSIO_UART3_RX 球） | **X5 默认使能**；复用0=UART3_RXD | A+板 |
| 6 | GND | — | — | — | | B |
| 7 | I2S1_MCLK | 4 | 420 | DSP 域 | 复用0=DSP_MCLK1 | A |
| 8 | UART1_TXD | 14 | 383 | 线5（LSIO_UART1_TX 球） | **X5 默认使能**，/dev/ttyS1 | A+板 |
| 9 | GND | — | — | — | | B |
| 10 | UART1_RXD | 15 | 384 | 线4（LSIO_UART1_RX 球） | **X5 默认使能**，/dev/ttyS1 | A+板 |
| 11 | GPIO17 / **UART7_TXD** | 17 | 380 | **线1** | 默认 GPIO；uart7 overlay 使能后为串口 TX；与 gpio0_porta 组互斥须同关 | A+板 |
| 12 | I2S1_BCLK | 18 | 421 | DSP 域 | | A |
| 13 | GPIO27 / **UART7_RXD** | 27 | 379 | **线0** | 默认 GPIO；uart7 overlay 使能后为串口 RX | A+板 |
| 14 | GND | — | — | — | | B |
| 15 | GPIO22（复用 UART2_TXD） | 22 | 388 | 线9 | 默认 GPIO；**当前无 w1 master 绑定此垫**（见 §4） | A |
| 16 | GPIO23（复用 UART6_TXD/UART0_RTS） | 23 | 382 | 线3 | | A |
| 17 | 3.3V 电源 | — | — | — | | B |
| 18 | GPIO24（复用 SPI2_MOSI／LSIO_PWM_OUT3＝PWM1 第2路） | 24 | 402 | 线23 | spi2↔pwm1 互斥组 | A |
| 19 | SPI1_MOSI | 10 | 398 | 线19 | | A |
| 20 | GND | — | — | — | | B |
| 21 | SPI1_MISO | 9 | 397 | 线18 | | A |
| 22 | GPIO25（复用 UART2_RXD） | 25 | 387 | 线8 | | A |
| 23 | SPI1_SCLK | 11 | 395 | 线16 | | A |
| 24 | SPI1_CSN1 | 8 | 394 | 线15 | 官方 pwm.md 文字表"OUT3=24脚"系笔误，OUT3 实在 18脚 | A |
| 25 | GND | — | — | — | | B |
| 26 | SPI1_CSN0 | 7 | 396 | 线17（LSIO_SPI1_SSN 球） | 当前被 34010000.spi 占用（pinmux-pins） | A+板 |
| 27 | I2C0_SDA（复用 LSIO_PWM_OUT5＝PWM2 第2路） | 0 | 355 | gpio1_8 | **X5 默认使能 I2C0**（27/28） | A |
| 28 | I2C0_SCL（复用 LSIO_PWM_OUT4＝PWM2 第1路） | 1 | 354 | gpio1_7 | 同上 | A |
| 29 | GPIO5（复用 SPI2_SCLK／LSIO_PWM_OUT0＝PWM0 第1路） | 5 | 399 | 线20 | spi2↔pwm0 互斥组 | A |
| 30 | GND | — | — | — | | B |
| 31 | GPIO6（复用 SPI2_SSN／LSIO_PWM_OUT1＝PWM0 第2路） | 6 | 400 | 线21 | 同上 | A |
| 32 | PWM6（复用 I2C1_SCL／LSIO_PWM_OUT6＝PWM3 第1路） | 12 | 356 | gpio1_9 | **X5 默认使能 PWM3**；本板被 ms5837_i2c1 overlay 占作 I2C1_SCL | A+板 |
| 33 | PWM7（复用 I2C1_SDA／LSIO_PWM_OUT7＝PWM3 第2路） | 13 | 357 | gpio1_10 | 同上 | A+板 |
| 34 | GND | — | — | — | | B |
| 35 | I2S1_LRCK | 19 | 422 | DSP 域 | | A |
| 36 | GPIO16（复用 UART6_RXD/UART0_CTS） | 16 | 381 | 线2 | | A |
| 37 | GPIO26（复用 SPI2_MISO／LSIO_PWM_OUT2＝PWM1 第1路） | 26 | 401 | **线22** | **当前被 onewire-1（master2）占用** | A+板 |
| 38 | I2S1_SDIN | 20 | 423 | DSP 域 | | A |
| 39 | GND | — | — | — | | B |
| 40 | I2S1_SDOUT | 21 | 424 | DSP 域 | | A |

编号规则说明：官方表有独立 BCM 列，与树莓派 BCM 完全一致；`LSIO_GPIO0_x` 下标是 SoC 垫片序号
（bank0 内 **SOC ≈ 379 + 线号**，gpio1 bank 基数 347），与 BCM 是**置换关系而非恒等**。
对 gpiod/cdev 应使用 lsio 线号（gpiochip4 line N），对 sysfs 应使用 SOC 号（379+N）。

## 2. UART7 TX/RX 方向之争——证据链与裁决

**权威结论（高置信）：11脚=TXD（线1/SOC380），13脚=RXD（线0/SOC379）。**

证据链（四环独立）：
1. 官方 40pin 引脚表：BOARD11 行＝BCM17/SOC380/复用0=UART7_TXD；BOARD13 行＝BCM27/SOC379/复用0=UART7_RXD；
2. 出厂库 `gpio_pin_data.py:200-201`：`(380, 11, 17, 'GPIO17', 'UART7_TXD')`、`(379, 13, 27, 'GPIO27', 'UART7_RXD')`（列序 [chip, SOC, BOARD, BCM, CVM名, SOC名]）；
3. 板卡 gpioinfo（存档 `rdk_probe4_out.txt:94-97`）：`gpiochip4 - 32 lines: @34120000.gpio: @379-410`，`line 0: … LSIO_UART7_RX 379`、`line 1: … LSIO_UART7_TX 380` —— 线号↔SOC 号一手闭环；
4. 板卡 dts `pinmux-gpio.dtsi:162/168`：`lsio_gpio0_0=LSIO_UART7_RX`、`lsio_gpio0_1=LSIO_UART7_TX`。

由此证伪的仓库记录（矛盾如实保留，不删除历史）：
- `rdkx5/scripts/pwm_probe_cdev.py` HEAD（e838dd2 引入）注释：`RX_LINE=0 #（11 脚）`、`TX_LINE=1 #（13 脚）` —— 线号用法正确、**脚号标注颠倒**（line0 实为 13脚）。
- e838dd2 提交信息"声纳 TX 需改接 11 脚"：按权威表，声纳 TX 驱动的 13脚 恰是板 RX 输入，**收向已接对**；该改线建议若执行会把声纳 TX 接到板的 TX 输出上。
- 工作区未提交版再改为 `RX_LINE=17 / TX_LINE=27`（把 BCM 号当 cdev 线号）：line17=gpio396（SPI1_CSN0 球=26脚，且被 spi1 占用）、line27=gpio406（非排针脚）——该版探针**接触不到任何声纳**。
- 本会话未做回环/示波终验；"触发期间零边沿"的测量细节无法从提交信息重建，物理终验待实机。

## 3. I2C5 佐证（无争议）

dts `pinmux-func.dtsi:482-487`：i2c5grp = LSIO_UART3_RX BIT_OFFSET20 / LSIO_UART3_TX BIT_OFFSET22（MUX_ALT1）
——I2C5 复用在 UART3 球上；debugfs pinmux-pins（`rdk_probe2_out.txt`）：pin10/11（lsio_uart3_rx/tx）→
`341c0000.i2c group i2c5grp`。出厂表 `gpio_pin_data.py:197-198`（390→3脚SDA、389→5脚SCL）、
官方 i2c 页（"X5 默认使能 I2C5 物理管脚 3 和 5"）、`rdkx5/config.yaml:98-101`（MS5837 bus5 实测）全部一致。

## 4. 1-Wire 线26/线22 vs 37/15脚——证据链与后果

权威映射：**lsio线22（SOC401，BCM26）= 40-pin 37脚**；**lsio线26（SOC405）不在 40-pin 表内**
（官方全表 40 行无 405；出厂 `RDK_X5_PIN` 无 405）；**15脚 = SOC388 = lsio线9（BCM22）**。

一手证据：
- gpioinfo（`rdk_probe4_out.txt:118,122`）：`line 22: … onewire-1 … LSIO_SPI2_MISO 401`、`line 26: … onewire-0 … LSIO_SPI3_MISO 405`；
- pinmux-pins（`rdk_probe2_out.txt:166,170`）：`pin 22 (lsio_spi2_miso): onewire-1 34120000.gpio:401`、`pin 26 (lsio_spi3_miso): onewire-0 …:405`；
- 出厂表 `gpio_pin_data.py:202,211`：`(388, 15, 22, …)`、`(401, 37, 26, 'GPIO26', 'SPI2_MISO')`。

仓库错误记录（成因：出厂表 CVM 名把 37脚 叫 'GPIO26'、15脚 叫 'GPIO22'——BCM 名；overlay 作者把
BCM 号误当 lsio 线号写入 `gpios=<&ls_gpio0_porta 26/22 1>`）：
- `rdkx5/deploy/dtoverlay_1_wire.dts:7-8,27,41` 注释与绑定；
- `rdkx5/config.yaml:107,112`（"37脚 GPIO26"/"15脚 GPIO22"）；
- `rdkx5/deploy/setup_1wire.sh:25-26` 回显提示；
- `rdkx5/scripts/board_super_query.py:61-62`（"总线1（37脚）…405"/"总线2（15脚）…401"——sysfs 号对、脚号标注错）；
- `CONTEXT_BASELINE.md:31`（未提交）——"芯片级验证生效"仅证明 overlay 绑定生效（hb_gpioinfo 可见），不证明物理脚对应。

**后果**（若探头确实接 37/15脚，按 config.yaml 意图）：
- 探头@37脚 → 落在 **master2（onewire-1，线22）**，与 config `ds18b20_1→master1` 映射**对调**；
- 探头@15脚 → 垫=线9，**无任何 w1 master**，永远无法枚举（与供电/上拉无关的第二个死因）；
- dts 头注释"线26 读到稳定高电平（探头1+上拉在线）"与 `CONTEXT_BASELINE.md:36`"DS18B20 供电+上拉未完成"
  时间线互相矛盾，且悬空垫可被内部弱上拉读高——不足以推翻三源映射，记录存疑。
- 两 master `slave_count=0`，本会话未做实物枚举终验。

## 5. 矛盾与错误清单（mismatches）

1. `rdkx5/scripts/pwm_probe_cdev.py` HEAD:30-31 注释脚号颠倒（详见 §2）；e838dd2"改接11脚"建议存疑。
2. `pwm_probe_cdev.py` 工作区未提交版:30-31 把 BCM 号当 gpiochip4 线号（line17=26脚球、line27 非排针）——探针失效。
3. `rdkx5/deploy/dtoverlay_1_wire.dts` + `rdkx5/config.yaml:107,112` 的 1-Wire 物理脚标注错误（详见 §4）。
4. `rdkx5/deploy/setup_1wire.sh:25-26` 回显沿用错误映射，误导现场接线。
5. `rdkx5/scripts/board_super_query.py:61-62` 物理脚标注错误（sysfs 号本身正确）。
6. `CONTEXT_BASELINE.md:31`（未提交）1-Wire 映射记录与权威表冲突。
7. MS5837 新旧两说并存：`rdkx5/scripts/watch_sensors.py:206-207` 仍显示 "MS5837 bus1"/"无应答(32脚SCL/33脚SDA)"，
   `rdkx5/deploy/enable_ms5837_i2c1.sh` 仍描述 I2C1 方案（板卡 340c0000.i2c/i2c1grp 仍占 32/33 垫）；
   而 `config.yaml:96-102` 已实测迁移 I2C5/bus5（4907fb8）。**修复时不得回退 bus5 真实绑定**，只清文案或经实机确认后停用旧 overlay。
8. `control/config/hardware.yaml:49-62` 与 `control/docs/*`（1cc31e5 初版）仍描述"11/13=1-Wire DATA"旧方案，未同步。
9. `config.yaml:117` 的"UART7=11/13脚"**不是错误**（与权威表一致）；但其"板 TXD=11/RXD=13"与探针脚本注释相反，
   需在脚本侧修正而非配置侧。"TTL 电平"表述模糊：官方硬件页明确 40PIN IO=3.3V，`l08_probe.py:5` 转述 DYP 规格
   V1.2 为"TTL5V"——电平匹配风险仓库内零讨论，未定论，接入前必须实测确认。
10. 外部资料引用须知：官方 pwm.md 文字表"OUT3=24脚"为笔误（引脚图在 18脚）；论坛帖 35426 的脚号（UART7=23/24 等）
    照搬树莓派布局不可采信（仅其 srpi-config 使能方法可采信）；出厂 `EVB_X5_PIN` 是另一载板布局，勿混用。

## 6. config.yaml 修正建议（供修复智能体执行）

- **:107** 现文 `# 独立总线1：40-pin 37脚 GPIO26（…），只挂探头1` →
  改 `# 独立总线1：overlay 绑 lsio 线26（SOC405）——SOC405 不在 40-pin 排针上（官方全表+出厂 RDK_X5_PIN 均无）；
  37脚垫=线22/SOC401。物理接法需实物核对后重绑 overlay，见 docs/PINMAP.md §4`
- **:112** 现文 `# 独立总线2：40-pin 15脚 GPIO22（…；11/13脚是 UART7 勿用），只挂探头2` →
  改 `# 独立总线2：overlay 绑 lsio 线22（SOC401）=40-pin 37脚（BCM26），非 15脚（15脚垫=线9/SOC388，当前无 master）；
  11/13脚是 UART7 勿用`
- **:117** 脚号部分保留（正确）；建议把 `TTL 电平` 改 `3.3V TTL（官方硬件页：40PIN IO 3.3V；DYP 规格书转述 5V，接入前实测确认）`。
- 同步修正：`pwm_probe_cdev.py:30-31` 恢复线号 0/1 并把注释改为 `RX=line0=13脚、TX=line1=11脚`（或弃用探针改走 /dev/ttyS7 受控型）；
  `dtoverlay_1_wire.dts` 头注释与 `setup_1wire.sh:25-26` 回显按 §4 改；重绑方案（探头在 37/15 时应绑 **线22+线9**）
  待实物核对探头实际接脚并枚举成功后执行，并同步调整 `ds18b20_1/2` 的 `sysfs_root` 与 master 对应关系；
  `watch_sensors.py:206-207`、`enable_ms5837_i2c1.sh`、`control/` 三份初版文档按 §5.7/5.8 清理。

## 7. 来源与未验证声明

**来源**：官方 `D-Robotics/rdk_x_doc`（40pin_define/uart/i2c/pwm + 引脚图 PNG 视觉读取，URL 见官方考古材料）；
出厂库 `gpio_pin_data.py`（本机 `C:/Users/Zmm/AppData/Local/Temp/gpio_pin_data.py`，SFTP 自板卡）；
板卡一手输出存档 `C:/Users/Zmm/AppData/Local/Temp/rdk_probe*_out.txt`（gpioinfo/pinmux-pins/dts）；
仓库 `rdkx5/config.yaml`、`rdkx5/scripts/*`、`rdkx5/deploy/*`、`CONTEXT_BASELINE.md`、git 4907fb8/0777058/e838dd2/150eea0。

**本会话未做**（如实声明）：未 SSH 上板复核（仅读本机存档与已下载出厂文件）；未做 UART7 回环/示波终验；
未做 DS18B20 实物枚举终验（两 master slave_count=0，供电/上拉未完成）；DYP-L08 手册原文不在仓库，
"TTL5V"仅为代码注释转述。
