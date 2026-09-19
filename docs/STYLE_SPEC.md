# SeaUI 旧版界面视觉规范（STYLE_SPEC）

> **考古对象**：提交 `1cc31e5`（Initial commit: SeaUI sea cucumber inspection & suction harvest robot control system）中的 `rov_flutter/`。
> **提取方法**：全部结论来自 `git show 1cc31e5:<path>` 逐文件读取，未运行任何猜测。
> **用途**：新版界面 100% 还原旧版视觉与艺术加工。本文档只描述"长什么样、怎么动"；凡涉及数据来源，一律以 §11 铁律对照表为准——**样式照抄，数据接真**。

---

## 1. 总体设计语言

- **基调**：浅色为主（`scaffoldBackgroundColor = #F8FAFC`），白色卡片 + 1px 浅灰描边 + 极轻投影，Material 3（`useMaterial3: true`）。即用户所称 "GitHub light" 观感。
- **主题双套**：浅色 / 深色（`AppTheme.lightTheme / darkTheme`，`rov_flutter/lib/core/theme/app_theme.dart`），默认浅色；深色仅换中性色与描边，主色不变。
- **中文宋体 + 英文衬线/无衬线混排**是本 UI 的签名特征：标题正文用 Noto Serif SC，数据数字用 Inter，英文副标题用 PT Serif（见 §3）。
- **中英双语标签**是贯穿全部页面的艺术加工：主按钮、标签、登录标题均为 `中文 + (ENGLISH)` 组合，英文部分用 `englishSubtitle` 样式（PT Serif、字距 2）。

---

## 2. 完整色板

### 2.1 主题色板（`rov_flutter/lib/core/theme/app_colors.dart`，均带用途注释）

| 名称 | Hex | 用途 |
|---|---|---|
| `primary` | `#3B82F6` | 主色蓝：按钮、激活态、Logo、链接、导航激活、图表 PH/深度 |
| `primaryDark` | `#2563EB` | 主色深变体（声明备用） |
| `primaryLight` | `#60A5FA` | 主色浅变体；移动端水温卡渐变第二色 |
| `gradientStart` | `#87CEEB` | 页眉渐变起点（天蓝）；移动端水温卡渐变第一色；AI 面板渐变第一色 |
| `gradientEnd` | `#9370DB` | 页眉渐变终点（紫）；ColorScheme.secondary；管理端"云端存储"图标色；气压图表色；AI 面板渐变第二色 |
| `success` | `#10B981` | 成功/在线/正常状态；YOLO 检测框颜色；距离测量横幅；光照柱图 `#22C55E` 见 §2.3 |
| `successLight` | `#D1FAE5` | 成功浅底（声明备用） |
| `warning` | `#F59E0B` | 警告；测量模式横幅与测量点画笔；能耗芯片图标 |
| `warningLight` | `#FEF3C7` | 警告浅底（声明备用） |
| `danger` | `#EF4444` | 错误/急停/通知红点/断开按钮 |
| `dangerLight` | `#FEE2E2` | 错误浅底（声明备用） |
| `emergency` | `#FF0000` | 紧急停止专用红（声明备用，实际急停按钮用 `danger`） |
| `backgroundLight` | `#F8FAFC` | 浅色页面底色 |
| `backgroundLightAlt` | `#F3F4F6` | 浅色输入框填充底 |
| `backgroundDark` | `#0F172A` | 深色页面底色；登录图占位底 |
| `backgroundDarkAlt` | `#111827` | 深色输入框填充底 |
| `surfaceLight` | `#FFFFFF` | 浅色卡片/页眉/底栏表面 |
| `surfaceDark` | `#1E293B` | 深色卡片表面 |
| `borderLight` | `#E2E8F0` | 浅色描边（卡片、开关未选轨道、分隔线） |
| `borderDark` | `#334155` | 深色描边 |
| `textPrimaryLight` | `#1F2937` | 浅色主文字 |
| `textSecondaryLight` | `#6B7280` | 浅色次级文字 |
| `textTertiaryLight` | `#9CA3AF` | 浅色提示/禁用文字（textHint） |
| `textPrimaryDark` | `#F3F4F6` | 深色主文字 |
| `textSecondaryDark` | `#9CA3AF` | 深色次级文字 |
| `textTertiaryDark` | `#6B7280` | 深色提示文字 |
| `chartBlue` | `#3B82F6` | PH 图表（与主色同值） |
| `chartRed` | `#F87171` | 温度图表（声明备用，实际水温图用 `#F97316`，见 §2.3） |
| `chartPurple` | `#A855F7` | 盐度图表（声明备用） |
| `chartGreen` | `#10B981` | 气压图表（声明备用，实际气压图用 `#9370DB`） |
| `shadowLight` | `#E8E8E8` | 浅色卡片阴影色（声明备用，实际阴影用黑色低透明度） |
| `shadowDark` | `#40000000` | 深色阴影 |
| `glassWhite` | `#F2FFFFFF` | 毛玻璃卡白（≈95% 不透明白），登录/忘记密码卡底 |
| `glassDark` | `#80000000` | 毛玻璃深色变体（声明备用） |
| `overlay` | `#33000000` | 遮罩 |
| `overlayDark` | `#99000000` | 深遮罩 |
| 便捷别名 | — | `textPrimary/textSecondary/textHint/border/error` 默认指向浅色系 |

### 2.2 语义别名

`error = danger`；`ColorScheme.light/dark` 中 `primary=#3B82F6`、`secondary=#9370DB`、`surface=白/#1E293B`、`error=#EF4444`。

### 2.3 页面内临时色（写在 dart 代码里的硬编码色，还原时必须原样保留）

| Hex | 出处 | 用途 |
|---|---|---|
| `#F1F5F9` | operate/admin/data_analysis/settings 多处 | 芯片/徽章底、分段控件选中底、滑块值chip、模块标签底、路径展示底 |
| `#F8FAFC` | admin 表头/hover、settings 字体预览卡、账户卡底、按钮 hover 色 | 比页面底色同名的另一种"更白的浅底" |
| `#F8FAFC`（表格行 hover）/`#F1F5F9` | 均为悬停/强调的"灰一档" | 悬停反馈 |
| `#6366F1` | admin 全量自检按钮+快捷"分析"、data_analysis AI 图标/生成报告按钮 | 靛蓝强调（AI/诊断专属色） |
| `#F97316` | data_analysis 水温折线与图标 | 橙色（水温） |
| `#22C55E` | data_analysis 盐度图标/光照柱图 | 绿色（盐度/光照） |
| `#9370DB` | admin 云存储图标、data_analysis 气压折线 | 紫（同 gradientEnd） |
| `#87CEEB`、`#60A5FA` | 移动端主控"环境水温"卡渐变 | 天蓝→主蓝横向渐变 |
| `#1E3A5F`、`#0F2027` | 移动端主控视频占位渐变 | 深海军蓝→近黑（深海感） |
| `Colors.greenAccent` | 移动端 YOLO 检测画笔（`MobileDetectionPainter`） | 荧光绿检测框（与桌面 `success` 不同！） |
| `#F87171` | operate 状态卡"实时读取中"小圆点 | 浅红点（非 danger） |
| `Colors.red` | 桌面主控录制徽章圆点 | 纯红录制点 |
| `Colors.black87/54/40/50`、`Colors.white30/54/70/80` 系列 | 视频叠加层各处 | 视频上叠层统一用黑/白透明度体系，见 §8.1 |

