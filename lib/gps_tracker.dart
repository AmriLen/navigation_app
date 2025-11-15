// gps_tracker.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';

class GPSTrackerScreen extends StatefulWidget {
  const GPSTrackerScreen({super.key});

  @override
  State<GPSTrackerScreen> createState() => _GPSTrackerScreenState();
}

class _GPSTrackerScreenState extends State<GPSTrackerScreen> {
  // Состояние GPS
  bool _isTracking = false;
  bool _isLoading = false;
  bool _hasPermission = false;
  String _gpsError = '';
  Position? _currentPosition;
  List<Position> _routeHistory = [];
  // УДАЛИЛ: Timer? _trackingTimer; // Не используется
  StreamSubscription<Position>? _positionStream;
  
  // Настройки GPS
  static const LocationAccuracy _desiredAccuracy = LocationAccuracy.best;
  static const int _trackingInterval = 2; // секунды
  static const double _minimumDistance = 1.0; // метры
  
  // Навигационные данные
  double _totalDistance = 0.0;
  double _currentSpeed = 0.0;
  double _averageSpeed = 0.0;
  DateTime? _trackingStartTime;
  Position? _lastPosition;
  
  // TTS для озвучивания
  FlutterTts? _flutterTts;
  bool _isVoiceEnabled = true;
  Timer? _voiceTimer;
  DateTime _lastVoiceAnnouncement = DateTime.now();
  
  // Настройки маршрута
  Position? _destination;
  bool _hasDestination = false;
  double _distanceToDestination = 0.0;
  String _directionToDestination = '';

  @override
  void initState() {
    super.initState();
    _initializeTTS();
    _checkPermissions();
  }

  Future<void> _initializeTTS() async {
    _flutterTts = FlutterTts();
    try {
      await _flutterTts?.setLanguage("ru-RU");
      await _flutterTts?.setSpeechRate(0.5);
      await _flutterTts?.setVolume(1.0);
      await _flutterTts?.setPitch(1.0);
    } catch (e) {
      debugPrint('Ошибка инициализации TTS: $e');
    }
  }

