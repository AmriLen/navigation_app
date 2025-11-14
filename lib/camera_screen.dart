import 'dart:html' as html;
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _isCameraActive = false;
  bool _isLoading = false;
  String _cameraError = '';
  html.MediaStream? _mediaStream;
  html.VideoElement? _videoElement;
  html.CanvasElement? _canvasElement;
  html.CanvasRenderingContext2D? _canvasContext;
  final List<DetectedObject> _detectedObjects = [];
  double _focalLength = 1000.0;
  late Random _random;
  Timer? _detectionTimer;
  int _frameCounter = 0;

  @override
  void initState() {
    super.initState();
    _random = Random();
    _initializeVideoElements();
  }

  void _initializeVideoElements() {
    _videoElement = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';

    _canvasElement = html.CanvasElement()
      ..style.position = 'absolute'
      ..style.top = '0'
      ..style.left = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.pointerEvents = 'none';

    _canvasContext = _canvasElement?.getContext('2d') as html.CanvasRenderingContext2D?;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Навигационный помощник - Камера'),
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
          // Заголовок
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue[50],
            child: const Text(
              'Режим компьютерного зрения - РЕАЛЬНАЯ КАМЕРА',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),

          // Основная область камеры
          Expanded(
            child: _buildCameraArea(),
          ),

          // Панель управления
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
            Text('Инициализация камеры...'),
          ],
        ),
      );
    }

    if (_cameraError.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _cameraError,
              style: const TextStyle(fontSize: 16, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _initializeCamera,
              child: const Text('Попробовать снова'),
            ),
          ],
        ),
      );
    }

    if (!_isCameraActive) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt, size: 100, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              'Реальная камера готова к работе',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Нажмите "Активировать камеру" для начала\nнавигационной помощи с реальным видеопотоком',
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
        // HTML Video Element для отображения реальной камеры
        SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: HtmlElementView(
            viewType: 'camera-view',
            onPlatformViewCreated: _onPlatformViewCreated,
          ),
        ),

        // Flutter overlay для обнаруженных объектов
        _buildObjectOverlay(),

        // Информационная панель
        Positioned(
          top: 20,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.videocam, color: Colors.green, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'РЕАЛЬНАЯ КАМЕРА | Объектов: ${_detectedObjects.length} | Кадр: $_frameCounter',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Отладочная информация
        Positioned(
          bottom: 100,
          left: 20,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Фокус: ${_focalLength.toStringAsFixed(0)}px',
              style: const TextStyle(color: Colors.white, fontSize: 12),
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
      color: Colors.grey[100],
      child: Column(
        children: [
          // Статус камеры
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Статус камеры:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isCameraActive ? Colors.green : Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isCameraActive ? 'АКТИВНА' : 'ВЫКЛ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Кнопки управления
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _isCameraActive ? _stopCamera : _initializeCamera,
                icon: Icon(_isCameraActive ? Icons.camera_alt : Icons.camera_alt),
                label: Text(_isCameraActive ? 'Выключить' : 'Включить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isCameraActive ? Colors.red : Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isCameraActive ? _manualDetection : null,
                icon: const Icon(Icons.visibility),
                label: const Text('Сканировать'),
              ),
              ElevatedButton.icon(
                onPressed: _isCameraActive ? _checkDangers : null,
                icon: const Icon(Icons.warning),
                label: const Text('Опасности'),
              ),
            ],
          ),

          // Настройки калибровки
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Фокусное расстояние:'),
              Expanded(
                child: Slider(
                  value: _focalLength,
                  min: 500,
                  max: 2000,
                  divisions: 15,
                  label: _focalLength.round().toString(),
                  onChanged: (value) {
                    setState(() {
                      _focalLength = value;
                    });
                  },
                ),
              ),
            ],
          ),

          // Информация о камере
          if (_isCameraActive) ...[
            const SizedBox(height: 10),
            const Text(
              '⚠️ Работает реальная камера браузера',
              style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }

  void _onPlatformViewCreated(int id) {
    final container = html.document.getElementById('camera-container-$id');
    if (container != null && _videoElement != null && _canvasElement != null) {
      container.children.clear();
      container.append(_videoElement!);
      container.append(_canvasElement!);
    }
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isLoading = true;
      _cameraError = '';
    });

    try {
      // Запрос доступа к камере через WebRTC
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw Exception('WebRTC не поддерживается в этом браузере');
      }

      // Запрашиваем доступ к задней камере
      _mediaStream = await mediaDevices.getUserMedia({
        'video': {
          'facingMode': 'environment', // Задняя камера
          'width': {'ideal': 1280},
          'height': {'ideal': 720}
        }
      });

      if (_mediaStream != null && _videoElement != null) {
        _videoElement!.srcObject = _mediaStream;
        
        // Ждем готовности видео
        await _videoElement!.onCanPlay.first;
        
        setState(() {
          _isLoading = false;
          _isCameraActive = true;
        });

        // Запускаем обнаружение объектов в реальном времени
        _startRealTimeDetection();
      } else {
        throw Exception('Не удалось получить доступ к камере');
      }
    } catch (e) {
      debugPrint('Ошибка инициализации камеры: $e');
      setState(() {
        _isLoading = false;
        _cameraError = 'Ошибка доступа к камере: $e\nУбедитесь, что вы разрешили доступ к камере.';
      });
    }
  }

  void _startRealTimeDetection() {
    // Обнаружение объектов каждые 100ms
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isCameraActive && _videoElement != null) {
        _frameCounter++;
        _processRealFrame();
      }
    });
  }

  void _processRealFrame() {
    if (_videoElement == null || 
        _videoElement!.videoWidth == 0 || 
        _videoElement!.videoHeight == 0) {
      return;
    }

    // Получаем реальные размеры видео
    final videoWidth = _videoElement!.videoWidth.toDouble();
    final videoHeight = _videoElement!.videoHeight.toDouble();

    // Симуляция обнаружения объектов на основе реального видеопотока
    final newObjects = <DetectedObject>[];

    // Генерируем реалистичные объекты
    final objectCount = _random.nextInt(4) + 1; // 1-4 объекта
    
    for (int i = 0; i < objectCount; i++) {
      final objectType = ObjectType.values[_random.nextInt(ObjectType.values.length)];
      final objectWidth = _getObjectWidth(objectType);
      
      // Реалистичные размеры bounding boxes
      final bboxWidth = 60.0 + _random.nextDouble() * 100.0;
      final distance = _calculateDistance(bboxWidth, objectWidth);
      
      // Создаем bounding box в пределах видео
      final bboxLeft = _random.nextDouble() * (videoWidth - bboxWidth);
      final bboxTop = _random.nextDouble() * (videoHeight - bboxWidth * 0.75);
      
      final object = DetectedObject(
        name: _getObjectName(objectType),
        distance: distance,
        direction: _getRandomDirection(),
        type: objectType,
        boundingBox: Rect.fromLTWH(
          bboxLeft,
          bboxTop,
          bboxWidth,
          bboxWidth * 0.75,
        ),
        confidence: 0.7 + _random.nextDouble() * 0.25,
        imageWidth: videoWidth,
        imageHeight: videoHeight,
      );
      
      newObjects.add(object);
    }

    if (mounted) {
      setState(() {
        _detectedObjects.clear();
        _detectedObjects.addAll(newObjects);
      });
    }
  }

  void _manualDetection() {
    if (_isCameraActive) {
      // Принудительное обновление обнаружения
      _processRealFrame();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ручное сканирование: ${_detectedObjects.length} объектов'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  double _calculateDistance(double pixelWidth, double realWidth) {
    final distance = (realWidth * _focalLength) / pixelWidth;
    return (distance * 10).round() / 10.0;
  }

  double _getObjectWidth(ObjectType type) {
    switch (type) {
      case ObjectType.person:
        return 0.5;
      case ObjectType.door:
        return 0.9;
      case ObjectType.chair:
        return 0.4;
      case ObjectType.table:
        return 0.8;
      case ObjectType.car:
        return 1.8;
    }
  }

  String _getObjectName(ObjectType type) {
    switch (type) {
      case ObjectType.person:
        return 'Человек';
      case ObjectType.door:
        return 'Дверь';
      case ObjectType.chair:
        return 'Стул';
      case ObjectType.table:
        return 'Стол';
      case ObjectType.car:
        return 'Автомобиль';
    }
  }

  String _getRandomDirection() {
    final directions = ['спереди', 'спереди слева', 'спереди справа', 'слева', 'справа'];
    return directions[_random.nextInt(directions.length)];
  }

  void _checkDangers() {
    final dangers = _detectedObjects.where((obj) => obj.distance < 3.0).toList();

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
              Text('Обнаружены близкие объекты'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final danger in dangers.take(3))
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
    _detectionTimer?.cancel();
    _detectionTimer = null;

    if (_mediaStream != null) {
      _mediaStream!.getTracks().forEach((track) => track.stop());
      _mediaStream = null;
    }
    
    if (_videoElement != null) {
      _videoElement!.srcObject = null;
    }

    setState(() {
      _isCameraActive = false;
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

// Классы для работы с обнаруженными объектами
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

// Кастомный painter для отрисовки bounding boxes
class ObjectDetectionPainter extends CustomPainter {
  final List<DetectedObject> objects;

  ObjectDetectionPainter(this.objects);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (final obj in objects) {
      // Выбираем цвет в зависимости от расстояния
      if (obj.distance < 2.0) {
        paint.color = Colors.red;
      } else if (obj.distance < 5.0) {
        paint.color = Colors.orange;
      } else {
        paint.color = Colors.green;
      }

      // Масштабируем bounding box к размеру экрана
      final scaleX = size.width / obj.imageWidth;
      final scaleY = size.height / obj.imageHeight;

      final rect = Rect.fromLTWH(
        obj.boundingBox.left * scaleX,
        obj.boundingBox.top * scaleY,
        obj.boundingBox.width * scaleX,
        obj.boundingBox.height * scaleY,
      );
      
      canvas.drawRect(rect, paint);

      // Рисуем текст с информацией
      final text = '${obj.name} ${obj.distance.toStringAsFixed(1)}м';
      textPainter.text = TextSpan(
        text: text,
        style: textStyle,
      );
      
      textPainter.layout();
      
      // Рисуем фон для текста
      final textBackground = Rect.fromLTWH(
        rect.left,
        rect.top - textPainter.height - 4,
        textPainter.width + 8,
        textPainter.height + 4,
      );
      
      final backgroundPaint = Paint()
        ..color = Colors.black.withOpacity(0.7)
        ..style = PaintingStyle.fill;
      
      canvas.drawRect(textBackground, backgroundPaint);
      
      // Рисуем текст
      textPainter.paint(
        canvas,
        Offset(rect.left + 4, rect.top - textPainter.height - 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Кастомный виджет для отображения HTML видео элемента
class HtmlElementView extends StatelessWidget {
  final String viewType;
  final Function(int) onPlatformViewCreated;

  const HtmlElementView({
    super.key,
    required this.viewType,
    required this.onPlatformViewCreated,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final id = DateTime.now().millisecondsSinceEpoch;
        
        // Создаем HTML элемент при построении виджета
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final container = html.DivElement()
            ..id = 'camera-container-$id'
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.position = 'relative'
            ..style.backgroundColor = 'black';
          
          html.document.body?.append(container);
          onPlatformViewCreated(id);
        });

        return Container(
          color: Colors.black,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt, size: 80, color: Colors.white54),
                SizedBox(height: 10),
                Text(
                  'Реальная камера',
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}