---

## 3. 字体体系（google_fonts）

依赖：`google_fonts: ^6.2.1`（`rov_flutter/pubspec.yaml`）。

### 3.1 三个字体家族的分工（`rov_flutter/lib/core/theme/app_text_styles.dart`）

| 家族 | 封装 | 用途 |
|---|---|---|
| **Noto Serif SC** | `_chineseBase()` → `GoogleFonts.notoSerifSc(...)` | 全部中文：标题 h1/h2/h3、副标题、正文、标签、按钮文字、导航项 |
| **PT Serif** | `_englishSerif()` → `GoogleFonts.ptSerif(...)` | 英文副标题 `englishSubtitle`（14/w500/字距2/次级色），用于双语标题的英文半边 |
| **Inter** | `_englishSans()` → `GoogleFonts.inter(...)` | 全部数字/数据：`dataLarge/Medium/Small/Unit`、`timestamp`、`coordinate` |

主题层：`GoogleFonts.notoSerifScTextTheme()` 覆盖整个 `textTheme`（深色主题用 `GoogleFonts.notoSerifScTextTheme(ThemeData.dark().textTheme)`）。

### 3.2 完整文本样式表（名称/字号/字重/其他）

**标题（中文宋体）**
- `h1`：30 / bold / letterSpacing 2（登录页用时覆写 letterSpacing 4）
- `h2`：24 / bold（页面主标题，如"实时监控中心"）
- `h3`：18 / bold（卡片标题、状态卡数值、页眉站名）
- `subtitle`：16 / w500（面板标题，如"快捷操作""实时检测日志"）

**正文（中文宋体）**
- `bodyLarge`：16 / height 1.6
- `bodyMedium`：14 / height 1.5
- `bodySmall`：12 / height 1.5

**辅助（中文宋体）**
- `label`：12 / w500 / 次级色
- `caption`：10 / 三级色（徽章、提示、键帽、单位说明的通用小字）
- `button`：16 / bold

**数据（Inter）**
- `dataLarge`：36 / bold（统计大数字；桌面主控时间覆写为 32）
- `dataMedium`：24 / bold（水温数值）
- `dataSmall`：20 / bold
- `dataUnit`：14 / normal / 三级色（单位 °C、m）
- `timestamp`：12 / 三级色（时间戳、版本号）
- `coordinate`：18 / bold / letterSpacing 2（桌面坐标 "N 38°55' / E 121°38'"）

**导航（中文宋体）**
- `navItem`：14 / w500；`navItemActive`：同上 + 主色

### 3.3 全局字号缩放（`rov_flutter/lib/app.dart`）

- 设置页"全局字体大小"`fontSize`（默认 14，范围 10–20）→ `textTheme` 全部条目乘 `scale = fontSize / 14.0`。
- "UI缩放比例"`uiScale`（0.75–1.5，默认 1.0）→ `MaterialApp.builder` 里 `MediaQuery(textScaler: TextScaler.linear(uiScale))`。

---

## 4. 玻璃拟态参数（登录 / 忘记密码卡）

来源：`rov_flutter/lib/features/auth/login_screen.dart`、`forgot_password_screen.dart`（两页结构完全同构）。

**卡片（毛玻璃）**
- 外层：`SizedBox(width: (screenWidth-48).clamp(280.0, 480.0))` + `ClipRRect(borderRadius: 24)` + `BackdropFilter(blur sigmaX/Y = 10, 10)`。
- 容器装饰：
  - 背景 `AppColors.glassWhite`（`#F2FFFFFF`，95% 白）
  - 圆角 24
  - 描边 `Colors.white @ 20%`，宽 1
  - 阴影 `Colors.black @ 10%`，blurRadius 40，spread 0，无偏移
- 内边距：宽 ≥420 时水平 48 / 垂直 48；窄屏（<420）时 24 / 32。
- 内容纵向流：Logo → 24 → 标题（中英双语，中文 `h1` + letterSpacing 4）→ 48 → 表单。

**全屏背景叠层（背景图之上、卡片之下）**
- 遮罩：`backgroundDark @ 20%` 全屏 + `BackdropFilter(blur 2, 2)`（整页轻模糊）。

**Logo 方块（登录页）**
- 64×64，`primary` 实底，圆角 16，图标 `Icons.waves` 白 36
- 光晕：`primary @ 30%`，blurRadius 20，offset (0, 8)。
- 忘记密码页变体：`primary @ 10%` 底（无光晕），图标 `Icons.lock_reset` 主色 36。

**登录卡表单细节**
- 双语标签：`中文 / ENGLISH`（中文 label w600 次级色，斜杠三级色，英文 englishSubtitle 12）。
- 输入框：fill `#F3F4F6`，圆角 12，默认描边 `#E2E8F0`，聚焦描边主色 2px，contentPadding h16 v16，前缀图标 `person_outline / lock_outline / mail_outline` 三级色；密码框带 `visibility` 切换。
- 登录按钮：高 56，全宽，`primary` 底白字，圆角 12，elevation 0，`shadowColor: primary @ 30%`；文案 `登录 (LOGIN)`（中文 `button` 样式 + 英文 englishSubtitle 14 白 90%）；加载中显示 24×24 白色 2px 圆形进度。
- 记住密码：20×20 Checkbox，圆角 4，activeColor 主色；忘记密码为 RichText 文本按钮（主色）。
- 底部版权条：固定 bottom，白 70% caption + 白 40% 分隔 `|` + `v2.1.0`（`timestamp` 样式白 70%）；`copyright` 常量为空串，实际只显示版本。

---

## 5. 登录背景与页眉/页脚处理

### 5.1 登录艺术背景（`rov_flutter/lib/core/constants/app_constants.dart`）

- 水下背景图 `underwaterBgUrl`（googleusercontent aida-public 直链，原始长 URL 原样保留）：
  `https://lh3.googleusercontent.com/aida-public/AB6AXuDXYooQ0DN8BgeYPnsz3EhhZ1IvlebwlxqF6c_LVMvTO3gumcL2ZtdtpNC3JqLWzR9OwlLzQaMsi__uHi3Rm6kWAVmzuQAJLO7g5UBjFiMuD8ifGtWkf26JDnX5-4iC79gOssNumvDM7F987LRWnA5Fw7C0b4FCjWMLVj3C41ECXpONRSs_0JODsHlq25_WtTEz6L5DihYD6-obuhxsK8kquVWmAiK6IYgTUNpMVoZKCSYpbd2sFaeOZxZ6BrVAlcvIId5-nh57_5wF`
