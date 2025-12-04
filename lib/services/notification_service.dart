// lib/services/notification_service.dart

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:vibration/vibration.dart';

class NotificationService {
  // 1. Singleton Pattern para garantir uma única instância
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // 2. Inicialização do Serviço
  Future<void> init() async {
    // Inicializa os dados de fusos horários
    tz.initializeTimeZones();
    // Define o timezone local para Fortaleza (Ceará, Brasil)
    tz.setLocalLocation(tz.getLocation('America/Fortaleza'));

    // Configurações para Android
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  // 3. Solicitação de Permissões (necessária para Android 13+)
  Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.requestNotificationsPermission();
  }

  // 4. Agendamento da Notificação
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      // Converte DateTime para TZDateTime usando o fuso horário local
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'bus_alerts',
          'Bus Alerts',
          channelDescription: 'Notifications for bus arrivals',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // O parâmetro 'uiLocalNotificationDateInterpretation' foi removido
      // conforme a correção, pois não é usado em zonedSchedule.
    );
  }

  // 5. Função de Vibração Opcional
  Future<void> triggerVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      // Padrão de vibração: 500ms ligada, 1000ms desligada, 500ms ligada, 1000ms desligada
      Vibration.vibrate(pattern: [500, 1000, 500, 1000]);
    }
  }
}