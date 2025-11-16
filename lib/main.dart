import 'package:flutter/material.dart';
import 'home_screen.dart';

void main() {
  runApp(const SafeWayApp());
}

class SafeWayApp extends StatelessWidget {
  const SafeWayApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Safe Way',
      home: NavigationScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}