- 渲染方式：`CachedNetworkImage(fit: BoxFit.cover)` 全屏；
  - 占位：纯 `backgroundDark` 色块；
  - **加载失败兜底**：主色 80% → 紫色 80% 的左上→右下线性渐变（相当于把页眉渐变放大成整页，这是设计里明确的降级艺术处理）。
- 另有 `defaultAvatarUrl`（同域 aida-public 头像直链，在常量中声明备用）。

### 5.2 桌面页眉 `AppHeader`（`rov_flutter/lib/features/shared/app_header.dart`）

- 高 64（`AppConstants.headerHeight`），白底，底部 1px `borderLight` 描边，水平 padding 24。
- 左侧 Logo：36×36 圆（radius 18）主色底 + `Icons.waves` 白 20；间距 12；站名 `appName`（"海参检测机器人管理系统"）`h3` 主色 bold。
- 中部导航（Expanded 居中均布）5 项：管理员 `person_search`、操作 `tune`、主控 `dashboard`、数据分析 `bar_chart`、设置 `settings`。
  - 单项：InkWell 圆角 8，内边距 h16 v8；**激活指示 = 底边 2px 主色下划线**（非背景色）；
  - 图标 20，激活主色/未激活次级色；文字 `navItem/navItemActive`。
- 右侧工具栏：通知 `IconButton`（`notifications_outlined` 次级色）+ 右上 8×8 `danger` 红点（Positioned right8 top8）→ 间距 16 → 1×32 竖分隔线（borderLight）→ 间距 16 → 用户区。
- 用户区：右侧对齐双行（姓名 bodyMedium bold / 角色 caption 次级色，空时显示"未登录/访客"）→ 间距 12 → 40×40 主色圆头像（首字符白 18 bold，空显示 `?`）；点击弹 `showMenu`（用户信息条目 + 分隔线 + 红色"退出登录"，登出后回 `/`）。菜单位置 `RelativeRect.fromLTRB(屏宽-200, 64, 0, 0)`。

### 5.3 桌面底部状态栏（`rov_flutter/lib/app.dart` `_buildDesktopFooter`）

- 高约 40（padding h24 v12），白/`surfaceDark` 底，顶部 1px 描边；左侧空文本占位，右侧 8×8 `success` 圆点 + "系统运行正常 (v2.1.0)"（12/三级色）。

### 5.4 移动端页眉与底栏（`rov_flutter/lib/features/shared/bottom_nav_bar.dart`、`app.dart`）

- 渐变页眉 `MobileGradientHeader`：高 100（主控页用 SliverAppBar `expandedHeight: 120` pinned + 同款渐变），`headerGradient`（`#87CEEB → #9370DB`，topLeft→bottomRight），顶部安全区 +16，左右 20，标题白 22 bold；可带 trailing。
- 搜索页眉 `MobileSearchHeader`：同渐变，下方 44 高搜索条：白 20% 底、圆角 22（胶囊）、白色放大镜 20 + hint 白 60%；右端"今日"白底胶囊（圆角 22，日历图标 14 + 12 号主文字色）。
- 底部导航：白/`surfaceDark` 底，上投影 `black 5% blur10 offset(0,-2)`，SafeArea + padding v8；4 项（概览 `dashboard`、控制 `sports_esports`、数据 `bar_chart`、设置 `settings`），每项宽 72，图标 24 + 间距 4 + 标签 12；激活：实心图标 + 主色 + w500；未激活：outline 图标 + textHint。移动端索引映射：桌面 0/1/2/3/4 → 移动 0/1/1/2/3（概览/控制/数据/设置）。

---

## 6. 卡片阴影与间距体系（`rov_flutter/lib/core/constants/app_constants.dart` + 各页实测）

### 6.1 间距刻度

- `spacingXs/Sm/Md/Lg/Xl = 4/8/16/24/32`
- 页面内边距：桌面统一 `EdgeInsets.all(24)`（数据分析页用 32）；卡片内边距 `cardPadding = 20`（状态卡常用 24，方向控制卡 32/48）。
- 卡片间距：网格横向 16（admin/data_analysis）或 24（主控/operate 状态卡间 24）；右栏纵向 16。

### 6.2 圆角刻度

`radiusSm/Md/Lg/Xl/Round/Circle = 4/8/12/16/24/999`；实际使用的还有 20（胶囊芯片）、30（急停大按钮）、22（移动搜索胶囊）、6（小描边按钮）、18（页眉圆 Logo/移动相机切换胶囊）。

### 6.3 阴影体系（全部 BoxShadow，还原必须逐条对齐）

| 场景 | 颜色 | blur | offset | spread |
|---|---|---|---|---|
| 标准卡片（operate/admin/data_analysis/设置内容卡） | black 2% | 8 | (0,2) | 0 |
| 主控视频区 | black 20% | 20 | (0,10) | 0 |
| 小描边按钮（历史周报、时间选择器） | black 2% | 4 | (0,1) | 0 |
| 移动底栏/页眉阴影 | black 5% | 10 | (0,-2) | 0 |
| 登录毛玻璃卡 | black 10% | 40 | 0 | 0 |
| 登录 Logo 光晕 | primary 30% | 20 | (0,8) | 0 |
| 主控方向盘中键 | primary 30% | 16 | 0 | **2** |
| operate HOVER 中心钮 | primary 40% | 16 | (0,4) | 0 |
| 方向键按下态 | primary 40% | 12 | (0,4) | 0 |
| 方向键静息态 | black 5% | 4 | (0,2) | 0 |
| 移动端前进键/中心钮 | primary 30%/40% | 8/16 | (0,4)/0 | 0 |
| 急停大按钮（operate） | error 30%（shadowColor） | elevation 8 | — | — |

**注意**：主题 `cardTheme.elevation = 0`——卡片立体感全部来自上述自绘阴影 + 1px 描边，绝不用 Material 默认投影。

### 6.4 布局度量

