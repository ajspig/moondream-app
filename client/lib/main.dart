import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:livekit_components/livekit_components.dart';
import 'package:logging/logging.dart';

import 'home_screen.dart';

void main() async {
  final format = DateFormat('HH:mm:ss');

  // configure logs for debugging
  Logger.root.level = Level.FINE;
  Logger.root.onRecord.listen((record) {
    if (kDebugMode) {
      print('${format.format(record.time)}: ${record.message}');
    }
  });

  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiveKit Moondream App',
      theme: LiveKitTheme().buildThemeData(context),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
