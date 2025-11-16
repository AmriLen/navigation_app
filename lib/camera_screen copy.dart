import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _isCameraActive = false;
  bool _isLoading = false;
  bool _isModelLoaded = false;
  String _cameraError = '';
  CameraController? _controller;
  final List<DetectedObject> _detectedObjects = [];
  Timer? _detectionTimer;
  int _frameCounter = 0;
  List<CameraDescription>? _cameras;
  Interpreter? _interpreter;
  bool _isProcessing = false;
  
  // Переменные для озвучивания
  FlutterTts? _flutterTts;
  bool _isVoiceEnabled = true;
  Timer? _voiceTimer;
  final Set<String> _announcedObjects = {};
  DateTime _lastVoiceTime = DateTime.now();

  // Переменные для звуков
  final player = AudioPlayer();
  bool _isSoundEnabled = true;

  // Настройки модели
  static const String _modelPath = 'assets/ssd_mobilenet.tflite';
  static const double _confidenceThreshold = 0.6; // Понижаем порог для лучшего обнаружения
  
  // Полный словарь меток на русском языке
  static const Map<String, String> _russianLabels = {
    'person': 'Человек',
    'bicycle': 'Велосипед',
    'car': 'Автомобиль',
    'motorcycle': 'Мотоцикл',
    'bus': 'Автобус',
    'train': 'Поезд',
    'truck': 'Грузовик',
    'traffic light': 'Светофор',
    'fire hydrant': 'Пожарный гидрант',
    'stop sign': 'Знак стоп',
    'parking meter': 'Парковочный счетчик',
    'bench': 'Скамейка',
    'cat': 'Кошка',
    'dog': 'Собака',
    'horse': 'Лошадь',
    'sheep': 'Овца',
    'cow': 'Корова',
    'elephant': 'Слон',
    'bear': 'Медведь',
    'zebra': 'Зебра',
    'giraffe': 'Жираф',
    'sports ball': 'Мяч',
    'skateboard': 'Скейтборд',
    'chair': 'Стул',
    'couch': 'Диван',
    'potted plant': 'Растение в горшке',
    'bed': 'Кровать',
    'dining table': 'Стол',
    'tv': 'Телевизор',
    'sink': 'Раковина',
    'refrigerator': 'Холодильник',
  };

  // Приоритетные объекты для навигации (более важные объекты)
  static const List<String> _priorityObjects = [
    'person', 'car', 'truck', 'bus', 'motorcycle', 'bicycle',
    'chair', 'table', 'door', 'stairs', 'wall'
  ];

  @override
  void initState() {
    super.initState();
    _initializeTTS();
    _initializeApp();
    WakelockPlus.enable();
    _flutterTts!.speak("Запуск помошника");
    HapticFeedback.heavyImpact();
  }

  Future<void> _initializeTTS() async {
    _flutterTts = FlutterTts();
    
    try {
      await _flutterTts?.setLanguage("ru-RU");
      await _flutterTts?.setSpeechRate(0.8);
      await _flutterTts?.setVolume(1.0);
      await _flutterTts?.setPitch(1.0);
      
      // Добавляем обработчики событий TTS для отладки
      _flutterTts?.setStartHandler(() {
        debugPrint("TTS started");
      });
      
      _flutterTts?.setCompletionHandler(() {
        debugPrint("TTS completed");
      });
      
      _flutterTts?.setErrorHandler((msg) {
        debugPrint("TTS error: $msg");
      });
      
    } catch (e) {
      debugPrint('Ошибка инициализации TTS: $e');
    }
    
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isVoiceEnabled && _detectedObjects.isNotEmpty && mounted) {
        _announceObjects();
      }
    });
  }

  // Улучшаем логику озвучивания
  Future<void> _announceObjects() async {
    AudioPlayer().stop();
    if (!_isVoiceEnabled || _flutterTts == null || !mounted) return;

    if (_isSoundEnabled) {
      player.setAsset('assets/warn.mp3');
      player.setVolume(1);
      player.play();
    }

    final now = DateTime.now();
    // Увеличиваем интервал между озвучиваниями
    if (now.difference(_lastVoiceTime).inSeconds < 1) return;
    
    try {
      // Фильтруем объекты для озвучивания
      final objectsToAnnounce = _detectedObjects
          .where((obj) => obj.distance < 8.0)
          .where((obj) => _isPriorityObject(obj.name))
          .where((obj) => !_announcedObjects.contains(_getObjectKey(obj)))
          .where((obj) => obj.confidence > 0.6) // Повышаем порог уверенности
          .toList();
      
      if (objectsToAnnounce.isNotEmpty) {
        // Сортируем по приоритету и расстоянию
        objectsToAnnounce.sort((a, b) {
          final priorityA = _getObjectPriority(a.name);
          final priorityB = _getObjectPriority(b.name);
          if (priorityA != priorityB) {
            return priorityB.compareTo(priorityA);
          }
          return a.distance.compareTo(b.distance);
        });
        
        final nearestObject = objectsToAnnounce.first;
        
        // Проверяем, достаточно ли объект значим для озвучивания
        if (_shouldAnnounceObject(nearestObject)) {
          final announcement = _generateAnnouncement(nearestObject);
          debugPrint('Озвучивание: $announcement');
          
          await _flutterTts!.speak(announcement);
          _announcedObjects.add(_getObjectKey(nearestObject));
          _lastVoiceTime = DateTime.now();
          
          // Ограничиваем размер множества озвученных объектов
          if (_announcedObjects.length > 20) {
            final temp = _announcedObjects.toList().sublist(10);
            _announcedObjects.clear();
            _announcedObjects.addAll(temp);
          }
          
        }
      }
    } catch (e) {
      debugPrint('Ошибка озвучивания: $e');
    }
  }

  // Проверяем, стоит ли озвучивать объект
  bool _shouldAnnounceObject(DetectedObject obj) {
    // Озвучиваем только если объект достаточно уверенно распознан
    if (obj.confidence < 0.4) return false;
    
    // Озвучиваем близкие объекты чаще
    if (obj.distance < 6.0) return true;
    
    // Для далеких объектов озвучиваем только приоритетные
    if (obj.distance >= 6.0) {
      return _getObjectPriority(obj.name) >= 70;
    }
    
    return true;
  }

  // Улучшаем генерацию объявления
  String _generateAnnouncement(DetectedObject obj) {
    String distanceText;
    
    if (obj.distance <= 1.0) {
      distanceText = '1 метр';
    } else if (obj.distance <= 2.0) {
      distanceText = '2 метра';
    } else if (obj.distance <= 3.0) {
      distanceText = '3 метра';
    } else if (obj.distance <= 3.0) {
      distanceText = '4 метра';
    } else if (obj.distance <= 3.0) {
      distanceText = '5 метров';
    } else if (obj.distance <= 6.0) {
      distanceText = '6 метров';
    } else {
      distanceText = 'Дальше';
    }
    
    // Для особо близких объектов добавляем предупреждение
    if (obj.distance < 2.0) {
      return 'Внимание! ${obj.name} $distanceText ${obj.direction}';
    }
    
    // Упрощаем фразу для лучшего восприятия
    return '${obj.name} $distanceText';
  }

  // Проверяем, является ли объект приоритетным для навигации
  bool _isPriorityObject(String objectName) {
    final englishName = _russianLabels.entries
        .firstWhere((entry) => entry.value == objectName, orElse: () => const MapEntry('', ''))
        .key;
    return _priorityObjects.contains(englishName) || objectName.contains('человек') || objectName.contains('авто');
  }

  // Получаем приоритет объекта (чем выше число, тем выше приоритет)
  int _getObjectPriority(String objectName) {
    final englishName = _russianLabels.entries
        .firstWhere((entry) => entry.value == objectName, orElse: () => const MapEntry('', ''))
        .key;
    
    if (englishName == 'person') return 100;
    if (['car', 'truck', 'bus', 'motorcycle'].contains(englishName)) return 90;
    if (['chair', 'table', 'door'].contains(englishName)) return 80;
    if (['stairs', 'wall'].contains(englishName)) return 70;
    return 50;
  }

  String _getObjectKey(DetectedObject obj) {
    return '${obj.name}_${obj.direction}_${(obj.distance ~/ 0.5)}';
  }

  void _toggleVoice() {
    setState(() {
      _isVoiceEnabled = !_isVoiceEnabled;
    });
    
    if (_isVoiceEnabled) {
      _announcedObjects.clear();
      _flutterTts!.speak("Озвучивание включено");
    } else {
      _flutterTts?.stop();
      _flutterTts!.speak("Озвучивание выключено");
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isVoiceEnabled ? 
          'Озвучивание включено' : 'Озвучивание выключено', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),),
          backgroundColor: _isVoiceEnabled ? 
          Colors.green : Colors.red,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _toggleSound() {
    setState(() {
      _isSoundEnabled = !_isSoundEnabled;
    });
    
    if (_isSoundEnabled) {
      _announcedObjects.clear();
      _flutterTts!.speak("Звуки включены");
    } else {
      _flutterTts?.stop();
      _flutterTts!.speak("Звуки выключены");
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isSoundEnabled ? 
          'Звуки включены' : 'Звуки выключены', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),),
          backgroundColor: _isSoundEnabled ? 
          Colors.green : Colors.red,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _initializeApp() async {
    await _loadModel();
    await _initializeCamera();
  }

  Future<void> _loadModel() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final options = InterpreterOptions();
      
      _interpreter = await Interpreter.fromAsset(
        _modelPath,
        options: options,
      );

      var inputTensors = _interpreter!.getInputTensors();
      var outputTensors = _interpreter!.getOutputTensors();
      
      debugPrint('Модель загружена успешно');
      debugPrint('Входные тензоры: $inputTensors');
      debugPrint('Выходные тензоры: $outputTensors');

      setState(() {
        _isModelLoaded = true;
        _isLoading = false;
      });
      
    } catch (e) {
      debugPrint('Ошибка загрузки модели: $e');
      setState(() {
        _cameraError = 'Ошибка загрузки ИИ-модели: ${e.toString()}\nУбедитесь, что файл $_modelPath существует в папке assets';
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isLoading = true;
      _cameraError = '';
    });

    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('Камеры не найдены');
      }

      final CameraDescription camera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.high, // Используем medium для лучшей производительности
        enableAudio: false,
      );

      await _controller!.initialize();

      setState(() {
        _isLoading = false;
        _isCameraActive = true;
      });

      _startRealTimeDetection();

    } catch (e) {
      debugPrint('Ошибка инициализации камеры: $e');
      setState(() {
        _isLoading = false;
        _cameraError = 'Ошибка доступа к камере: ${e.toString()}\nУбедитесь, что вы разрешили доступ к камере.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safe Way'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _stopCamera();
            Navigator.pop(context);
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildCameraArea(),
          ),
          _buildControlPanel(),
        ],
      ),
    );
  }

  Widget _buildCameraArea() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Инициализация камеры и ИИ-модели...'),
          ],
        ),
      );
    }

    if (_cameraError.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _cameraError,
              style: const TextStyle(fontSize: 16, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _initializeApp,
              child: const Text('Попробовать снова'),
            ),
          ],
        ),
      );
    }

    if (!_isCameraActive || _controller == null || !_controller!.value.isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt, size: 100, color: Colors.blue),
            const SizedBox(height: 20),
            Text(
              _isModelLoaded ? 'ИИ-модель загружена' : 'Загрузка ИИ-модели...',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Нажмите "Активировать камеру" для начала\nнавигационной помощи с реальным ИИ-анализом',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _initializeCamera,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Активировать камеру'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
          ],
        ),
      );
    }

    return _buildRealCameraView();
  }

  Widget _buildRealCameraView() {
    return Stack(
      children: [
        CameraPreview(_controller!),
        _buildObjectOverlay(),
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
                const Icon(Icons.videocam, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'LIVE | Объектов: ${_detectedObjects.length} | Кадр: $_frameCounter',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildObjectOverlay() {
    return IgnorePointer(
      child: CustomPaint(
        painter: ObjectDetectionPainter(_detectedObjects),
        size: Size.infinite,
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.transparent, //Colors.grey[100],
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
                  backgroundColor: _isVoiceEnabled ? Colors.lightGreen : Colors.red,
                ),
              ),
              IconButton(
                iconSize: 50,
                onPressed: _toggleSound,
                icon: Icon(_isSoundEnabled ? Icons.music_note : Icons.music_off),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isSoundEnabled ? Colors.lightGreen : Colors.red,
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
                  _buildStatusChip('КАМЕРА', _isCameraActive ? Colors.blue : Colors.orange),
                  const SizedBox(width: 5),
                  _buildStatusChip('ИИ', _isModelLoaded ? Colors.blue : Colors.red),
                  const SizedBox(width: 5),
                  _buildStatusChip('ГОЛОС', _isVoiceEnabled ? Colors.blue : Colors.red),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

  void _startRealTimeDetection() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_isCameraActive && !_isProcessing) {
        _frameCounter++;
        _processRealFrame();
      }
    });
  }

  Future<void> _processRealFrame() async {
    if (_controller == null || 
        !_controller!.value.isInitialized || 
        _interpreter == null ||
        _isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    XFile? imageFile;
    
    try {
      imageFile = await _controller!.takePicture();
      final bytes = await imageFile.readAsBytes();
      
      final image = img.decodeImage(bytes);
      if (image == null) {
        debugPrint('Не удалось декодировать изображение');
        return;
      }

      final input = _preprocessImage(image);
      final output = await _runInference(input);
      final objects = _processOutput(output, image.width, image.height);
      
      if (mounted) {
        setState(() {
          _detectedObjects.clear();
          _detectedObjects.addAll(objects);
        });
      }

    } catch (e) {
      debugPrint('Ошибка обработки кадра: $e');
    } finally {
      await _deleteImageFile(imageFile);
      
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _deleteImageFile(XFile? imageFile) async {
    if (imageFile == null) return;
    
    try {
      final file = File(imageFile.path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Ошибка удаления временного файла: $e');
    }
  }

  List<Uint8List> _preprocessImage(img.Image image) {
    final resizedImage = img.copyResize(image, width: 300, height: 300);
    
    // Только контраст без sharpen
    final enhancedImage = img.adjustColor(resizedImage, contrast: 1.2);
    
    final inputBytes = Uint8List(300 * 300 * 3);
    int index = 0;
    
    for (int y = 0; y < 300; y++) {
      for (int x = 0; x < 300; x++) {
        final pixel = enhancedImage.getPixel(x, y);
        inputBytes[index++] = (pixel.r).clamp(0, 255).toInt();
        inputBytes[index++] = (pixel.g).clamp(0, 255).toInt();
        inputBytes[index++] = (pixel.b).clamp(0, 255).toInt();
      }
    }
    return [inputBytes];
  }

  Future<List<List<dynamic>>> _runInference(List<Uint8List> input) async {
    try {
      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();
      
      final outputShapes = outputTensors.map((tensor) => tensor.shape).toList();
      final outputs = <List<dynamic>>[];
      
      for (var shape in outputShapes) {
        final size = shape.reduce((a, b) => a * b);
        outputs.add(List.filled(size, 0.0).reshape(shape));
      }
      
      final outputMap = <int, Object>{};
      for (int i = 0; i < outputs.length; i++) {
        outputMap[i] = outputs[i];
      }
      
      _interpreter!.runForMultipleInputs(input, outputMap);
      
      return outputs;
    } catch (e) {
      debugPrint('Ошибка inference: $e');
      rethrow;
    }
  }

  List<DetectedObject> _processOutput(List<List<dynamic>> output, int imageWidth, int imageHeight) {
    final objects = <DetectedObject>[];
    
    try {
      // Для SSD MobileNet выходы обычно:
      // output[0] - локации [1, N, 4]
      // output[1] - классы [1, N]
      // output[2] - уверенности [1, N]
      // output[3] - количество обнаружений [1]
      
      final numDetections = min(output[3][0].toInt() as int, 10); // Ограничиваем количество
      
      for (int i = 0; i < numDetections; i++) {
        try {
          final score = output[2][0][i].toDouble();
          
          if (score > _confidenceThreshold && score.isFinite) {
            final classIndex = output[1][0][i].toInt();
            final englishLabel = _getEnglishLabel(classIndex);
            final russianLabel = _russianLabels[englishLabel] ?? englishLabel;
            
            if (russianLabel != '???' && russianLabel != 'Unknown') {
              // Получаем координаты bounding box
              final ymin = output[0][0][i][0].toDouble();
              final xmin = output[0][0][i][1].toDouble();
              final ymax = output[0][0][i][2].toDouble();
              final xmax = output[0][0][i][3].toDouble();
              
              // Конвертируем в пиксели
              final left = (xmin * imageWidth).clamp(0, imageWidth.toDouble());
              final top = (ymin * imageHeight).clamp(0, imageHeight.toDouble());
              final right = (xmax * imageWidth).clamp(0, imageWidth.toDouble());
              final bottom = (ymax * imageHeight).clamp(0, imageHeight.toDouble());
              
              final width = right - left;
              final height = bottom - top;
              
              // Фильтруем слишком маленькие объекты
              if (width > 20 && height > 20 && width < imageWidth * 0.8 && height < imageHeight * 0.8) {
                final objectType = _getObjectType(englishLabel);
                final distance = _estimateDistance(objectType, width);
                final direction = _estimateDirection(left, right, imageWidth);
                
                objects.add(DetectedObject(
                  name: russianLabel,
                  distance: distance,
                  direction: direction,
                  type: objectType,
                  boundingBox: Rect.fromLTRB(left, top, right, bottom),
                  confidence: score,
                  imageWidth: imageWidth.toDouble(),
                  imageHeight: imageHeight.toDouble(),
                ));
                
                debugPrint('Обнаружен: $russianLabel (${score.toStringAsFixed(2)})');
              }
            }
          }
        } catch (e) {
          debugPrint('Ошибка обработки объекта $i: $e');
        }
      }
    } catch (e) {
      debugPrint('Ошибка обработки вывода модели: $e');
    }
    
    return _applyNMS(objects, 0.3);
  }

  // Получаем английское название по индексу класса
  String _getEnglishLabel(int classIndex) {
    // COCO dataset labels (91 classes)
    final List<String> cocoLabels = [
      'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train', 'truck', 'boat',
      'traffic light', 'fire hydrant', 'stop sign', 'parking meter', 'bench', 'bird', 'cat',
      'dog', 'horse', 'sheep', 'cow', 'elephant', 'bear', 'zebra', 'giraffe', 'backpack',
      'umbrella', 'handbag', 'tie', 'suitcase', 'frisbee', 'skis', 'snowboard', 'sports ball',
      'kite', 'baseball bat', 'baseball glove', 'skateboard', 'surfboard', 'tennis racket',
      'bottle', 'wine glass', 'cup', 'fork', 'knife', 'spoon', 'bowl', 'banana', 'apple',
      'sandwich', 'orange', 'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake',
      'chair', 'couch', 'potted plant', 'bed', 'dining table', 'toilet', 'tv', 'laptop',
      'mouse', 'remote', 'keyboard', 'cell phone', 'microwave', 'oven', 'toaster', 'sink',
      'refrigerator', 'book', 'clock', 'vase', 'scissors', 'teddy bear', 'hair drier', 'toothbrush'
    ];
    
    return classIndex < cocoLabels.length ? cocoLabels[classIndex] : 'Unknown';
  }

  List<DetectedObject> _applyNMS(List<DetectedObject> objects, double iouThreshold) {
    objects.sort((a, b) => b.confidence.compareTo(a.confidence));
    
    final filtered = <DetectedObject>[];
    
    for (final obj in objects) {
      bool overlap = false;
      
      for (final kept in filtered) {
        final iou = _calculateIOU(obj.boundingBox, kept.boundingBox);
        if (iou > iouThreshold) {
          overlap = true;
          break;
        }
      }
      
      if (!overlap) {
        filtered.add(obj);
      }
    }
    
    return filtered;
  }

  double _calculateIOU(Rect a, Rect b) {
    final intersectionLeft = max(a.left, b.left);
    final intersectionTop = max(a.top, b.top);
    final intersectionRight = min(a.right, b.right);
    final intersectionBottom = min(a.bottom, b.bottom);
    
    if (intersectionRight < intersectionLeft || intersectionBottom < intersectionTop) {
      return 0.0;
    }
    
    final intersectionArea = (intersectionRight - intersectionLeft) * (intersectionBottom - intersectionTop);
    final unionArea = a.width * a.height + b.width * b.height - intersectionArea;
    
    return intersectionArea / unionArea;
  }

  ObjectType _getObjectType(String englishLabel) {
    switch (englishLabel.toLowerCase()) {
      case 'person':
        return ObjectType.person;
      case 'car':
      case 'truck':
      case 'bus':
      case 'motorcycle':
      case 'bicycle':
        return ObjectType.car;
      case 'chair':
        return ObjectType.chair;
      case 'dining table':
        return ObjectType.table;
      case 'door':
        return ObjectType.door;
      default:
        return ObjectType.person;
    }
  }

  double _estimateDistance(ObjectType type, double pixelWidth) {
    if (!pixelWidth.isFinite || pixelWidth <= 0) {
      return 10.0;
    }
    
    final realWidth = _getObjectWidth(type);
    const focalLength = 800.0; // Подбираем фокусное расстояние
    final distance = (realWidth * focalLength) / pixelWidth;
    
    return (distance.clamp(0.5, 30.0) * 10).round() / 10.0;
  }

  double _getObjectWidth(ObjectType type) {
    switch (type) {
      case ObjectType.person: return 0.5;
      case ObjectType.door: return 0.9;
      case ObjectType.chair: return 0.5;
      case ObjectType.table: return 1.0;
      case ObjectType.car: return 1.8;
    }
  }

  String _estimateDirection(double left, double right, int imageWidth) {
    final centerX = (left + right) / 2;
    final normalizedX = centerX / imageWidth;
    
    if (normalizedX < 0.3) return 'слева';
    if (normalizedX > 0.7) return 'справа';
    return 'прямо';
  }

  void _stopCamera() {
    WakelockPlus.disable();
    _detectionTimer?.cancel();
    _detectionTimer = null;
    _voiceTimer?.cancel();
    _voiceTimer = null;
    _flutterTts?.stop();

    if (_controller != null) {
      _controller!.dispose();
      _controller = null;
    }

    if (_interpreter != null) {
      _interpreter!.close();
      _interpreter = null;
    }

    setState(() {
      _isCameraActive = false;
      _isModelLoaded = false;
      _detectedObjects.clear();
      _frameCounter = 0;
    });
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }
}

// Остальные классы остаются без изменений
enum ObjectType { person, door, chair, table, car }

class DetectedObject {
  final String name;
  final double distance;
  final String direction;
  final ObjectType type;
  final Rect boundingBox;
  final double confidence;
  final double imageWidth;
  final double imageHeight;

  const DetectedObject({
    required this.name,
    required this.distance,
    required this.direction,
    required this.type,
    required this.boundingBox,
    required this.confidence,
    required this.imageWidth,
    required this.imageHeight,
  });
}

class ObjectDetectionPainter extends CustomPainter {
  final List<DetectedObject> objects;

  ObjectDetectionPainter(this.objects);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (final obj in objects) {
      if (obj.distance < 2.0) {
        paint.color = Colors.red;
      } else if (obj.distance < 5.0) {
        paint.color = Colors.orange;
      } else {
        paint.color = Colors.green;
      }

      final scaleX = size.width / obj.imageWidth;
      final scaleY = size.height / obj.imageHeight;

      final rect = Rect.fromLTWH(
        obj.boundingBox.left * scaleX,
        obj.boundingBox.top * scaleY,
        obj.boundingBox.width * scaleX,
        obj.boundingBox.height * scaleY,
      );
      
      canvas.drawRect(rect, paint);

      final text = '${obj.name} ${obj.distance.toStringAsFixed(1)}м ${obj.confidence}';
      textPainter.text = TextSpan(
        text: text,
        style: textStyle,
      );
      
      textPainter.layout();
      
      final textBackground = Rect.fromLTWH(
        rect.left,
        rect.top - textPainter.height - 4,
        textPainter.width + 8,
        textPainter.height + 4,
      );
      
      final backgroundPaint = Paint()
        ..color = const Color(0xB3000000)
        ..style = PaintingStyle.fill;
      
      canvas.drawRect(textBackground, backgroundPaint);
      
      textPainter.paint(
        canvas,
        Offset(rect.left + 4, rect.top - textPainter.height - 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}