- 桌面骨架（app.dart）：页眉 64 → 内容 Expanded → 底部状态栏；页面内容 `SingleChildScrollView(padding 24)`。
- 主控桌面：左 `flex 7`（视频 16:9 → 24 → 控制条 → 24 → 方向盘）/ 右 `flex 3`（状态卡×2 → 16 → 水温卡 → 16 → 快捷操作 → 16 → 400 高日志面板）。
- operate：状态卡三等分 Row（间距 24）→ 主区左 `flex 4`（辅助系统卡 + 24 + 智能纠偏卡）/ 右 `flex 8`（方向控制卡，内 500×400 布局，左右距 24）→ 48 → 居中急停。
- admin：4 等分统计卡（间距 16）→ 主区左 `flex 2` 日志表 / 右 `flex 1`（用户与角色 + 24 + 系统配置 + 24 + 快捷入口）。
- data_analysis：4 等分指标卡（16）→ 2×2 图表卡（24，卡高 280）→ AI 面板。
- 设置：左侧栏 256（= `sidebarWidth`）+ 右内容区白底。
- 断点（`responsive.dart`）：mobile ≤767、tablet 768–1023、desktop ≥1024、宽屏 ≥1440；`maxContentWidth 1600`、`bottomNavHeight 64`、`cardMinWidth 280`、`inputHeight 48`、`buttonHeightSm/Md/Lg = 32/44/56`。

---

## 7. 控件规范：按钮 / 开关 / 方向键盘 / 输入 / 徽章

### 7.1 按钮

- **主题级 ElevatedButton**：`primary` 底白字，elevation 0，圆角 12，padding h24 v16，文字 16 bold（app_theme.dart）。
- **自绘主按钮**（admin/settings/data_analysis 的"添加机器人/导出 CSV/应用更改"）：`Material(color: primary)` + InkWell，圆角 8，padding h16 v10（主）或 h24 v12，白字 14。
- **描边按钮**：白底 + `Border.all(borderLight)` 圆角 8（常规）/6（表格分页、筛选导出小钮），字 14/12 主或次级色；hover 色 `#F8FAFC`。
- **危险按钮**：透明底 + error 描边 + error 字（圆角 8）。
- **AI/诊断按钮**：`#6366F1` 底白字圆角 8（"运行全量自检" padding v14、"生成完整报告" h20 v12）。
- **按压反馈**：全部走 InkWell 水波纹（borderRadius 与容器一致）；无缩放/无颜色动画。
- **紧急停止**三种形态：
  1. 主控右栏：`danger` 底 ElevatedButton 圆角 8，`stop_circle` 白图标 + 双行"紧急停止"/"STOP"（白 80% caption），直接发 `emergencyStop()`。
  2. operate 页：居中大胶囊（radius 30），error 底 elevation 8、`shadowColor: error 30%`，内边距 h80 v16，"紧急停止 (STOP)" 20 bold 白；点击弹红色确认对话框（警告图标 + "确认停止"红色按钮），确认后才发停止命令。
  3. 移动端：全宽胶囊，error 10% 底 + error 30% 描边（radius 30），左侧 24×24 红圆内白色 `close` 图标 16 + "急停" 20 bold error；直发 `emergencyStop()`。

### 7.2 开关（Switch）

- 主题级：选中轨道 `primary`，未选轨道 `borderLight`（深色 `borderDark`），滑块恒白（app_theme.dart switchTheme）。
- 页面级覆写：`activeColor: AppColors.primary`（主控控制条、设置页、移动端 `materialTapTargetSize: shrinkWrap`）。
- 桌面控制条形态：`文本(bodyMedium 次级色) + 12 + Switch`，四组之间用 1×32 `borderLight` 竖线分隔，整条卡 padding h24 v16。
- 设置页行形态：左"标题 14 w500 + 副标题 12 textHint"，右 Switch，行距 16。
- 移动端卡片形态：白卡圆角 12 内"标题 13 + Switch"，下方图标 28（亮主色/灭 textHint）。
- **铁律提醒**：旧控制条含"声呐雷达/激光测距/自动巡航"开关、移动端含"声呐雷达"开关——这些是已废弃的空壳入口，**样式规范仅适用于保留的真实受控项（如照明）**，空壳不得复活（见 §11）。

### 7.3 方向键盘（核心交互件，两套实现）

**A. 主控桌面版**（main_control_desktop.dart）
- 容器 256×256；圆形底：`Border.all(borderLight, width 2)` + `primary @ 5%` 填充。
- 四向键：上/下 48×64、左/右 64×48，圆角 8，白底 borderLight 描边，内含图标（`keyboard_arrow_*`，主色）+ 标签 caption 10；外侧另有独立"上浮 `expand_less`/下潜 `expand_more`"48×48 方钮（同描边样式），与方向盘间距 48。
- 中心钮：64×64 主色圆 + `Icons.videogame_asset` 白 28 + 光晕（primary 30% / blur16 / spread2）；点击 = 停止。
- **按压反馈协议**：`onTapDown` 发方向命令（携带 `_thrusterPower`），`onTapUp` 与 `onTapCancel` 一律 `_backendService.stop()`（按住走、松手停；无视觉状态变化，反馈靠水波纹）。
- 键盘等价物：`KeyboardListener` W/A/S/D 同命令、Space 抓取、松开即停；画面底部有键帽提示（见 §8.1）。

**B. operate 页版**（operate_desktop.dart，**带按压亮起视觉**）
- 圆形方向钮 `_PressableButton`：64×64，静息白底 + 1.5px borderLight 描边 + 阴影(black 5%/blur4/(0,2))；**按下瞬间**：底变 `primary`、描边 `primary`、图标变白、阴影换主色光晕(primary 40%/blur12/(0,4))；`onTapDown` 置亮、`onTapUp` 恢复并执行、`onTapCancel` 恢复。图标 `arrow_upward/back/forward/downward` 28。
- 方形上浮/下潜 `_PressableSquareButton`：56×56 圆角 12，其余同上（图标 `expand_less/more` 28）。
- 每钮下方标签 12 textHint。
- 中心 `HOVER` 控制器：外圈 96 圆 `RadialGradient(primary 10% → transparent)` + 半透明描边(border 50%)；内圆 48 `primary` + 光晕(primary 40%/blur16/(0,4))；圆心 12 白 40% 点；下方徽标 `HOVER`（10 bold 主色，底 primary 10% 圆角 4）。
- 布局：`SizedBox(500×400)` 内 Stack 定位四向 + Center 中心 + 右列 80 宽放上浮/下潜（间距 40）。

**C. 移动端版**（main_control_mobile.dart）
- 前进键 48 圆：`isPrimary: true` → 主色实底白图标 + 光晕(primary 30%/blur8/(0,4))；其余方向 48 白圆描边、图标 `textPrimary`；上浮/下潜/左倾/右倾为 40×40 圆角 12 白底小方钮（图标 20 次级色，标签 9）。
- 中心 56 主色圆 + `Icons.gamepad` 白 24 + 光晕(primary 40%/blur16)，点击停止。
- 同样执行 `onTapDown 发令 / onTapUp·onTapCancel 停止` 协议。

### 7.4 滑块（Slider）

- operate 补光：`SliderTheme(trackHeight 6, activeTrack primary, inactiveTrack primary 20%, thumb primary, overlay primary 10%, RoundSliderThumbShape(radius 8))`；`onChangeEnd` 时弹浮动 SnackBar 反馈。
- 设置页滑块：`activeColor: primary`；标题行右端值chip（`#F1F5F9` 底圆角 4，12/4 padding，14 bold）。

