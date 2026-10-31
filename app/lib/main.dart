import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/core/i18n.dart';
import 'src/data/repository.dart';
import 'src/state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
  }
  if (Platform.isWindows) {
    if (!await NoteStore.acquireProcessLock()) {
      // 已经有一个「此记」在跑了。静默退出，避免两边同时写同一批文件。
      exit(0);
    }
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1400, 900),
      minimumSize: Size(1020, 680),
      center: true,
      title: '此记 · ThisNote',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Color(0xFFF4EFE4),
    );
    // 关闭前先落盘：交给 AppShell.onWindowClose 处理，处理完再 destroy。
    await windowManager.setPreventClose(true);
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final state = AppState();
  try {
    await state.init();
  } catch (e) {
    state.startupError = e.toString();
  }
  // 任务栏上显示的名字也跟着语言走；窗口本身无边框，标题只对系统可见。
  if (Platform.isWindows) {
    await windowManager.setTitle(
      I18n.lang == AppLang.en ? 'ThisNote' : '此记 · ThisNote',
    );
  }
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const ThisNoteApp(),
    ),
  );
}
