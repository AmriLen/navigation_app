// camera_screen.dart с YOLO
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_tts/flutter_tts.dart';

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
  
  // YOLO настройки
  static const String _modelPath = 'assets/yolov5s.tflite'; // или yolov4, yolov8
  static const double _confidenceThreshold = 0.5;
  static const double _nmsThreshold = 0.4;
  static const int _inputSize = 416; // YOLO стандартный размер
  
  // Добавляем переменные для озвучивания
  FlutterTts? _flutterTts;
  bool _isVoiceEnabled = true;
  Timer? _voiceTimer;
  Set<String> _announcedObjects = {};
  DateTime _lastVoiceTime = DateTime.now();

  // Словарь меток COCO для YOLO (80 классов)
  static const Map<int, String> _cocoLabels = {
    0: 'person', 1: 'bicycle', 2: 'car', 3: 'motorcycle', 4: 'airplane',
    5: 'bus', 6: 'train', 7: 'truck', 8: 'boat', 9: 'traffic light',
    10: 'fire hydrant', 11: 'stop sign', 12: 'parking meter', 13: 'bench',
    14: 'bird', 15: 'cat', 16: 'dog', 17: 'horse', 18: 'sheep', 19: 'cow',
    20: 'elephant', 21: 'bear', 22: 'zebra', 23: 'giraffe', 24: 'backpack',
    25: 'umbrella', 26: 'handbag', 27: 'tie', 28: 'suitcase', 29: 'frisbee',
    30: 'skis', 31: 'snowboard', 32: 'sports ball', 33: 'kite', 34: 'baseball bat',
    35: 'baseball glove', 36: 'skateboard', 37: 'surfboard', 38: 'tennis racket',
    39: 'bottle', 40: 'wine glass', 41: 'cup', 42: 'fork', 43: 'knife',
    44: 'spoon', 45: 'bowl', 46: 'banana', 47: 'apple', 48: 'sandwich',
    49: 'orange', 50: 'broccoli', 51: 'carrot', 52: 'hot dog', 53: 'pizza',
    54: 'donut', 55: 'cake', 56: 'chair', 57: 'couch', 58: 'potted plant',
    59: 'bed', 60: 'dining table', 61: 'toilet', 62: 'tv', 63: 'laptop',
    64: 'mouse', 65: 'remote', 66: 'keyboard', 67: 'cell phone', 68: 'microwave',
    69: 'oven', 70: 'toaster', 71: 'sink', 72: 'refrigerator', 73: 'book',
    74: 'clock', 75: 'vase', 76: 'scissors', 77: 'teddy bear', 78: 'hair drier',
    79: 'toothbrush'
  };

  // Русские названия
  static const Map<String, String> _russianLabels = {
    'person': 'Человек',
    'bicycle': 'Велосипед',
    'car': 'Автомобиль',
    'motorcycle': 'Мотоцикл',
    'airplane': 'Самолет',
    'bus': 'Автобус',
    'train': 'Поезд',
    'truck': 'Грузовик',
    'boat': 'Лодка',
    'traffic light': 'Светофор',
    'fire hydrant': 'Пожарный гидрант',
    'stop sign': 'Знак стоп',
    'parking meter': 'Парковочный счетчик',
    'bench': 'Скамейка',
    'bird': 'Птица',
    'cat': 'Кошка',
    'dog': 'Собака',
    'horse': 'Лошадь',
    'sheep': 'Овца',
    'cow': 'Корова',
    'elephant': 'Слон',
    'bear': 'Медведь',
    'zebra': 'Зебра',
    'giraffe': 'Жираф',
    'backpack': 'Рюкзак',
    'umbrella': 'Зонт',
    'handbag': 'Сумка',
    'tie': 'Галстук',
    'suitcase': 'Чемодан',
    'frisbee': 'Фрисби',
    'skis': 'Лыжи',
    'snowboard': 'Сноуборд',
    'sports ball': 'Мяч',
    'kite': 'Воздушный змей',
    'baseball bat': 'Бейсбольная бита',
    'baseball glove': 'Бейсбольная перчатка',
    'skateboard': 'Скейтборд',
    'surfboard': 'Доска для серфинга',
    'tennis racket': 'Теннисная ракетка',
    'bottle': 'Бутылка',
    'wine glass': 'Бокал',
    'cup': 'Чашка',
    'fork': 'Вилка',
    'knife': 'Нож',
    'spoon': 'Ложка',
    'bowl': 'Миска',
    'banana': 'Банан',
    'apple': 'Яблоко',
    'sandwich': 'Сэндвич',
    'orange': 'Апельсин',
    'broccoli': 'Брокколи',
    'carrot': 'Морковь',
    'hot dog': 'Хот-дог',
    'pizza': 'Пицца',
    'donut': 'Пончик',
    'cake': 'Торт',
    'chair': 'Стул',
    'couch': 'Диван',
    'potted plant': 'Растение в горшке',
    'bed': 'Кровать',
    'dining table': 'Стол',
    'toilet': 'Унитаз',
    'tv': 'Телевизор',
    'laptop': 'Ноутбук',
    'mouse': 'Мышь',
    'remote': 'Пульт',
    'keyboard': 'Клавиатура',
    'cell phone': 'Телефон',
    'microwave': 'Микроволновка',
    'oven': 'Духовка',
    'toaster': 'Тостер',
    'sink': 'Раковина',
    'refrigerator': 'Холодильник',
    'book': 'Книга',
    'clock': 'Часы',
    'vase': 'Ваза',
    'scissors': 'Ножницы',
    'teddy bear': 'Плюшевый мишка',
    'hair drier': 'Фен',
    'toothbrush': 'Зубная щетка',
  };

  // Приоритетные объекты для навигации
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
  }

  Future<void> _initializeTTS() async {
    _flutterTts = FlutterTts();
    
    try {
      await _flutterTts?.setLanguage("ru-RU");
      await _flutterTts?.setSpeechRate(0.5);
      await _flutterTts?.setVolume(1.0);
      await _flutterTts?.setPitch(1.0);
      
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
    
    _voiceTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_isVoiceEnabled && _detectedObjects.isNotEmpty && mounted) {
        _announceObjects();
      }
    });
  }

  // 🔄 ОСНОВНЫЕ ИЗМЕНЕНИЯ ДЛЯ YOLO НАЧИНАЮТСЯ ЗДЕСЬ

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

      // Получаем информацию о входных/выходных тензорах
      var inputTensors = _interpreter!.getInputTensors();
      var outputTensors = _interpreter!.getOutputTensors();
      
      debugPrint('YOLO модель загружена успешно');
      debugPrint('Входные тензоры: $inputTensors');
      debugPrint('Выходные тензоры: $outputTensors');

      setState(() {
        _isModelLoaded = true;
        _isLoading = false;
      });
      
    } catch (e) {
      debugPrint('Ошибка загрузки YOLO модели: $e');
      setState(() {
        _cameraError = 'Ошибка загрузки YOLO модели: ${e.toString()}\nУбедитесь, что файл $_modelPath существует в папке assets';
        _isLoading = false;
      });
    }
  }

  // 🎯 ПРЕДОБРАБОТКА ДЛЯ YOLO