### 7.5 自绘复选/单选（admin 系统配置、设置页单选组）

- 复选：20×20，圆角 4，选中 `primary` 底 + 白 `Icons.check` 14，未选透明底 1.5px borderLight 描边；右侧标题 14 bold（选中主文字色/未选 textHint）+ 副标题 12。
- 单选：同尺寸 `BoxShape.circle`（radius 10），选中主色底白勾。
- 语言卡：12 圆角卡，选中 primary 10% 底 + 2px 主色描边 + `check_circle` 20；国旗 emoji 24 + 名称 14 bold + 副标题 11。
- 主题三卡：等分 Expanded，选中 primary 10% 底、描边 2px 主色，图标 32。

### 7.6 徽章 / 状态条 / 芯片

- **圆点状态**：8×8 圆（success/error/danger/红录制点）；通知红点 8×8 `danger`。
- **胶囊芯片**：padding h16 v8，圆角 20，白底描边边框（主控标题栏"信号强度/能耗"）；operate"通信延迟"胶囊 `#F1F5F9` 底圆角 20 无描边；测量/距离横幅 = warning/success 90% 底圆角 20 白 bold 文字，居中悬浮于画面 top16/top60。
- **RDK 状态条**（设置页）：圆角 8 描边芯片，连接时 success 10% 底 + success 描边 + `check_circle` + "已连接 RDK X5 host:port"；断开时 error 10% 底 + error 描边 + `error_outline` + 网线提示文案。
- **日志标签 chip**：primary 10% 底圆角 4，caption 10 主色文字；系统类条目用 `#F3F4F6` 底次级色。admin 模块列 chip：`#F1F5F9` 底圆角 4。
- **日志状态徽章**（admin 表格）：成功/警告 = 纯彩色 bold 文本 14；错误 = error 底白字 12 圆角 4 小胶囊。
- **统计趋势角标**：卡片右上 12 号图标（`north_east`）+ 粗体百分比，色 success/error。
- **指标趋势 chip**（data_analysis）：10% success/error 底圆角 4，`trending_up/down` 14 + 12 bold。
- **数据条数 chip**（图表卡右上）：`#F1F5F9` 底圆角 4，11 textHint "N 条数据"。

### 7.7 输入框

- 主题级：fill `#F3F4F6`/`#111827`，圆角 12，默认/启用描边 border 色，聚焦主色 2px，contentPadding h16 v14，hint 三级色。
- 表格搜索框（admin）：宽 240，圆角 8，前缀 `search` 20 三级色，contentPadding h12 v8。
- 对话框表单：`OutlineInputBorder()` 默认样式 + labelText。

---

## 8. 每页独特艺术加工点

### 8.1 主控桌面（main_control_desktop.dart）

- **标题栏**：左"实时监控中心"h2 + 副行 bodySmall；右两枚胶囊状态芯片（图标 16 success/warning 着色）。
- **视频区**：16:9 黑底圆角 16 + 大投影；上方叠层依次为：
  1. 视频帧 `Image.memory(fit cover, gaplessPlayback: true)`；
  2. YOLO 检测叠层 `DetectionOverlayPainter`：`success` 2px 描边框 + `success 10%` 填充 + 框上标签 `label conf%`（白 12 bold、success 80% 文字底），标签自动 clamp 不出画；
  3. 测量叠层 `MeasurePointPainter`：warning 实心点 r8 + 同色描边环 r16 + 两点 2px 连线 + "点1/点2"标签（白 12 bold、warning 80% 底，偏移 (+20, −h/2)）；
  4. **暗角渐变**：topCenter→bottomCenter，stops `[0, 0.2, 0.8, 1]`，色 black40% → 透明 → 透明 → black60%（IgnorePointer）；
  5. 左上录制徽章：black 50% 底圆角 8 + 白 20% 1px 描边 + 8×8 红点 + "实时画面 - 01号摄像头" caption 白；
  6. 右上信息：`30 fps | 1920×1080`（timestamp 白）+ `bolt` 12 warning + "延迟: 45ms" caption warning；
  7. top16 left200 连接条：三枚 black 50% 圆角 8 胶囊（视频源选择/双摄切换/连接状态），连接胶囊内 8×8 红绿点 + 状态文字白 + 内嵌"连接/断开"小色块钮（success/error 底圆角 4 白 11 号）；
  8. 底部 24 居中键帽提示：W/A/S/D 键帽（白 40% 1px 描边 + 白 10% 底圆角 4，caption 白 80%，"空格"为宽版 h16 padding）+ "推进器控制"/"抓取采集"说明 + 1×24 白 20% 竖分隔；
  9. 左下 64 坐标卡：black 40% 底圆角 12 + 白 10% 描边，"当前坐标" caption 三级色 + 坐标 `coordinate` 样式白字距 2；
  10. 右下 64 时间：`dataLarge` 32 白 + 日期 timestamp 白 70%。
- **控制条**：白卡圆角 12 描边，四组开关 + 竖分隔（见 §7.2）。
- **方向盘**：见 §7.3A。
- **右栏状态卡**：48×48 圆形图标底（图标色 10% 透明度）+ 16 间距 + caption 标签/h3 值；报警卡 `error_outline` 次级色，运行卡 `check_circle_outline`（文本/颜色由 RDK/Pixhawk/后端三级链路状态决定）。
- **水温特色卡**：`primary 10%` 底 + `primary 30%` 描边圆角 12；48 白圆内 `thermostat` 主色；"环境水温" caption 主色 + `dataMedium` 主色数值 + °C bodyMedium + "深度 x m · 前方 x m" caption 主色。数值全部来自 `sensorData`（`ds18b20_water_1/ms5837_depth/ultrasonic_front_suction_mouth`），缺失显示 `--`。
- **快捷操作**：标题 subtitle + 右侧测量模式 `straighten` 16 图标钮（激活 warning/否则次级色，tooltip 切换）+ `flash_on` 主色；2 列网格 aspect 1.5，按钮白底圆角 8 描边，图标 20 按动作着色（上浮 warning/归零 primary/补光 warning/快照 success），标签 caption 居中；下方全宽红色急停（§7.1）；再下方"推进器动力 65%"行 + `LinearProgressIndicator(value 0.65, 背景 borderLight, 主色, 圆角 4)`。
- **日志面板**：400 高白卡；头部 16 padding + 底描边（`show_chart` 16 主色 + "实时检测日志" subtitle + 右侧"实时流" caption）；列表条目 = 时间戳 + 标签 chip + 标题(bodySmall bold) + 副文 caption，间距 16；底部"查看完整历史记录"主色 bodySmall + 顶描边。
- 无视频占位：black87 底，`videocam_off/link_off` 64 白 30%，状态文案白 54 16 号，服务器地址白 30 12 号，RDK 行（连接 success/未连白 30 12 号），未连接时主色"连接"按钮。

