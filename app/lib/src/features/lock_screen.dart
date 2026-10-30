import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/motion.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../state/app_state.dart';
import 'splash.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _error = false;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _shake.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _press(String d) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += d;
      _error = false;
    });
    if (_pin.length == 4) _verify();
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = false;
    });
  }

  Future<void> _verify() async {
    final state = context.read<AppState>();
    if (state.verifyPin(_pin)) {
      HapticFeedback.lightImpact();
      state.unlock();
    } else {
      HapticFeedback.mediumImpact();
      setState(() => _error = true);
      await _shake.forward(from: 0);
      if (mounted) setState(() => _pin = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final ch = event.character;
          if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
            _press(ch);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.backspace) {
            _backspace();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: PaperGrain(color: c.ink, opacity: c.grain * 0.8),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Seal(size: 52, radius: 14),
                    const SizedBox(height: 22),
                    Text(
                      '此记已上锁',
                      style: TextStyle(
                        fontFamily: 'WenKai',
                        fontSize: 22,
                        letterSpacing: 2,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '输入 4 位密码，继续写字',
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 12,
                        color: c.inkMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 30),
                    AnimatedBuilder(
                      animation: _shake,
                      builder: (context, child) {
                        final t = _shake.value;
                        final dx = math.sin(t * math.pi * 8) * 7 * (1 - t);
                        return Transform.translate(offset: Offset(dx, 0), child: child);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(4, (i) {
                          final filled = i < _pin.length;
                          return AnimatedContainer(
                            duration: Motion.fast,
                            curve: Motion.spring,
                            margin: const EdgeInsets.symmetric(horizontal: 7),
                            width: filled ? 13 : 11,
                            height: filled ? 13 : 11,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _error
                                  ? c.danger
                                  : filled
                                      ? c.ink
                                      : Colors.transparent,
                              border: Border.all(
                                color: _error
                                    ? c.danger
                                    : filled
                                        ? c.ink
                                        : c.lineStrong,
                                width: 1.4,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 40),
                    _Keypad(
                      onDigit: _press,
                      onBackspace: _backspace,
                      onClear: () => setState(() => _pin = ''),
                      error: _error,
                    ),
                    const SizedBox(height: 26),
                    Text(
                      '密码只保存在本机，忘记后无法找回',
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 10.5,
                        color: c.inkMuted,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.error,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return SizedBox(
      width: 264,
      child: Column(
        children: [
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final d in row) _Key(label: d, onTap: () => onDigit(d)),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Key(
                label: '清空',
                small: true,
                onTap: onClear,
                color: c.inkMuted,
              ),
              _Key(label: '0', onTap: () => onDigit('0')),
              _Key(
                icon: Icons.backspace_outlined,
                small: true,
                onTap: onBackspace,
                color: c.inkMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    this.label,
    this.icon,
    required this.onTap,
    this.small = false,
    this.color,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool small;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return HoverBuilder(
      builder: (context, hovered, t) {
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            width: 72,
            height: 62,
            margin: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: hovered ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hovered ? c.line : Colors.transparent,
              ),
            ),
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, size: 18, color: color ?? c.inkSoft)
                : Text(
                    label!,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: small ? 11 : 22,
                      fontWeight: small ? FontWeight.w400 : FontWeight.w300,
                      color: color ?? c.ink,
                      height: 1,
                    ),
                  ),
          ),
        );
      },
    );
  }
}
