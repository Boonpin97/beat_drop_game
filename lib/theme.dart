import 'package:beatdrop_shared/beatdrop_shared.dart';
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const cream = Color(0xFFFFF7EE);
  static const ink = Color(0xFF1F1A24);
  static const muted = Color(0xFF7A7080);
  static const red = Color(0xFFD7263D);

  /// Buttons and switches, with white text.
  static const accent = Color(0xFFC45A5A);
  static const card = Colors.white;
  static const line = Color(0xFFEDE3D8);
}

/// One soft colour per seat: pastel enough to sit behind the drum full
/// screen, with hues spread out so neighbours in the lobby stay distinct.
const playerPalette = <Color>[
  Color(0xFFF7B9BE), // rose
  Color(0xFFAEDFC6), // mint
  Color(0xFFAED6F3), // sky
  Color(0xFFF8E3A3), // butter
  Color(0xFFD3C1F2), // lavender
  Color(0xFFFFCFA3), // apricot
  Color(0xFFA6DDDB), // aqua
  Color(0xFFEFBDE6), // orchid
  Color(0xFFD5EAA8), // pistachio
  Color(0xFFBFC8F7), // periwinkle
  Color(0xFFE2CDB4), // sand
  Color(0xFFC9D1DA), // mist
];

Color playerColor(int index) =>
    playerPalette[index % playerColorCount % playerPalette.length];

/// Black or white, whichever reads better on [background].
Color onColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? Colors.white
    : AppColors.ink;

/// Pale wash of [accent] for secondary buttons.
Color accentTint(Color accent) => Color.lerp(Colors.white, accent, 0.13)!;

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.accent,
    onPrimary: Colors.white,
    surface: AppColors.cream,
    onSurface: AppColors.ink,
  );
  const radius = BorderRadius.all(Radius.circular(14));
  const buttonShape = RoundedRectangleBorder(borderRadius: radius);
  const buttonSize = Size.fromHeight(50);
  const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.cream,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: buttonSize,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonSize,
        shape: buttonShape,
        textStyle: buttonText,
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.ink, width: 1.5),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.ink, width: 1.5),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.cream,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.ink,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.muted,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// A player's coloured circle with their initial.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.name,
    required this.color,
    this.size = 56,
  });

  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(
          color: onColor(color),
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
