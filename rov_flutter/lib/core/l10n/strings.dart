/// 集中文案常量（契约§6：页面文案逐步集中到此类）
///
/// 本轮（Wave 1）只收录基建层的通用文案（连接状态、信号丢失、共享
/// 组件、登录入口等），各页面私有文案由 Wave 2/3 迁移时逐步纳入。
/// 统一使用中文短句，避免页面内散落魔法字符串。
class AppStrings {
  AppStrings._();

  // ============ 应用 ============
  /// 应用产品名（窗口/桌面显示）
  static const String appTitle = 'SeaUI';

  /// 应用全称
  static const String appFullName = '海参检测机器人管理系统';

  // ============ 登录 ============
  /// 登录按钮
  static const String login = '登录';

  /// 登出
  static const String logout = '退出登录';

  /// 用户名占位
  static const String usernameHint = '请输入用户名';

  /// 密码占位
  static const String passwordHint = '请输入密码';

  // ============ 连接状态 ============
  /// 未连接（初始态）
  static const String connectionOffline = '未连接';

  /// 连接中
  static const String connectionConnecting = '正在连接...';

  /// 已连接（注意：未鉴权时后端不推流，属预期）
  static const String connectionConnected = '已连接';

  /// 重连中
  static const String connectionReconnecting = '正在重连...';

  /// 已断开（手动）
  static const String connectionDisconnected = '已断开';

  /// 未鉴权提示（登录前无视频/遥测属预期行为）
  static const String notAuthenticatedHint = '尚未登录，登录后开始接收数据';

  // ============ 数据健康（StaleBadge） ============
  /// 信号丢失（遥测断链超时提示）
  static const String staleSignal = '⚠ 信号丢失';

  /// 无数据（从未收到）
  static const String noData = '--';

  // ============ 危险操作（ConfirmDialog 默认文案） ============
  /// 确认
  static const String confirm = '确认';

  /// 取消
  static const String cancel = '取消';

  /// 紧急停止
  static const String emergencyStop = '紧急停止';

  /// 紧急停止确认正文
  static const String emergencyStopMessage = '确认立即停止全部推进器？此操作将中断当前作业。';

  // ============ 仿真角标（契约§8） ============
  /// 仿真数据角标（backend_mode == 'sim' 时全页显示，黄色）
  static const String simulatedDataBadge = '仿真数据';
}