### 8.2 控制操作 operate（operate_desktop.dart）

- 标题行：`bolt` 24 主色 + "实时运行状态" 24 bold；右"通信延迟"胶囊（`#F1F5F9` 底圆角 20，"12ms" bold）。
- 三张状态卡（探测深度/机器温度/漏水检测）：白底圆角 16 描边 + 标准投影；标题 14 次级 + 右上图标 tile（探测深度：primary 10% 底圆角 8 内图标；其余透明底）；数值 36/32 bold（深度值主色，其余主文字色）+ 单位 20 textHint；**底部状态行 = 8×8 `#F87171` 圆点 + "实时读取中 (±0.02)" 12 textHint**（固定装饰性注记）。
- 辅助系统卡：padding 32；"辅助系统" 20 bold + 副文 12 textHint；补光滑块（§7.4）；2×2 切换钮网格 aspect 2.5（`_buildToggleControlButton`：圆角 12，激活时 primary 10% 底 + primary 描边 + 图标文字转主色加粗，未激活透明底 border 描边，hover `#F8FAFC`；图标 18 + 标签 14）。
- 智能纠偏卡：`primary 5%` 底 + `primary 20%` 描边圆角 16，`info` 20 主色 + 标题 14 bold + 正文 12 height1.5。
- 方向控制卡：见 §7.3B（含 HOVER 中心件）。
- 操作反馈：所有切换用 `SnackBarBehavior.floating` 1 秒提示（"机械臂已展开"等）。

### 8.3 管理员面板（admin_panel_desktop.dart）

- 标题行：左"今日核心概览" 24 bold + 副文 14；右"历史周报"描边钮 + "添加机器人"主色钮（均带图标）。
- 四统计卡：白底圆角 12 描边 + 投影，padding 20；40×40 图标 tile（圆角 8，图标色 10% 底：primary/error/success/`#9370DB`）→ 16 → 标题 14 次级 → 数值 30 bold + 单位 14 次级；右上角趋势（`north_east` 12 + 12 bold，success/error）。
- 日志表：白卡圆角 12；头部 20 padding 内标题组（"系统操作日志"18 bold + 副文 12 textHint）+ 右侧搜索框/筛选/导出钮；表头行 `#F8FAFC` 底，12 次级色文字，列 flex 2/1/1/2/1，状态列右对齐；数据行 24/16 padding、底部 0.5px 描边、hover `#F8FAFC`；模块 chip（§7.6）；分页条：'共计 N 条操作记录' + 上一页/下一页描边小钮（圆角 6，禁用时描边 50% 透明）+ "x / y" 12 号。
- 用户与角色卡：标题行（`people_outline` 20 主色 + 16 bold 主色标题）+ 刷新/添加小图标钮（textHint 色，zero padding）；用户行：40 圆头像（primary 10% 底，asset 加载失败回退首字符主色 18 bold）+ 姓名 14 bold + 角色 chip（primary 10% 底圆角 4，10 主色）+ 权限 chip（`#F1F5F9` 底 10 次级色）+ 删除小钮（id≠0 时）；底部全宽描边钮"管理所有权限"+`chevron_right`。
- 系统配置快选卡：自绘复选行（§7.5）；底部 `#6366F1` 全宽自检钮（v14 padding，`auto_fix_high` 18 + 14 白）。
- 快捷入口：两枚白底圆角 12 描边钮（40 图标 tile：primary/`#6366F1` 10% 底 + 标签 14）。
- 对话框家族：添加用户/添加机器人（表单 AlertDialog，主色标题图标）、导出成功（success 图标 + `#F1F5F9` 路径块 monospace 12 + 复制路径/确定）、历史周报（Card+ListTile 列表）、权限管理（600×400，用户 Chip 汇总 primary 5% 底块 + 权限行卡片）、删除用户确认（error 按钮）、全量自检进度圈。

### 8.4 数据分析（data_analysis_desktop.dart）

- 标题行：左"数据分析报表"+ 数据源副文；右**分段选择器**（白底圆角 8 描边 padding 4 容器，内四段 padding h16 v6，选中 `#F1F5F9` 底圆角 6 + w500 主文字色）+ 主色"导出 CSV"钮（`download` 18）。
- 四指标卡：白卡 padding 20，行布局：48×48 图标 tile（圆角 12，图标色 10% 底：primary/`#F97316`/`#22C55E`/`#9370DB`）+ 16 + 标题 12 次级/数值 24 bold + 单位 12 textHint + 右端趋势 chip（§7.6）。
- 2×2 图表卡：高 280，padding 24；标题 16 bold + 右上数据条数 chip；fl_chart 规格全页统一：
  - 网格：仅水平线 `#E5E7EB` 1px；边框无；
  - 轴标签：左侧 10 textHint（深度 1 位小数/光照整数/水温 `x°`/气压 1 位小数），其余轴隐藏；
  - 折线：`isCurved`、2px、`isStrokeCapRound`、无点、线下 10% 同色渐变填充；颜色：深度 `primary`、水温 `#F97316`、气压 `#9370DB`；
  - 柱状（光照）：`#22C55E`、宽 16、顶部圆角 4；
  - Y 轴量程：深度 0–2、光照 0–500、水温 8–18、气压 100–104；
  - 数据窗口：折线取最近 24 条倒序、柱状取 12 条；空数据显示居中"暂无数据"。
- AI 分析面板（页面视觉高潮）：整卡**渐变底 `#87CEEB 10% → #9370DB 10%`（topLeft→bottomRight）+ 描边圆角 16**；头部 12 padding `#6366F1 10%` 底圆角 12 内 `auto_awesome` 24 + "AI 智能分析看板"18 bold + 副文 12 + 右端评分胶囊（success/warning/error 底圆角 20，白 14 bold "综合评分: N分"）；三枚白底圆角 12 分析项（图标+标题 12 textHint + 结论 16 bold 着色：采收适宜度/环境预警/养殖建议）；白底圆角 12 详细报告块（13 号 height1.6 列表）；右下 `#6366F1` "生成完整报告"钮。
- 报告导出：`_generateFullReport` 生成 Markdown 文本走系统保存对话框 + 同款"导出成功"对话框。

### 8.5 设置（settings_desktop.dart）

