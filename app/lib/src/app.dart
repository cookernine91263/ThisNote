import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'core/theme_reveal.dart';
import 'features/lock_screen.dart';
import 'features/onboarding.dart';
import 'features/shell.dart';
import 'features/splash.dart';
import 'state/app_state.dart';

class ThisNoteApp extends StatelessWidget {
  const ThisNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.settings;
    const scale = 1.0;
    return RepaintBoundary(
      key: ThemeReveal.rootKey,
      child: MaterialApp(
      title: '此记 · ThisNote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(
        Brightness.light,
        scale,
        accent: settings.accent,
      ),
      darkTheme: AppTheme.build(
        Brightness.dark,
        scale,
        accent: settings.accent,
      ),
      themeMode: settings.themeMode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      scrollBehavior: const _AppScrollBehavior(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  Theme.of(context).brightness == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
              systemNavigationBarColor: AppPalette.of(context).paper,
              systemNavigationBarIconBrightness:
                  Theme.of(context).brightness == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
            ),
            child: child!,
          ),
        );
      },
      home: const _AppGate(),
      ),
    );
  }
}

class _AppGate extends StatelessWidget {
  const _AppGate();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.startupError != null) {
      return _StartupErrorScreen(error: state.startupError!);
    }
    if (!state.ready) return const SplashScreen();
    if (state.locked) return const LockScreen();
    if (!state.settings.onboardingDone) return const OnboardingScreen();
    return const AppShell();
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Seal(size: 44, radius: 12),
                const SizedBox(height: 18),
                Text(
                  '暂时打不开这张纸',
                  style: TextStyle(
                    fontFamily: 'WenKai',
                    fontSize: 24,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '数据目录可能被占用或没有写入权限。你的文字不会被删除。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 12,
                    height: 1.8,
                    color: c.inkSoft,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.ink,
                    foregroundColor: c.paper,
                  ),
                  onPressed: () => context.read<AppState>().retryInit(),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}

