import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vibration/vibration_presets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';
import 'package:ultralytics_yolo/yolo.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});
  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {

  // FLUTTER TTS
  FlutterTts? _flutterTts;
  
  // STATES PARAMETRS
  final player = AudioPlayer();
  bool _isCameraActive = false;
  bool _isModelLoaded = false;
  bool _isVoiceEnabled = true;
  bool _isSoundEnabled = true;
  bool _isVibrationEnabled = true;
  
  // Initialize Function
  @override
  void initState() {
    super.initState();
    _initializeTTS();
    WakelockPlus.enable();
    Vibration.vibrate(preset: VibrationPreset.doubleBuzz);
  }

  Future<void> _initializeTTS() async {
    _flutterTts = FlutterTts();
    
    try {
      await _flutterTts?.setLanguage("ru-RU");
      await _flutterTts?.setSpeechRate(0.8);
      await _flutterTts?.setVolume(1.0);
      await _flutterTts?.setPitch(1.0);
      
      // _flutterTts?.setStartHandler(() {
      //   debugPrint("TTS started");
      // });
      
      // _flutterTts?.setCompletionHandler(() {
      //   debugPrint("TTS completed");
      // });
      
      // _flutterTts?.setErrorHandler((msg) {
      //   debugPrint("TTS error: $msg");
      // });
      
    } catch (e) {
      debugPrint('Ошибка инициализации TTS: $e');
    }
    
    // _voiceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    //   if (_isVoiceEnabled && _detectedObjects.isNotEmpty && mounted) {
    //     _announceObjects();
    //   }
    // });
  }

  /*====================================================================================*/

  // * Toggle Voice Function
  void _toggleVoice() {
    setState(() {
      _isVoiceEnabled = !_isVoiceEnabled;
    });
    
    if (_isVoiceEnabled) {
      _flutterTts?.stop();
      _flutterTts!.speak("Озвучивание включено");
      Vibration.vibrate(preset: VibrationPreset.doubleBuzz);
    } else {
      _flutterTts?.stop();
      _flutterTts!.speak("Озвучивание выключено");
      Vibration.vibrate(duration: 500);
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isVoiceEnabled ? 
          'Озвучивание включено' : 'Озвучивание выключено', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),),
          backgroundColor: _isVoiceEnabled ? 
          Colors.blue : Colors.red,
        duration: const Duration(milliseconds: 500),
      ),
    );
  }

  // * Toggle Sound Function
  void _toggleSound() {
    setState(() {
      _isSoundEnabled = !_isSoundEnabled;
    });
    
    if (_isSoundEnabled) {
      _flutterTts?.stop();
      _flutterTts!.speak("Звуки включены");
      Vibration.vibrate(preset: VibrationPreset.doubleBuzz);
    } else {
      _flutterTts?.stop();
      _flutterTts!.speak("Звуки выключены");
      Vibration.vibrate(duration: 500);
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isSoundEnabled ? 
          'Звуки включены' : 'Звуки выключены', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),),
          backgroundColor: _isSoundEnabled ? 
          Colors.blue : Colors.red,
        duration: const Duration(milliseconds: 500),
      ),
    );
  }

  // * Toggle Vibration Function
  void _toggleVibration() {
    setState(() {
      _isVibrationEnabled = !_isVibrationEnabled;
    });
    
    if (_isVibrationEnabled) {
      _flutterTts?.stop();
      _flutterTts!.speak("Вибрации включены");
      Vibration.vibrate(preset: VibrationPreset.doubleBuzz);
    } else {
      _flutterTts?.stop();
      _flutterTts!.speak("Вибрации выключены");
      Vibration.vibrate(duration: 500);
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isVibrationEnabled ? 
          'Вибрации включены' : 'Вибрации выключены', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),),
          backgroundColor: _isVibrationEnabled ? 
          Colors.blue : Colors.red,
        duration: const Duration(milliseconds: 500),
      ),
    );
  }

  // * State Panel Widget
  Widget _statePanel(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  // * Camera Frame Widget
  Widget _cameraFrame() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: ElevatedButton(
          child: Text('Test YOLO'),
          onPressed: () async {
            try {
              final yolo = YOLO(
                modelPath: 'assets/yolo11n.tflite',
                task: YOLOTask.detect,
              );

              await yolo.loadModel();
              print('✅ YOLO loaded successfully!');

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('YOLO plugin working!')),
              );
            } catch (e) {
              print('❌ Error: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e')),
              );
            }
          },
        ),
      ),
    );



    // const Scaffold(
    //   backgroundColor: Colors.transparent,
    //   body: Center(
    //     child: Text("CAMERA FRAME", style: TextStyle(color: Colors.white)),
    //   ),
    // );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safe Way', style: TextStyle(fontWeight: FontWeight.bold),),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: double.maxFinite,
            height: 600,
            color: Colors.blueGrey,
            child:
            Stack(
              children: [
                _cameraFrame(),
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isCameraActive ? Icons.videocam : Icons.videocam_off,
                          color: _isCameraActive ? Colors.red : Colors.blue, 
                          size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            //'LIVE | Объектов: ${_detectedObjects.length} | Кадр: $_frameCounter',
                            _isCameraActive ? 'LIVE | Объектов: ??? | Кадр: ???' : 'OFFLINE',
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            //color: Colors.white,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      iconSize: 50,
                      onPressed: _toggleVoice,
                      icon: Icon(_isVoiceEnabled ? Icons.volume_up : Icons.volume_off),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: _isVoiceEnabled ? Colors.blue : Colors.red,
                      ),
                    ),
                    IconButton(
                      iconSize: 50,
                      onPressed: _toggleSound,
                      icon: Icon(_isSoundEnabled ? Icons.music_note : Icons.music_off),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: _isSoundEnabled ? Colors.blue : Colors.red,
                      ),
                    ),
                    IconButton(
                      iconSize: 50,
                      onPressed: _toggleVibration,
                      icon: const Icon(Icons.vibration),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: _isVibrationEnabled ? Colors.blue : Colors.red,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Статус:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        _statePanel('КАМЕРА', _isCameraActive ? Colors.blue : Colors.red,),
                        _statePanel('ИИ', _isModelLoaded ? Colors.blue : Colors.red,),
                        _statePanel('ГОЛОС', _isVoiceEnabled ? Colors.blue : Colors.red,),
                        _statePanel('ЗВУКИ', _isSoundEnabled ? Colors.blue : Colors.red,),
                        _statePanel('ВИБР', _isVibrationEnabled ? Colors.blue : Colors.red,),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}