- 双栏骨架：左 256 侧栏（白底右边框）+ 右白底内容区。
- 侧栏：顶部"配置中心"（12 bold textHint letterSpacing 1.2）；菜单项 padding h24 v16，选中 = `primary 5%` 底 + **右侧 3px 主色竖条**（Border right），图标 20 + 标签 14（选中主色/否则次级色）；底部提示卡（primary 5% 底 primary 20% 描边圆角 12，`info` 18 主色 70% + 12 主色 height1.5 文案"部分设置修改后需要重启…"）。
- 内容页：padding 32；页标题 = 图标 28 + 24 bold；节标题 16 bold；节间 `Divider` 上下各 24。
- RDK 连接块：状态条芯片（§7.6）+ IP/端口两输入框 + "保存并连接"主色 icon 按钮（`cable`）。
- 显示设置：主题三卡（§7.5）；字体滑块 + 字体预览卡（`#F8FAFC` 底圆角 12 描边，三行示例：字号+4 bold / 字号 / 字号−2 次级）；UI 缩放滑块；无障碍双开关。
- 语言与地区：三语言卡（国旗 emoji）+ 日期/时间单选组（§7.5）+ 时区下拉（自绘描边圆角 8 容器包 `DropdownButton`，无下划线）。
- 账户与安全：账户卡（`#F8FAFC` 底圆角 12：64 主色圆角 12 头像首字符白 24 + 姓名 18 bold + 邮箱 14 次级 + 角色 chip + "编辑资料"描边钮）；"上次修改密码"信息行 + 修改密码描边钮；安全选项开关组（自动锁定开启时追加分钟滑块）；登录历史（描边圆角 12 容器内 4 行，行 padding 16 + 底描边：success/warning 图标 20 + 时间 14 + "设备 · IP" 12 textHint + 右端 成功/失败 12 着色）；**危险区**：error 5% 底 + error 30% 描边圆角 12，`warning` 20 + "危险区域" 14 bold error + 说明 + 两枚红描边按钮（登出所有设备/删除账户，后者两级确认、需输入 "DELETE"）。
- 右下角统一 `_buildApplyButton`：'恢复默认值' 描边 + '应用更改' 主色。

### 8.6 移动端主控（main_control_mobile.dart）

- 渐变 SliverAppBar（§5.4）：标题行"海参检测系统"白 20 bold + `notifications_outlined` 白 90% + 16 半径白 24% 圆头像（`person` 白 18）；信息行：白 20% 底圆角 12 信息 chip（"ROV-01"/"全海区"，白 12 号）+ 右端 `⬛ -45dBm ⚡ 120W` 白 80% 12 号单行省略。
- 视频卡：高 200 圆角 16，占位渐变 `#1E3A5F → #0F2027`；左上 LIVE 徽章（success/error 底圆角 4，`fiber_manual_record/link_off` 10 白 + "LIVE/离线" 10 bold）+ CAM-01 黑 54 徽章；右上 `${frameRate} fps` 白 80% 10 号 + success 底圆角 4 `⏱ 45ms` 白 9 号；左下 COORDINATES 8 号白 60% + 两行坐标 14 bold 白；底部中央 DEPTH 8 号 + 大数字 28 + m 10 号；右下时间/日期（实时取 `DateTime.now()`）。有帧时右上悬浮**双摄切换胶囊**（black54 底圆角 18：`videocam` 14 + 当前相机名 11 + "前视/吸口"两枚小胶囊钮，选中 primary 底 bold）。
- 设备开关卡：两枚白卡（§7.2 移动形态）横向等分，间距 12。
- 方向盘卡（§7.3C）+ 白卡圆角 16 padding 20。
- 状态卡组：两张标准卡（error/success 图标 tile 10% 底圆角 8）+ **渐变水温卡**：`#87CEEB → #60A5FA` 横向渐变圆角 12，白 20% 底圆角 8 图标 tile + `thermostat` 白 + "环境水温"白 80% 12 + `22.5°C` 24 bold 白（样式参照；数值须接真实源）。
- 快捷操作：标题行右 `straighten` 20（测量模式激活 warning）+ `bolt` 主色；2 列网格 aspect 1.8，白底圆角 12 描边钮（图标 24 主色 + 标签 12）。
- 急停胶囊（§7.1 第 3 形态）。
- 日志区：标题行（`receipt_long` 18 次级 + "实时检测日志"16 bold + 右"实时流"）+ 条目（时间 12 textHint + 标签 chip primary 10% 圆角 4 10 号 + 标题 14 + 详情 12 textHint），`Divider` 24 分隔。
- `MobileDetectionPainter`：**greenAccent** 2px 框 + 15% 填充 + 框上方 16 高同色 80% 标签条（`label xx%` 10 bold，文字 greenAccent）。
- `MobileMeasurePainter`：warning 实心点 r6 + 描边环 r8 + 2px 连线（无标签文字）。
- 视频源配置 = 底部弹窗（顶部圆角 20），ChoiceChip 选类型 + 表单 + 全宽主色"保存配置"。

### 8.7 登录 / 忘记密码

见 §4/§5.1。补充：忘记密码提交为"模拟网络请求（1 秒延迟）+ success SnackBar"——样式还原，但**假发送行为不得照搬**（见 §11-③）。

---

## 9. 动效现状

- **路由转场**（app.dart `_generateRoute`，受"减少动画"设置控制）：
  - `/`（登录）：`PageRouteBuilder` 纯 FadeTransition，400ms；
  - `/dashboard`：SlideTransition（Offset (0, 0.05) → 0，`Curves.easeOutCubic`）+ Fade，500ms；
  - `reduceMotion = true` → `Duration.zero` / 直接返回 child。
- **页内切页**（DashboardRouter）：`AnimationController` 300ms `Curves.easeInOut`——旧页 fade reverse → setState 换页 → 新页 fade forward，同时内容 SlideTransition 从 (0, 0.02) 浮起；移动端用 `IndexedStack`（无切换动画，仅保状态）。
- **常量**：`animationFast/Normal/Slow = 150/300/500ms`（声明于 AppConstants，主要供语义引用）。
- **微交互**：InkWell 水波纹（全部可点元素）；SnackBar 反馈（全局底色条 + operate 页 floating 1s）；Switch/Slider/进度圈为 Material 默认动效；`CircularProgressIndicator` 用于登录按钮、加载占位（admin 表格 40 padding、数据分析整页 Center、自检对话框）。
- **没有**：Hero、隐式 AnimatedContainer、自定义补间、页面级视差。整体动效克制，仅转场与水波纹。

---

## 10. 文案与资源常量

- 应用名：`海参检测机器人管理系统` / `ROV Management System`；版本 `v2.1.0`；`copyright = ''`（页脚只显示版本）。
- 导航枚举 `NavItem`：admin('管理员','person_search')、operate('控制操作','tune')、main('主控','dashboard')、dataAnalysis('数据分析','bar_chart')、settings('settings','settings')；页眉实际用短标签"操作"，其余一致。
- 依赖（pubspec.yaml）：`google_fonts ^6.2.1`、`fl_chart ^0.69.0`、`cached_network_image ^3.4.1`、`web_socket_channel ^3.0.1`、`http ^1.2.0`、`file_picker`、`path_provider`、`sqflite`。
- assets：`assets/images/`、`assets/data/`、`assets/users/`。

---

## 11. 铁律对照表（还原时的硬约束，违反 = 返工）

