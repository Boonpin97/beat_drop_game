import 'package:beatdrop_shared/beatdrop_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform/platform.dart';
import 'screens/landing_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  runApp(RhythmApp(inviteCode: _inviteCode(Uri.base)));
}

/// The room code in a shared `/r/<code>` link.
String? _inviteCode(Uri uri) {
  final s = uri.pathSegments;
  return s.length == 2 && s[0] == 'r' ? normalizeRoomCode(s[1]) : null;
}

class RhythmApp extends StatelessWidget {
  RhythmApp({super.key, this.inviteCode});

  final String? inviteCode;
  final _sound = SoundEngine();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Challenge your sense',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: LandingScreen(sound: _sound, inviteCode: inviteCode),
    );
  }
}
