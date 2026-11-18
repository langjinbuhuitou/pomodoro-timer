import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PomodoroApp());
}

class PomodoroApp extends StatelessWidget {
  const PomodoroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '番茄钟',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFFFFBF6),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE4572E)),
        useMaterial3: true,
      ),
      home: const PomodoroHome(),
    );
  }
}

// ---------------------------------------------------------------------------
// 数据结构
// ---------------------------------------------------------------------------
enum PomodoroMode { focus, rest }

class SettingsData {
  final int focusMinutes;
  final int breakMinutes;
  final int totalRounds;
  final bool vibrateOn;
  final bool soundOn;
  const SettingsData({
    required this.focusMinutes,
    required this.breakMinutes,
    required this.totalRounds,
    required this.vibrateOn,
    required this.soundOn,
  });
}

class DialogAction {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const DialogAction(this.label, this.onTap, {this.primary = true});
}

// ---------------------------------------------------------------------------
// 首页
// ---------------------------------------------------------------------------
class PomodoroHome extends StatefulWidget {
  const PomodoroHome({super.key});

  @override
  State<PomodoroHome> createState() => _PomodoroHomeState();
}

class _PomodoroHomeState extends State<PomodoroHome>
    with TickerProviderStateMixin {
  // 设置项
  int focusMinutes = 25;
  int breakMinutes = 5;
  int totalRounds = 4;
  bool vibrateOn = true;
  bool soundOn = false;

  // 运行状态
  PomodoroMode mode = PomodoroMode.focus;
  bool running = false;
  int sessionTotalMs = 25 * 60 * 1000;
  int remainingMs = 25 * 60 * 1000;
  int round = 1;

  // 动画控制器
  late final AnimationController _progressCtrl; // 驱动环形进度 (1.0 -> 0.0)
  late final AnimationController _staggerCtrl; // 交织动画
  late final Animation<double> _ringScale;
  late final Animation<double> _textFade;
  late final Animation<double> _chipFade;
  late final Animation<double> _roundsFade;
  late final Animation<double> _actionsSlide;

  @override
  void initState() {
    super.initState();
    sessionTotalMs = focusMinutes * 60 * 1000;
    remainingMs = sessionTotalMs;

    // 进度环：value=1 表示满，reverse 到 0 表示结束
    _progressCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: sessionTotalMs),
      value: 1.0,
    );
    _progressCtrl.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) _onFinish();
    });
    _progressCtrl.addListener(() {
      setState(() {
        remainingMs = (_progressCtrl.value * sessionTotalMs).round();
      });
    });

    // 交织动画（Stagger）：多个 Interval 错开时间
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _ringScale = CurvedAnimation(
      parent: _staggerCtrl,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
    );
    _textFade = CurvedAnimation(
      parent: _staggerCtrl,
      curve: const Interval(0.18, 0.6, curve: Curves.easeOut),
    );
    _chipFade = CurvedAnimation(
      parent: _staggerCtrl,
      curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
    );
    _roundsFade = CurvedAnimation(
      parent: _staggerCtrl,
      curve: const Interval(0.42, 0.8, curve: Curves.easeOut),
    );
    _actionsSlide = CurvedAnimation(
      parent: _staggerCtrl,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
    );

    // 首屏播放一次交织入场动画
    _staggerCtrl.forward();
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _staggerCtrl.dispose();
    super.dispose();
  }

  int get currentTotalMs =>
      (mode == PomodoroMode.focus ? focusMinutes : breakMinutes) * 60 * 1000;

  Color get accent => mode == PomodoroMode.focus
      ? const Color(0xFFE4572E)
      : const Color(0xFF2F8F6B);
  Color get accent2 => mode == PomodoroMode.focus
      ? const Color(0xFFF5894F)
      : const Color(0xFF63B992);

  // ---------------- 计时控制 ----------------
  void start() {
    if (running) return;
    final total = currentTotalMs;
    final isFresh = remainingMs >= total - 50;
    if (remainingMs <= 0) {
      remainingMs = total;
    }
    if (isFresh) sessionTotalMs = total;
    _progressCtrl.duration = Duration(milliseconds: sessionTotalMs);
    setState(() => running = true);
    _progressCtrl.reverse(from: remainingMs / sessionTotalMs);
    if (isFresh) _staggerCtrl.forward(from: 0.0);
  }

  void pause() {
    if (!running) return;
    _progressCtrl.stop();
    setState(() => running = false);
  }

  void reset() {
    pause();
    setState(() {
      round = 1;
      mode = PomodoroMode.focus;
      sessionTotalMs = currentTotalMs;
      remainingMs = sessionTotalMs;
    });
    _progressCtrl.duration = Duration(milliseconds: sessionTotalMs);
    _progressCtrl.value = 1.0;
  }

  void switchMode(PomodoroMode next) {
    if (mode == next) return;
    pause();
    setState(() {
      mode = next;
      sessionTotalMs = currentTotalMs;
      remainingMs = sessionTotalMs;
    });
    _progressCtrl.duration = Duration(milliseconds: sessionTotalMs);
    _progressCtrl.value = 1.0;
  }

  // ---------------- 结束 ----------------
  void _onFinish() {
    setState(() => running = false);
    remainingMs = 0;
    if (vibrateOn) _vibrate();
    _showFinishDialog();
  }

  void _vibrate() {
    HapticFeedback.vibrate();
    Future.delayed(
        const Duration(milliseconds: 200), () => HapticFeedback.heavyImpact());
    Future.delayed(
        const Duration(milliseconds: 420), () => HapticFeedback.vibrate());
  }

  void _startNextFocus() {
    final wasBreak = mode == PomodoroMode.rest;
    if (round < totalRounds) {
      setState(() => round += 1);
    } else if (wasBreak) {
      setState(() => round = totalRounds);
    }
    if (mode != PomodoroMode.focus) switchMode(PomodoroMode.focus);
    start();
  }

  void _showFinishDialog() {
    String title;
    String desc;
    List<DialogAction> actions;

    if (mode == PomodoroMode.focus) {
      if (round >= totalRounds) {
        title = '全部完成';
        desc = '已完成 $totalRounds 轮专注，好好休息一下';
        actions = [
          DialogAction('重新开始', () {
            setState(() => round = 1);
            switchMode(PomodoroMode.focus);
            start();
          }),
          const DialogAction('关闭', _noop, primary: false),
        ];
      } else {
        title = '专注完成';
        desc = '这一轮结束，休息 $breakMinutes 分钟吧';
        actions = [
          DialogAction('开始休息', () {
            switchMode(PomodoroMode.rest);
            start();
          }),
          DialogAction('继续专注', _startNextFocus, primary: false),
        ];
      }
    } else {
      title = '休息完成';
      desc = '准备好就开始下一轮专注';
      actions = [
        DialogAction('开始下一轮', _startNextFocus),
        DialogAction('稍后', () {
          if (mode == PomodoroMode.rest) {
            setState(() => round = (round + 1).clamp(1, totalRounds));
            switchMode(PomodoroMode.focus);
          }
        }, primary: false),
      ];
    }

    // ScaleTransition + FadeTransition 弹窗
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x662C2018),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, a1, a2, child) {
        final curved = CurvedAnimation(parent: a1, curve: Curves.easeOutBack);
        return FadeTransition(
          opacity: a1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
            child: _FinishDialog(
              title: title,
              desc: desc,
              actions: actions,
              accent: accent,
            ),
          ),
        );
      },
    );
  }

  static void _noop() {}

  // ---------------- 设置 ----------------
  void applySettings(SettingsData data) {
    setState(() {
      focusMinutes = data.focusMinutes;
      breakMinutes = data.breakMinutes;
      totalRounds = data.totalRounds;
      vibrateOn = data.vibrateOn;
      soundOn = data.soundOn;
      if (round > totalRounds) round = totalRounds;
    });

    final newTotal = currentTotalMs;
    if (!running) {
      setState(() {
        sessionTotalMs = newTotal;
        remainingMs = sessionTotalMs;
      });
      _progressCtrl.duration = Duration(milliseconds: newTotal);
      _progressCtrl.value = 1.0;
    } else {
      setState(() => sessionTotalMs = newTotal);
      _progressCtrl.stop();
      _progressCtrl.duration = Duration(milliseconds: newTotal);
      _progressCtrl.reverse(from: remainingMs / newTotal);
    }
  }

  void openSettings() {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (ctx, a1, a2) => SettingsPage(
          data: SettingsData(
            focusMinutes: focusMinutes,
            breakMinutes: breakMinutes,
            totalRounds: totalRounds,
            vibrateOn: vibrateOn,
            soundOn: soundOn,
          ),
          onChanged: applySettings,
        ),
        transitionsBuilder: (ctx, a1, a2, child) {
          final curved =
              CurvedAnimation(parent: a1, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
      ),
    );
  }

  // ---------------- 构建 ----------------
  @override
  Widget build(BuildContext context) {
    final mm = (remainingMs / 60000).floor();
    final ss = ((remainingMs % 60000) / 1000).floor();
    final timeText =
        '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
    final modeLabel =
        mode == PomodoroMode.focus ? '专注模式' : '休息模式';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              _buildBackgroundGlow(),
              Column(
                children: [
                  _buildAppBar(),
                  Expanded(child: _buildBody(timeText, modeLabel)),
                  _buildActions(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundGlow() {
    return Positioned(
      top: -80,
      left: 0,
      right: 0,
      height: 320,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                accent.withValues(alpha: 0.12),
                Colors.transparent,
              ],
              radius: 0.8,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              const Text('番茄钟',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ],
          ),
          const Spacer(),
          _CircleIconButton(
            onTap: openSettings,
            child: const Icon(Icons.tune_rounded, size: 21, color: Color(0xFF6B5647)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(String timeText, String modeLabel) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 环形进度
        ScaleTransition(
          scale: _ringScale,
          child: FadeTransition(
            opacity: _ringScale,
            child: SizedBox(
              width: 288,
              height: 288,
              child: CustomPaint(
                painter: _RingPainter(progress: _progressCtrl, color: accent),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: _textFade,
                        child: SlideTransition(
                          position: _textFade.drive(
                            Tween<Offset>(
                              begin: const Offset(0, 0.12),
                              end: Offset.zero,
                            ),
                          ),
                          child: Text(
                            timeText,
                            style: const TextStyle(
                              fontSize: 58,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 2,
                              color: Color(0xFF2E2621),
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // AnimatedSwitcher：模式切换
                      FadeTransition(
                        opacity: _chipFade,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.15),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: _ModeChip(
                            key: ValueKey(mode),
                            label: modeLabel,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),
        // 轮次
        FadeTransition(
          opacity: _roundsFade,
          child: SlideTransition(
            position: _roundsFade.drive(
              Tween<Offset>(
                begin: const Offset(0, 0.12),
                end: Offset.zero,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(totalRounds, (i) {
                    final isDone = i < round - 1;
                    final isCurrent = i == round - 1;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 3.5),
                      width: isCurrent ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isDone
                            ? accent.withValues(alpha: 0.45)
                            : isCurrent
                                ? accent
                                : const Color(0xFFEBDFD4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 10),
                Text('第 $round / $totalRounds 轮',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFA08F81), letterSpacing: 0.5)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return SlideTransition(
      position: _actionsSlide.drive(
        Tween<Offset>(
          begin: const Offset(0, 1.2),
          end: Offset.zero,
        ),
      ),
      child: FadeTransition(
        opacity: _actionsSlide,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          child: Row(
            children: [
              Expanded(
                child: _PrimaryButton(
                  onTap: () => running ? pause() : start(),
                  running: running,
                  accent: accent,
                  accent2: accent2,
                ),
              ),
              const SizedBox(width: 12),
              _GhostButton(
                label: '重置',
                onTap: reset,
              ),
              const SizedBox(width: 12),
              _GhostButton(
                label: mode == PomodoroMode.focus ? '休息' : '专注',
                onTap: () => switchMode(
                    mode == PomodoroMode.focus ? PomodoroMode.rest : PomodoroMode.focus),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 环形进度绘制（CustomPaint + Animation<double>）
// ---------------------------------------------------------------------------
class _RingPainter extends CustomPainter {
  final Animation<double> progress;
  final Color color;

  _RingPainter({required this.progress, required this.color})
      : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;
    const strokeWidth = 14.0;

    final trackPaint = Paint()
      ..color = const Color(0xFFF0E6DC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final value = progress.value.clamp(0.0, 1.0);
    final sweep = -2 * 3.141592653589793 * value; // 逆时针消耗

    final barPaint = Paint()
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: 0.65), color],
        startAngle: -3.141592653589793 / 2,
        endAngle: -3.141592653589793 / 2 + 2 * 3.141592653589793,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.141592653589793 / 2,
      sweep,
      false,
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// 小组件
// ---------------------------------------------------------------------------
class _CircleIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _CircleIconButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF785032).withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final Color color;
  const _ModeChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                  letterSpacing: 0.6)),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool running;
  final Color accent;
  final Color accent2;
  const _PrimaryButton({
    required this.onTap,
    required this.running,
    required this.accent,
    required this.accent2,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [accent2, accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: accent.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 10)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(running),
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 6),
            Text(running ? '暂停' : '开始',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF785032).withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6C5849))),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 结束弹窗
// ---------------------------------------------------------------------------
class _FinishDialog extends StatelessWidget {
  final String title;
  final String desc;
  final List<DialogAction> actions;
  final Color accent;
  const _FinishDialog({
    required this.title,
    required this.desc,
    required this.actions,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFFFFDFB),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [const Color(0xFFF5894F), const Color(0xFFE4572E)]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFE4572E).withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 34),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Text(desc,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, height: 1.6, color: Color(0xFF8B7869))),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      actions.first.onTap();
                    },
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFFF5894F), Color(0xFFE4572E)]),
                        borderRadius: BorderRadius.circular(23),
                      ),
                      child: Center(
                        child: Text(actions.first.label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
                if (actions.length > 1) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        actions[1].onTap();
                      },
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7EFE7),
                          borderRadius: BorderRadius.circular(23),
                        ),
                        child: Center(
                          child: Text(actions[1].label,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6C5849))),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 设置页
// ---------------------------------------------------------------------------
class SettingsPage extends StatefulWidget {
  final SettingsData data;
  final ValueChanged<SettingsData> onChanged;
  const SettingsPage({super.key, required this.data, required this.onChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late int focusMinutes;
  late int breakMinutes;
  late int totalRounds;
  late bool vibrateOn;
  late bool soundOn;

  @override
  void initState() {
    super.initState();
    focusMinutes = widget.data.focusMinutes;
    breakMinutes = widget.data.breakMinutes;
    totalRounds = widget.data.totalRounds;
    vibrateOn = widget.data.vibrateOn;
    soundOn = widget.data.soundOn;
  }

  void _emit() {
    widget.onChanged(SettingsData(
      focusMinutes: focusMinutes,
      breakMinutes: breakMinutes,
      totalRounds: totalRounds,
      vibrateOn: vibrateOn,
      soundOn: soundOn,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFBF6),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    _CircleIconButton(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 19, color: Color(0xFF6B5647)),
                    ),
                    const SizedBox(width: 12),
                    const Text('设置',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    const _SectionTitle('时间'),
                    _Card(children: [
                      _StepperRow(
                        title: '专注时长',
                        desc: '每一轮番茄的时长',
                        value: focusMinutes,
                        unit: '分',
                        min: 1,
                        max: 60,
                        onChanged: (v) => setState(() {
                          focusMinutes = v;
                          _emit();
                        }),
                      ),
                      _StepperRow(
                        title: '休息时长',
                        desc: '专注结束后的休整时间',
                        value: breakMinutes,
                        unit: '分',
                        min: 1,
                        max: 30,
                        onChanged: (v) => setState(() {
                          breakMinutes = v;
                          _emit();
                        }),
                      ),
                      _StepperRow(
                        title: '循环轮次',
                        desc: '完成后重置轮次计数',
                        value: totalRounds,
                        unit: '轮',
                        min: 1,
                        max: 10,
                        onChanged: (v) => setState(() {
                          totalRounds = v;
                          _emit();
                        }),
                      ),
                    ]),
                    const SizedBox(height: 18),
                    const _SectionTitle('提示'),
                    _Card(children: [
                      _SwitchRow(
                        title: '计时结束震动',
                        desc: 'HapticFeedback.vibrate()',
                        value: vibrateOn,
                        onChanged: (v) => setState(() {
                          vibrateOn = v;
                          _emit();
                        }),
                      ),
                      _SwitchRow(
                        title: '计时结束提示音',
                        desc: '可选功能，后续接入音频插件',
                        value: soundOn,
                        onChanged: (v) => setState(() {
                          soundOn = v;
                          _emit();
                        }),
                      ),
                    ]),
                    const SizedBox(height: 22),
                    const Center(
                      child: Text('修改后立即生效',
                          style: TextStyle(
                              fontSize: 11.5, color: Color(0xFFB0A093))),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: Color(0xFFA08F81))),
      );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i != children.length - 1) {
        items.add(const Divider(height: 1, color: Color(0x12785A46)));
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF6E4B32).withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Column(children: items),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String title;
  final String desc;
  final int value;
  final String unit;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _StepperRow({
    required this.title,
    required this.desc,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 11.5, color: Color(0xFFA8968A))),
              ],
            ),
          ),
          _StepperButton(
              icon: Icons.remove,
              onTap: value > min ? () => onChanged(value - 1) : null),
          Container(
            width: 66,
            alignment: Alignment.center,
            child: Text('$value',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
          _StepperButton(
              icon: Icons.add,
              onTap: value < max ? () => onChanged(value + 1) : null),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0xFFFAF2EA),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF7C6553)),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String desc;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.title,
    required this.desc,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 11.5, color: Color(0xFFA8968A))),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFFE4572E),
          ),
        ],
      ),
    );
  }
}