  Future<void> _checkPermissions() async {
    setState(() {
      _isLoading = true;
      _gpsError = '';
    });

    try {
      // Проверяем разрешения
      final LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        final LocationPermission requestedPermission = await Geolocator.requestPermission();
        
        if (requestedPermission != LocationPermission.whileInUse && 
            requestedPermission != LocationPermission.always) {
          throw Exception('Разрешение на доступ к местоположению не предоставлено');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Доступ к местоположению заблокирован. Разрешите доступ в настройках устройства.');
      }

      // Проверяем доступность сервисов
      final bool isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isLocationServiceEnabled) {
        throw Exception('Службы геолокации отключены. Включите GPS для работы трекера.');
      }

      setState(() {
        _hasPermission = true;
        _isLoading = false;
      });

      // Получаем начальную позицию
      await _getCurrentPosition();

    } catch (e) {
      debugPrint('Ошибка проверки разрешений: $e');
      setState(() {
        _gpsError = e.toString();
        _isLoading = false;
        _hasPermission = false;
      });
    }
  }

  Future<void> _getCurrentPosition() async {
    if (!_hasPermission) return;

    try {
      setState(() {
        _isLoading = true;
      });

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: _desiredAccuracy,
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _isLoading = false;
          _gpsError = '';
        });
      }

    } catch (e) {
      debugPrint('Ошибка получения позиции: $e');
      if (mounted) {
        setState(() {
          _gpsError = 'Не удалось получить текущее местоположение: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  void _startTracking() {
  if (!_hasPermission || _isTracking) return;

  setState(() {
    _isTracking = true;
    _trackingStartTime = DateTime.now();
    _totalDistance = 0.0;
    _routeHistory.clear();
    _lastPosition = _currentPosition;
  });

  // Таймер для периодического обновления позиции
  Timer.periodic(Duration(seconds: _trackingInterval), (timer) async {
    if (!_isTracking || !mounted) {
      timer.cancel();
      return;
    }
    
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: _desiredAccuracy,
      );
      _updatePosition(position);
    } catch (e) {
      debugPrint('Ошибка получения позиции: $e');
    }
  });

  // Таймер для озвучивания
  _voiceTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
    if (_isVoiceEnabled && _isTracking && mounted) {
      _announceNavigationInfo();
    }
  });

  _announceNavigationInfo();
}

  void _stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _voiceTimer?.cancel();
    _voiceTimer = null;

    setState(() {
      _isTracking = false;
      _trackingStartTime = null;
      _lastPosition = null;
    });

    _speak('Отслеживание маршрута остановлено');
  }

  void _updatePosition(Position position) {
    if (!mounted) return;

    setState(() {
      _currentPosition = position;
      _currentSpeed = position.speed; // м/с
      
      // Конвертируем скорость в км/ч
      if (_currentSpeed > 0) {
        _currentSpeed = _currentSpeed * 3.6;
      }

      // Обновляем историю маршрута
      _routeHistory.add(position);

      // Рассчитываем пройденное расстояние
      if (_lastPosition != null) {
        final double distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        _totalDistance += distance;
      }

      _lastPosition = position;

      // Обновляем информацию о цели
      if (_hasDestination && _destination != null) {
        _updateDestinationInfo();
      }

      // Рассчитываем среднюю скорость
      _calculateAverageSpeed();
    });

    // Автоматическое озвучивание при значительных изменениях
    _checkForAutomaticAnnouncement();
  }

  void _updateDestinationInfo() {
    if (_currentPosition == null || _destination != null) return;

    _distanceToDestination = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _destination!.latitude,
      _destination!.longitude,
    );

    _directionToDestination = _calculateBearing(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _destination!.latitude,
      _destination!.longitude,
    );
  }

  String _calculateBearing(double startLat, double startLng, double endLat, double endLng) {
    final double startLatRad = startLat * math.pi / 180;
    final double startLngRad = startLng * math.pi / 180;
    final double endLatRad = endLat * math.pi / 180;
    final double endLngRad = endLng * math.pi / 180;

    final double y = math.sin(endLngRad - startLngRad) * math.cos(endLatRad);
    final double x = math.cos(startLatRad) * math.sin(endLatRad) - 
                    math.sin(startLatRad) * math.cos(endLatRad) * math.cos(endLngRad - startLngRad);
    
    double bearing = math.atan2(y, x);
    bearing = bearing * 180 / math.pi;
    bearing = (bearing + 360) % 360;

    if (bearing >= 337.5 || bearing < 22.5) return 'север';
    if (bearing >= 22.5 && bearing < 67.5) return 'северо-восток';
    if (bearing >= 67.5 && bearing < 112.5) return 'восток';
    if (bearing >= 112.5 && bearing < 157.5) return 'юго-восток';
    if (bearing >= 157.5 && bearing < 202.5) return 'юг';
    if (bearing >= 202.5 && bearing < 247.5) return 'юго-запад';
    if (bearing >= 247.5 && bearing < 292.5) return 'запад';
    return 'северо-запад';
  }

  void _calculateAverageSpeed() {
    if (_trackingStartTime == null) return;

    final Duration trackingDuration = DateTime.now().difference(_trackingStartTime!);
    final double hours = trackingDuration.inSeconds / 3600;

    if (hours > 0) {
      _averageSpeed = _totalDistance / 1000 / hours; // км/ч
    }
  }

  void _checkForAutomaticAnnouncement() {
    final now = DateTime.now();
    
    // Озвучиваем каждые 30 секунд или при значительных изменениях
    if (now.difference(_lastVoiceAnnouncement).inSeconds >= 30) {
      _announceNavigationInfo();
    }
    
    // Особые случаи для озвучивания
    if (_hasDestination && _distanceToDestination < 50) {
      _speak('Цель близко, осталось ${_distanceToDestination.round()} метров');
    }
    
    // Предупреждение о высокой скорости
    if (_currentSpeed > 10 && _currentSpeed < 50) { // Пешеходная скорость
      _speak('Внимание! Вы движетесь со скоростью ${_currentSpeed.round()} километров в час');
    }
  }

  void _announceNavigationInfo() {
    if (!_isVoiceEnabled || _currentPosition == null) return;

    String announcement = '';

    if (_hasDestination && _destination != null) {
      announcement = 'До цели ${_distanceToDestination.round()} метров, направление $_directionToDestination';
    } else {
      announcement = 'Скорость ${_currentSpeed.round()} километров в час, пройдено ${(_totalDistance).round()} метров';
    }

    _speak(announcement);
    _lastVoiceAnnouncement = DateTime.now();
  }

  Future<void> _speak(String text) async {
    if (!_isVoiceEnabled || _flutterTts == null) return;

    try {
      await _flutterTts!.speak(text);
    } catch (e) {
      debugPrint('Ошибка озвучивания: $e');
    }
  }

  void _setDestination() {
    if (_currentPosition == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Установить цель'),
        content: const Text('Установить текущее местоположение как цель навигации?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _destination = _currentPosition;
                _hasDestination = true;
                _updateDestinationInfo();
              });
              Navigator.pop(context);
              _speak('Цель установлена. До цели ${_distanceToDestination.round()} метров');
            },
            child: const Text('Установить'),
          ),
        ],
      ),
    );
  }

  void _clearDestination() {
    setState(() {
      _destination = null;
      _hasDestination = false;
      _distanceToDestination = 0.0;
      _directionToDestination = '';
    });
    _speak('Цель сброшена');
  }

  void _toggleVoice() {
    setState(() {
      _isVoiceEnabled = !_isVoiceEnabled;
    });
    
    if (_isVoiceEnabled) {
      _speak('Озвучивание включено');
    } else {
      _flutterTts?.stop();
    }
  }

  void _showRouteHistory() {
    if (_routeHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('История маршрута пуста')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('История маршрута'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _routeHistory.length,
            itemBuilder: (context, index) {
              final position = _routeHistory[index];
              return ListTile(
                leading: const Icon(Icons.location_on),
                title: Text('Точка ${index + 1}'),
                subtitle: Text('${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}'),
                trailing: Text('${position.timestamp}'),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Трекер'),
        backgroundColor: Colors.green,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _stopTracking();
            Navigator.pop(context);
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildGPSStatus(),
          ),
          _buildControlPanel(),
        ],
      ),
    );
  }

  Widget _buildGPSStatus() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Получение данных GPS...'),
          ],
        ),
      );
    }

    if (_gpsError.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.gps_off, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _gpsError,
              style: const TextStyle(fontSize: 16, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _checkPermissions,
              child: const Text('Попробовать снова'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _openAppSettings,
              child: const Text('Открыть настройки'),
            ),
          ],
        ),
      );
    }

    if (!_hasPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Требуется разрешение на доступ к местоположению',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _checkPermissions,
              child: const Text('Запросить разрешение'),
            ),
          ],
        ),
      );
    }

    return _buildGPSData();
  }

  Widget _buildGPSData() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Статус трекера
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isTracking ? const Color(0x1A4CAF50) : const Color(0x1A9E9E9E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isTracking ? Colors.green : Colors.grey,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  _isTracking ? Icons.gps_fixed : Icons.gps_not_fixed,
                  size: 40,
                  color: _isTracking ? Colors.green : Colors.grey,
                ),
                const SizedBox(height: 8),
                Text(
                  _isTracking ? 'Отслеживание активно' : 'Отслеживание остановлено',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _isTracking ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Основные данные GPS
          if (_currentPosition != null) ...[
            _buildDataCard(
              'Текущее местоположение',
              [
                _buildDataRow('Широта', _currentPosition!.latitude.toStringAsFixed(6)),
                _buildDataRow('Долгота', _currentPosition!.longitude.toStringAsFixed(6)),
                _buildDataRow('Точность', '±${_currentPosition!.accuracy?.round() ?? 0}м'), // ИСПРАВЛЕНО
              ],
            ),

            const SizedBox(height: 16),

            // Навигационные данные
            _buildDataCard(
              'Навигация',
              [
                _buildDataRow('Скорость', '${_currentSpeed.round()} км/ч'),
                _buildDataRow('Пройдено', '${_totalDistance.round()} м'),
                if (_trackingStartTime != null)
                  _buildDataRow('Время', '${_formatDuration(DateTime.now().difference(_trackingStartTime!))}'),
                if (_averageSpeed > 0)
                  _buildDataRow('Средняя скорость', '${_averageSpeed.round()} км/ч'),
              ],
            ),

            // Информация о цели
            if (_hasDestination && _destination != null) ...[
              const SizedBox(height: 16),
              _buildDataCard(
                'Цель навигации',
                [
                  _buildDataRow('Расстояние', '${_distanceToDestination.round()} м'),
                  _buildDataRow('Направление', _directionToDestination),
                  _buildDataRow('Координаты', 
                    '${_destination!.latitude.toStringAsFixed(6)}, ${_destination!.longitude.toStringAsFixed(6)}'),
                ],
                color: const Color(0x1A2196F3), // ИСПРАВЛЕНО
              ),
            ],

            // История маршрута
            if (_routeHistory.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildDataCard(
                'Маршрут',
                [
                  _buildDataRow('Точек маршрута', _routeHistory.length.toString()),
                  _buildDataRow('Общее расстояние', '${_totalDistance.round()} м'),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDataCard(String title, List<Widget> children, {Color? color}) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}ч ${minutes}м ${seconds}с';
    } else if (minutes > 0) {
      return '${minutes}м ${seconds}с';
    } else {
      return '${seconds}с';
    }
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.grey[100],
      child: Column(
        children: [
          // Основные кнопки управления
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Старт/стоп трекинг
              ElevatedButton.icon(
                onPressed: _hasPermission ? (_isTracking ? _stopTracking : _startTracking) : null,
                icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
                label: Text(_isTracking ? 'Стоп' : 'Старт'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isTracking ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),

              // Управление целью
              ElevatedButton.icon(
                onPressed: _hasPermission ? 
                  (_hasDestination ? _clearDestination : _setDestination) : null,
                icon: Icon(_hasDestination ? Icons.location_off : Icons.flag),
                label: Text(_hasDestination ? 'Сбросить цель' : 'Установить цель'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Дополнительные кнопки
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Озвучивание
              IconButton(
                onPressed: _toggleVoice,
                icon: Icon(_isVoiceEnabled ? Icons.volume_up : Icons.volume_off),
                style: IconButton.styleFrom(
                  backgroundColor: _isVoiceEnabled ? Colors.blue : Colors.grey,
                  foregroundColor: Colors.white,
                ),
              ),

              // Обновить позицию
              IconButton(
                onPressed: _getCurrentPosition,
                icon: const Icon(Icons.refresh),
              ),

              // История маршрута
              IconButton(
                onPressed: _showRouteHistory,
                icon: const Icon(Icons.history),
              ),

              // Настройки
              IconButton(
                onPressed: _openAppSettings,
                icon: const Icon(Icons.settings),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openAppSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      debugPrint('Ошибка открытия настроек: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть настройки')),
      );
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _voiceTimer?.cancel();
    _flutterTts?.stop();
    super.dispose();
  }
}