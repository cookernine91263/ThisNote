import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
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
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1400, 900),
      minimumSize: Size(1020, 680),
      center: true,
      title: '姝よ 路 ThisNote',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Color(0xFFF4EFE4),
    );
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
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const ThisNoteApp(),
    ),
  );
}

