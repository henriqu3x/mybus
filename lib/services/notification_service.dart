import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  // Singleton
  static final NotificationService _instance =
      NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Inicialização obrigatória
  Future<void> init() async {
    if (_initialized) return;
    
    // Web safe-guard: Do not initialize Android/local notifications on Web
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    // Timezone
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.local);

    // Init Android
    const androidInit = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initSettings = InitializationSettings(
      android: androidInit,
    );

    await _plugin.initialize(initSettings);

    // Criação explícita do canal (OBRIGATÓRIO)
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'bus_alerts',
        'Bus Alerts',
        description: 'Notifications for bus planning alerts',
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  /// Permissão (Android 13+)
  Future<bool> requestPermissions() async {
    if (kIsWeb) return true; // Pretend permission granted

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final granted =
        await androidPlugin?.requestNotificationsPermission();

    return granted ?? false;
  }

  /// Agendamento simples (SEM alarme exato)
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (!_initialized) await init();
    if (kIsWeb) return; // No-op on web

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'bus_alerts',
          'Bus Alerts',
          channelDescription:
              'Notifications for bus planning alerts',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexact,
      matchDateTimeComponents: null,
    );
  }

  /// Cancelar uma notificação
  Future<void> cancel(int id) async {
    if (kIsWeb) return;
    await _plugin.cancel(id);
  }

  /// Cancelar todas
  Future<void> cancelAll() async {
     if (kIsWeb) return;
    await _plugin.cancelAll();
  }
  /// Mostrar notificação imediata
  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();
    if (kIsWeb) return; // No-op on web

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'bus_alerts',
          'Bus Alerts',
          channelDescription: 'Notifications for bus planning alerts',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