### 11-① 真实数据绑定必须原样保留（当前代码已核实存在）

| 绑定 | 当前代码位置（本次核实） |
|---|---|
| `videoFrameNotifier` / `telemetryNotifier` / `connectionNotifier` 三通道契约 | `rov_flutter/lib/core/services/rov_backend_service.dart:19-21`（帧 15~30Hz / 遥测 ≤5Hz 节流 / 连接态仅变化时） |
| `StaleBadge` 断链徽标（≥5s 无数据判据） | `rov_flutter/lib/core/services/rov_backend_service.dart:34,240`；使用处 `rov_flutter/lib/features/dashboard/desktop/admin_panel_desktop.dart:551,676`；文案表 `rov_flutter/lib/core/l10n/strings.dart:48` |
| 未 auth 不推流（后端只回 hello 是预期行为） | `rov_flutter/lib/core/services/rov_backend_service.dart:40-43,342-343,404-413`（`attachAuth` 注入 token 后才有帧/遥测） |
| 登录 `must_change_password` 强制改密流程 | `rov_flutter/lib/features/auth/login_screen.dart`（已核实包含该字符串；还原登录视觉时此流程不得回退） |
| RDK 传感器链路（`ds18b20_water_*`、`ms5837_depth`、`veml7700_*`、`ultrasonic_front_suction_mouth`）与心跳（5s `requestStatus`） | 旧版 main_control/operate 页即按此绑定（`main_control_desktop.dart:970-1026`、`operate_desktop.dart:137-196`），还原时沿用当前服务实现 |

### 11-② 旧版装饰性假数据清单（样式可还原，数值禁止照抄；必须改为真实源或真实状态驱动）

以下内容在旧版代码中是**硬编码/演示值**，逐条列出以便还原时替换：

- 主控桌面标题栏："正在连接: ROV-DEEPSEA-01 · 大连金海区检测点"、"信号强度: 强 (-45dBm)"、"能耗: 120W"（`main_control_desktop.dart:166-184`）。
- 视频右上角固定 "30 fps | 1920×1080"、"延迟: 45ms"；左下固定坐标 "N 38°55' / E 121°38'"；右下固定 "16:36:20 / 2026/02/14"（`main_control_desktop.dart:612-685`）。fps 应接 `frameRate`，坐标/时间须由遥测/系统时钟驱动或按产品决定移除。
- 右栏"报警提醒：无异常"为固定文案；快捷操作"推进器动力 65%"与进度条 0.65 为固定值（`main_control_desktop.dart:923,1148-1157`）。
- 实时日志面板三条演示日志（14:20:12 等，`main_control_desktop.dart:1250-1255`）；移动端同款两条（`main_control_mobile.dart:986-988`）。
- 移动端页眉 "⬛ -45dBm ⚡ 120W"、视频区固定 DEPTH "42.5"、水温卡固定 "22.5°C"（`main_control_mobile.dart:167,362,806`）。
- operate 页：初始 `_depth=5.2/_temperature=35` 兜底值（有真实值时优先真实值，但兜底仍是假数——还原时缺失应显示 `--` 或 StaleBadge）、固定"通信延迟 12ms"、固定"漏水检测 正常"、固定"实时读取中 (±0.02)"注记（`operate_desktop.dart:30-32,113-127,280-297`）。
- admin 页：默认演示日志/演示用户（`admin_panel_desktop.dart:144-160`）、固定统计 128/02/98.5/412（:46-49）、硬编码历史周报（:627-631）、"运行全量自检"为 `Future.delayed(2s)` 模拟并返回硬编码报告（:507-551）。
- data_analysis 页：演示数据 `_getDefaultData()`（:129-142）、固定趋势 "+0.05/+1.2/-0.3/+0.1"（:463-469）。图表数据须来自 `listSensors` 实时历史（:62-126 已有真实路径）。
- settings 页：硬编码登录历史 4 条（:985-990）、固定 `_lastPasswordChange '2026-01-15'`、拼造邮箱 `xxx@rov-system.com`（:919）。
- forgot_password：模拟 1 秒发送 + 恒成功提示（`forgot_password_screen.dart:36-50`）。

### 11-③ 空壳入口不得复活

旧 UI 中以下入口无后端实现（或为演示开关），当前版本已隐藏/删除，还原**只取其视觉样式、不恢复入口本身**：
- 主控桌面控制条"声呐雷达/激光测距/自动巡航"开关（`main_control_desktop.dart:747-760`）；
- 移动端"声呐雷达"开关（`main_control_mobile.dart:589`）；
- operate 页"机械臂展开/关闭主泵/姿态自动调平/全景扫描"切换钮（`operate_desktop.dart:424-439`，仅弹 SnackBar 无实控）；
- admin "筛选"空 onTap 钮（`admin_panel_desktop.dart:810`）、快捷入口"控制台/分析"空 onTap（:1362-1364）、主控"查看完整历史记录"空 onTap（`main_control_desktop.dart:1260`）。
- 对照基线（CONTEXT_BASELINE.md 铁律 4）：无后端实现的功能入口一律隐藏/删除，不做假开关。

### 11-④ 其他

- 登录 must_change_password 强制改密流程（当前 `login_screen.dart`）在还原旧视觉时保持行为不变。
- 风格基调以基线"GitHub light / 默认浅色"为准：旧版本身就是浅色系，还原不引入新的风格漂移；登录页背景图（§5.1）与当前 ca743cf 提交的"浅色登录背景"存在取舍，还原时按用户确认执行（见 risks）。

---

## 12. 快速还原清单（Tick list）

1. 复制 `AppColors`（§2.1 全表）+ §2.3 临时色 → `app_colors.dart`。
2. 复制 `AppTextStyles` 三家族分工与全部样式（§3.2）→ `app_text_styles.dart`；主题 `notoSerifScTextTheme` + §3.3 双缩放。
3. 主题：`useMaterial3`、elevation0 卡片（1px 描边圆角 12）、输入/按钮/开关/复选/底栏主题（§7）。
4. 登录/忘记密码：googleusercontent 背景 + CachedNetworkImage + 2/20 遮罩 blur2 + 毛玻璃卡（blur10 / #F2FFFFFF / 白20% 1px / black10% blur40 / 圆角24 / 280–480 宽 / 48-48 padding）（§4–5）。
5. 桌面骨架：64 页眉（下划线导航）+ 24 padding 内容 + 状态栏页脚（§5.2–5.3）；各页 flex 布局（§6.4）。
6. 逐页复刻 §8 的艺术加工层（渐变、徽章、暗角、键帽、图表规格、AI 渐变面板、设置侧栏等）。
7. 动效：400/500ms 路由转场 + 300ms 换页 fade/slide + reduceMotion 短路（§9）。
8. 数据层：全部按 §11-① 保留现绑定；§11-② 清单逐条替换真实数据；§11-③ 清单逐条不复活。