// Измените сигнатуру метода если нужно возвращать Float32List
List<Uint8List> _preprocessImageForYOLO(img.Image image) {
  // Ресайз до размера YOLO
  final resizedImage = img.copyResize(image, width: _inputSize, height: _inputSize);
  
  // Создаем байтовый буфер для RGB данных
  final inputBytes = Uint8List(_inputSize * _inputSize * 3);
  int index = 0;
  
  for (int y = 0; y < _inputSize; y++) {
    for (int x = 0; x < _inputSize; x++) {
      // Получаем цвет пикселя и преобразуем в RGB компоненты
      final color = resizedImage.getPixel(x, y);
      
      // Используем методы для получения RGB компонентов
      final r = img.getRed(color);
      final g = img.getGreen(color);
      final b = img.getBlue(color);
      
      inputBytes[index++] = r;
      inputBytes[index++] = g;
      inputBytes[index++] = b;
    }
  }
  
  return [inputBytes];
}
  // 🎯 ЗАПУСК YOLO INFERENCE
  Future<List<List<dynamic>>> _runYOLOInference(List<Uint8List> input) async {
    try {
      // Для YOLO обычно один выходной тензор [1, N, 85]
      // где 85 = [x, y, w, h, confidence, class_probabilities...]
      final outputTensors = _interpreter!.getOutputTensors();
      final outputs = <List<dynamic>>[];
      
      for (var tensor in outputTensors) {
        final shape = tensor.shape;
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
      debugPrint('Ошибка YOLO inference: $e');
      rethrow;
    }
  }

  // 🎯 ОБРАБОТКА ВЫХОДА YOLO
  List<DetectedObject> _processYOLOOutput(List<List<dynamic>> output, int imageWidth, int imageHeight) {
    final objects = <DetectedObject>[];
    
    try {
      // YOLO выход обычно в формате [1, N, 85]
      final predictions = output[0][0];
      
      for (int i = 0; i < predictions.length; i++) {
        try {
          final prediction = predictions[i];
          
          // Извлекаем уверенность
          final confidence = prediction[4].toDouble();
          
          if (confidence > _confidenceThreshold) {
            // Находим класс с максимальной вероятностью
            double maxClassScore = 0;
            int classId = 0;
            
            for (int j = 5; j < prediction.length; j++) {
              final score = prediction[j].toDouble();
              if (score > maxClassScore) {
                maxClassScore = score;
                classId = j - 5;
              }
            }
            
            final finalScore = confidence * maxClassScore;
            
            if (finalScore > _confidenceThreshold) {
              final englishLabel = _cocoLabels[classId] ?? 'Unknown';
              final russianLabel = _russianLabels[englishLabel] ?? englishLabel;
              
              if (russianLabel != 'Unknown') {
                // Извлекаем bounding box (YOLO формат: center_x, center_y, width, height)
                final x = prediction[0].toDouble();
                final y = prediction[1].toDouble();
                final w = prediction[2].toDouble();
                final h = prediction[3].toDouble();
                
                // Конвертируем в координаты углов
                final left = (x - w / 2) * imageWidth;
                final top = (y - h / 2) * imageHeight;
                final right = (x + w / 2) * imageWidth;
                final bottom = (y + h / 2) * imageHeight;
                
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
                    boundingBox: Rect.fromLTRB(
                      left.clamp(0, imageWidth.toDouble()),
                      top.clamp(0, imageHeight.toDouble()),
                      right.clamp(0, imageWidth.toDouble()),
                      bottom.clamp(0, imageHeight.toDouble()),
                    ),
                    confidence: finalScore,
                    imageWidth: imageWidth.toDouble(),
                    imageHeight: imageHeight.toDouble(),
                  ));
                  
                  debugPrint('YOLO обнаружен: $russianLabel (${finalScore.toStringAsFixed(2)})');
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Ошибка обработки предсказания $i: $e');
        }
      }
    } catch (e) {
      debugPrint('Ошибка обработки вывода YOLO: $e');
    }
    
    return _applyNMS(objects, _nmsThreshold);
  }

  // 🔄 ОБНОВЛЕННЫЙ МЕТОД ОБРАБОТКИ КАДРА
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

      // 🔄 ИСПОЛЬЗУЕМ YOLO ВМЕСТО SSD
      final input = _preprocessImageForYOLO(image);
      final output = await _runYOLOInference(input);
      final objects = _processYOLOOutput(output, image.width, image.height);
      
      if (mounted) {
        setState(() {
          _detectedObjects.clear();
          _detectedObjects.addAll(objects);
        });
      }

    } catch (e) {
      debugPrint('Ошибка обработки кадра YOLO: $e');
    } finally {
      await _deleteImageFile(imageFile);
      
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // 🔄 ОСТАЛЬНЫЕ МЕТОДЫ ОСТАЮТСЯ ПРЕЖНИМИ (с небольшими адаптациями)

   Future<void> _initializeApp() async {
    await _loadModel();
    await _initializeCamera();
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

      final camera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
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
        _cameraError = 'Ошибка доступа к камере: ${e.toString()}';
      });
    }
  }

  void _startRealTimeDetection() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (_isCameraActive && !_isProcessing) {
        _frameCounter++;
        _processRealFrame();
      }
    });
  }

  // 🔄 ОБНОВЛЯЕМ ИНФОРМАЦИЮ В ИНТЕРФЕЙСЕ
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
                    'YOLO LIVE | Объектов: ${_detectedObjects.length} | Кадр: $_frameCounter | ИИ: ${_isModelLoaded ? "YOLO АКТИВЕН" : "ОФФЛАЙН"} | Голос: ${_isVoiceEnabled ? "ВКЛ" : "ВЫКЛ"}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 🔄 ОСТАЛЬНЫЕ МЕТОДЫ ОЗВУЧИВАНИЯ И ИНТЕРФЕЙСА ОСТАЮТСЯ ПРЕЖНИМИ

  // ... (остальные методы остаются без изменений)

  Future<void> _announceObjects() async {
    if (!_isVoiceEnabled || _flutterTts == null || !mounted) return;
    
    final now = DateTime.now();
    if (now.difference(_lastVoiceTime).inSeconds < 3) return; // Увеличили интервал
    
    try {
      final objectsToAnnounce = _detectedObjects
          .where((obj) => obj.distance < 8.0)
          .where((obj) => _isPriorityObject(obj.name))
          .where((obj) => !_announcedObjects.contains(_getObjectKey(obj)))
          .where((obj) => obj.confidence > 0.5)
          .toList();
      
      if (objectsToAnnounce.isNotEmpty) {
        objectsToAnnounce.sort((a, b) {
          final priorityA = _getObjectPriority(a.name);
          final priorityB = _getObjectPriority(b.name);
          if (priorityA != priorityB) {
            return priorityB.compareTo(priorityA);
          }
          return a.distance.compareTo(b.distance);
        });
        
        final nearestObject = objectsToAnnounce.first;
        
        if (_shouldAnnounceObject(nearestObject)) {
          final announcement = _generateAnnouncement(nearestObject);
          
          debugPrint('YOLO озвучивание: $announcement');
          
          await _flutterTts!.speak(announcement);
          _announcedObjects.add(_getObjectKey(nearestObject));
          _lastVoiceTime = DateTime.now();
          
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

  bool _isPriorityObject(String objectName) {
    final englishName = _russianLabels.entries
        .firstWhere((entry) => entry.value == objectName, orElse: () => MapEntry('', ''))
        .key;
    return _priorityObjects.contains(englishName) || objectName.contains('человек') || objectName.contains('авто');
  }

  int _getObjectPriority(String objectName) {
    final englishName = _russianLabels.entries
        .firstWhere((entry) => entry.value == objectName, orElse: () => MapEntry('', ''))
        .key;
    
    if (englishName == 'person') return 100;
    if (['car', 'truck', 'bus', 'motorcycle'].contains(englishName)) return 90;
    if (['chair', 'table', 'door'].contains(englishName)) return 80;
    if (['stairs', 'wall'].contains(englishName)) return 70;
    return 50;
  }

  String _generateAnnouncement(DetectedObject obj) {
    String distanceText;
    
    if (obj.distance < 1.5) {
      distanceText = 'очень близко';
    } else if (obj.distance < 3.0) {
      distanceText = 'близко';
    } else if (obj.distance < 6.0) {
      distanceText = 'впереди';
    } else {
      distanceText = 'далеко';
    }
    
    if (obj.distance < 2.0) {
      return 'Внимание! ${obj.name} $distanceText ${obj.direction}';
    }
    
    return '${obj.name} $distanceText';
  }

  String _getObjectKey(DetectedObject obj) {
    return '${obj.name}_${obj.direction}_${(obj.distance ~/ 0.5)}';
  }

  bool _shouldAnnounceObject(DetectedObject obj) {
    if (obj.confidence < 0.5) return false;
    if (obj.distance < 3.0) return true;
    if (obj.distance >= 3.0) {
      return _getObjectPriority(obj.name) >= 70;
    }
    return true;
  }

  void _toggleVoice() {
    setState(() {
      _isVoiceEnabled = !_isVoiceEnabled;
    });
    
    if (_isVoiceEnabled) {
      _announcedObjects.clear();
    } else {
      _flutterTts?.stop();
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isVoiceEnabled ? 
          'Озвучивание включено' : 'Озвучивание выключено'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // 🔄 ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ДЛЯ YOLO

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
    const focalLength = 800.0;
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

  void _manualDetection() {
    if (_isCameraActive) {
      _processRealFrame();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('YOLO ручное сканирование: ${_detectedObjects.length} объектов'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _checkDangers() {
    final dangers = _detectedObjects.where((obj) => obj.distance < 2.0).toList();

    if (dangers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Прямых опасностей не обнаружено'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 10),
              Text('YOLO: Обнаружены близкие объекты'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final danger in dangers.take(5))
                Text('• ${danger.name} в ${danger.distance.toStringAsFixed(1)}м (${danger.direction})'),
              const SizedBox(height: 10),
              const Text('Рекомендуется осторожность при движении.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Понятно'),
            ),
          ],
        ),
      );
    }
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

  // 🔄 ОСТАЛЬНАЯ ЧАСТЬ ИНТЕРФЕЙСА ОСТАЕТСЯ ПРЕЖНЕЙ

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Навигационный помощник - YOLO Камера'),
        backgroundColor: Colors.blue,
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
            Text('Инициализация YOLO камеры...'),
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
              _isModelLoaded ? 'YOLO модель загружена' : 'Загрузка YOLO модели...',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Нажмите "Активировать камеру" для начала\nнавигационной помощи с YOLO ИИ-анализом',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _initializeCamera,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Активировать YOLO камеру'),
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
      color: Colors.grey[100],
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Статус:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  _buildStatusChip('КАМЕРА', _isCameraActive ? Colors.green : Colors.orange),
                  const SizedBox(width: 5),
                  _buildStatusChip('YOLO', _isModelLoaded ? Colors.green : Colors.red),
                  const SizedBox(width: 5),
                  _buildStatusChip('ГОЛОС', _isVoiceEnabled ? Colors.green : Colors.grey),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: _toggleVoice,
                icon: Icon(_isVoiceEnabled ? Icons.volume_up : Icons.volume_off),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isVoiceEnabled ? Colors.blue : Colors.grey,
                ),
              ),
              IconButton(
                onPressed: _isCameraActive ? _manualDetection : null,
                icon: const Icon(Icons.visibility),
              ),
              IconButton(
                onPressed: _isCameraActive ? _checkDangers : null,
                icon: const Icon(Icons.warning),
              ),
            ],
          ),
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
}

// Классы для объектов остаются прежними
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
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 3;
    final textStyle = TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

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

      final text = '${obj.name} ${obj.distance.toStringAsFixed(1)}м';
      textPainter.text = TextSpan(text: text, style: textStyle);
      textPainter.layout();
      
      final textBackground = Rect.fromLTWH(
        rect.left,
        rect.top - textPainter.height - 4,
        textPainter.width + 8,
        textPainter.height + 4,
      );
      
      final backgroundPaint = Paint()..color = Color(0xB3000000)..style = PaintingStyle.fill;
      canvas.drawRect(textBackground, backgroundPaint);
      
      textPainter.paint(canvas, Offset(rect.left + 4, rect.top - textPainter.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}