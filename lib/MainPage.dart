import 'package:flutter/material.dart';
import 'package:SafeRoad/MainPage.dart';

class MainPage extends StatefulWidget {
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text("Это приложение"),
      ),
      body: Container(
        child: Text("Hello world!"),
      ),
    );
  }
}