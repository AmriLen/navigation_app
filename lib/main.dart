import 'package:flutter/material.dart';
import 'package:SafeRoad/MainPage.dart';



void main() async {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.deepOrange),
      ),
      home: MainPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}