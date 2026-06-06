import 'package:flutter/material.dart';

import 'screens/main_screen.dart';

void main() {
  runApp(const ClipSyncApp());
}

class ClipSyncApp extends StatelessWidget {
  const ClipSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClipSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}
