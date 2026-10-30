import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// 此记的色彩系统：宣纸、墨、朱砂。
/// 低饱和、暖灰底、单一强调色，避免界面花哨。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.paper,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkSoft,
    required this.inkMuted,
    required this.line,
    required this.lineStrong,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.gold,
    required this.sage,
    required this.blue,
    required this.danger,
    required this.selection,
    required this.shadow,
    required this.grain,
  });

  /// 纸张底色（窗口背景）
  final Color paper;

  /// 卡片 / 面板
  final Color surface;

  /// 次级面板
  final Color surfaceAlt;

  /// 主文字：墨
  final Color ink;

  /// 次级文字
  final Color inkSoft;

  /// 辅助文字 / 占位
  final Color inkMuted;

  /// 发丝线
  final Color line;

  /// 稍强分隔线
  final Color lineStrong;

  /// 朱砂强调色
  final Color accent;
  final Color onAccent;
  final Color accentSoft;

  /// 金 / 松 / 黛 辅助色
  final Color gold;
  final Color sage;
  final Color blue;
  final Color danger;

  /// 文本选区
  final Color selection;

  /// 阴影基色
  final Color shadow;

  /// 纸纹颗粒强度
  final double grain;

  static const light = AppPalette(
    paper: Color(0xFFF4EFE4),
    surface: Color(0xFFFBF7EE),
    surfaceAlt: Color(0xFFEDE5D6),
    ink: Color(0xFF211E19),
    inkSoft: Color(0xFF575149),
    inkMuted: Color(0xFF8D8576),
    line: Color(0xFFE3DAC8),
    lineStrong: Color(0xFFD3C7B0),
    accent: Color(0xFFA84637),
    onAccent: Color(0xFFFFF9F2),
    accentSoft: Color(0xFFF2DED6),
    gold: Color(0xFFA8824B),
    sage: Color(0xFF6F806C),
    blue: Color(0xFF56697D),
    danger: Color(0xFFA04434),
    selection: Color(0x33A84637),
    shadow: Color(0xFF4A3826),
    grain: 0.055,
  );

  static const dark = AppPalette(
    paper: Color(0xFF161411),
    surface: Color(0xFF1D1B17),
    surfaceAlt: Color(0xFF24211C),
    ink: Color(0xFFEDE6D8),
    inkSoft: Color(0xFFB7AFA0),
    inkMuted: Color(0xFF7E776B),
    line: Color(0xFF322E27),
    lineStrong: Color(0xFF443E35),
    accent: Color(0xFFD07E6F),
    onAccent: Color(0xFF241512),
    accentSoft: Color(0xFF3A2A25),
    gold: Color(0xFFC9A46C),
    sage: Color(0xFF93A38E),
    blue: Color(0xFF8AA0B8),
    danger: Color(0xFFD08070),
    selection: Color(0x55D07E6F),
    shadow: Color(0xFF000000),
    grain: 0.04,
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? light;

  bool get isDark => paper.computeLuminance() < 0.3;

  @override
  AppPalette copyWith({
    Color? paper,
    Color? surface,
    Color? surfaceAlt,
    Color? ink,
    Color? inkSoft,
    Color? inkMuted,
    Color? line,
    Color? lineStrong,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? gold,
    Color? sage,
    Color? blue,
    Color? danger,
    Color? selection,
    Color? shadow,
    double? grain,
  }) {
    return AppPalette(
      paper: paper ?? this.paper,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkMuted: inkMuted ?? this.inkMuted,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentSoft: accentSoft ?? this.accentSoft,
      gold: gold ?? this.gold,
      sage: sage ?? this.sage,
      blue: blue ?? this.blue,
      danger: danger ?? this.danger,
      selection: selection ?? this.selection,
      shadow: shadow ?? this.shadow,
      grain: grain ?? this.grain,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      paper: Color.lerp(paper, other.paper, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      grain: lerpDouble(grain, other.grain, t)!,
    );
  }
}

class AppTypography {
  static const ui = 'NotoSansSC';

  static TextTheme textTheme(AppPalette c) {
    TextStyle base(double size, FontWeight w, {double? height, double? ls}) =>
        TextStyle(
          fontFamily: ui,
          fontSize: size,
          fontWeight: w,
          color: c.ink,
          height: height,
          letterSpacing: ls,
          fontFamilyFallback: const ['NotoSansSC', 'Microsoft YaHei'],
        );
    return TextTheme(
      displayLarge: base(44, FontWeight.w300, height: 1.15, ls: -1.2),
      displayMedium: base(36, FontWeight.w300, height: 1.18, ls: -0.8),
      displaySmall: base(30, FontWeight.w400, height: 1.2, ls: -0.4),
      headlineLarge: base(26, FontWeight.w600, height: 1.3, ls: -0.3),
      headlineMedium: base(22, FontWeight.w600, height: 1.35, ls: -0.2),
      headlineSmall: base(19, FontWeight.w600, height: 1.4, ls: -0.1),
      titleLarge: base(17, FontWeight.w600, height: 1.45),
      titleMedium: base(15, FontWeight.w500, height: 1.5),
      titleSmall: base(13.5, FontWeight.w500, height: 1.45),
      bodyLarge: base(15.5, FontWeight.w400, height: 1.75),
      bodyMedium: base(14, FontWeight.w400, height: 1.7),
      bodySmall: base(12.5, FontWeight.w400, height: 1.6),
      labelLarge: base(13.5, FontWeight.w500, height: 1.4),
      labelMedium: base(12, FontWeight.w500, height: 1.4, ls: 0.2),
      labelSmall: base(10.5, FontWeight.w500, height: 1.4, ls: 0.8),
    );
  }
}

class AppTheme {
  static const accents = <String, Color>{
    'vermilion': Color(0xFFA84637),
    'ink': Color(0xFF44515F),
    'sage': Color(0xFF5E7359),
    'gold': Color(0xFF9C7A43),
  };

  static ThemeData build(
    Brightness brightness,
    double fontScale, {
    String accent = 'vermilion',
  }) {
    var c = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
    final custom = accent.startsWith('#')
        ? int.tryParse(accent.substring(1), radix: 16)
        : null;
    final accentColor = custom != null
        ? Color(0xFF000000 | custom)
        : accents[accent] ?? accents['vermilion']!;
    final adjusted = brightness == Brightness.dark
        ? Color.lerp(accentColor, Colors.white, 0.35)!
        : accentColor;
    c = c.copyWith(
      accent: adjusted,
      accentSoft: Color.alphaBlend(
        adjusted.withValues(alpha: brightness == Brightness.dark ? 0.18 : 0.11),
        c.surface,
      ),
    );
    final text = AppTypography.textTheme(c);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.ink,
      secondary: c.gold,
      onSecondary: c.onAccent,
      secondaryContainer: c.surfaceAlt,
      onSecondaryContainer: c.ink,
      tertiary: c.sage,
      onTertiary: c.onAccent,
      error: c.danger,
      onError: c.onAccent,
      surface: c.surface,
      onSurface: c.ink,
      surfaceContainerHighest: c.surfaceAlt,
      onSurfaceVariant: c.inkSoft,
      outline: c.lineStrong,
      outlineVariant: c.line,
      shadow: c.shadow,
      scrim: c.shadow,
      inverseSurface: c.ink,
      onInverseSurface: c.paper,
      inversePrimary: c.accent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: AppTypography.ui,
      scaffoldBackgroundColor: c.paper,
      canvasColor: c.paper,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: text.apply(fontSizeFactor: fontScale),
      extensions: [c],
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.inkSoft, size: 20),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 420),
        decoration: BoxDecoration(
          color: c.ink,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
          fontFamily: AppTypography.ui,
          fontSize: 12,
          color: c.paper,
          height: 1.3,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintStyle: TextStyle(color: c.inkMuted, fontSize: 14),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(5),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => c.inkMuted.withValues(alpha: s.contains(WidgetState.hovered) ? 0.35 : 0.18),
        ),
        crossAxisMargin: 2,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.selection,
        selectionHandleColor: c.accent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: TextStyle(
          fontFamily: AppTypography.ui,
          color: c.paper,
          fontSize: 13,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.all(18),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.line),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: c.shadow.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.line),
        ),
        textStyle: TextStyle(
          fontFamily: AppTypography.ui,
          fontSize: 13,
          color: c.ink,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// 常用间距
class Insets {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

/// 圆角
class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 22.0;
}
