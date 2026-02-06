
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';


// Top-level function for the background service
@pragma('vm:entry-point')
Future<bool> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // State
  List<Map<String, dynamic>> orderedStops = [];
  int destinationIndex = -1;
  int currentStopIndex = 0;
  int? lastNotifiedStops;

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    // Listen for trip data
    service.on('setTripData').listen((event) {
      if (event != null) {
        print("Background Service: Trip Data Received");
        orderedStops = List<Map<String, dynamic>>.from(event['stops']);
        destinationIndex = event['destinationIndex'];
        currentStopIndex = event['currentIndex'];
        lastNotifiedStops = null;
      }
    });
  }

  // Helper for notifications
  Future<void> showNotification(int id, String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'mybus_foreground', 
      'MYBUS Tracking', // Reusing the same channel or use 'bus_alerts' if preferred
      importance: Importance.high,
      priority: Priority.high,
    );
     await flutterLocalNotificationsPlugin.show(
      id, title, body, const NotificationDetails(android: androidDetails),
    );
  }

  try {
     Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 3),
        // Use the same channel as the background service to keep it alive
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "No Ponto",
          notificationText: "Rastreamento ativo em segundo plano",
          notificationIcon: AndroidResource(name: 'ic_launcher'), // or your icon
          // notificationChannelId: 'mybus_foreground', // Removed invalid param
          enableWakeLock: true,
        ),
      ),
    ).listen((Position position) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.invoke(
            'update',
            {
              'lat': position.latitude,
              'lon': position.longitude,
            },
          );
          
          // --- Logic ---
          if (orderedStops.isNotEmpty && destinationIndex != -1) {
            double min = double.infinity;
            int closest = currentStopIndex;

            // Find closest stop forward from current index
            for (int i = currentStopIndex; i < orderedStops.length; i++) {
              final s = orderedStops[i];
              final d = Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                s['lat'],
                s['lon'],
              );
              if (d < min) {
                min = d;
                closest = i;
              }
            }
            
            currentStopIndex = closest;
            final remaining = destinationIndex - closest;
            final safe = remaining < 0 ? 0 : remaining;

            // Notify
            bool shouldNotify = false;
            
            // 3, 2, 1 stops remaining
            if (safe <= 3 && safe > 0) {
              if (lastNotifiedStops != safe) {
                shouldNotify = true;
                lastNotifiedStops = safe;
                await showNotification(
                  889, // Different ID than foreground service
                  'Viagem em andamento',
                  'Faltam $safe paradas para o seu destino.',
                );
              }
            }

            // Arrived
            if (safe == 0 && min < 250) {
               if (lastNotifiedStops != 0) {
                 lastNotifiedStops = 0;
                 await showNotification(
                  889,
                  'Chegando!',
                  'Prepare-se para descer.',
                );
               }
            }
            
            print("Background Logic: Remaining $safe, MinDist $min");
          }
        }
      }
    });
  } catch(e) {
    print("Background Service Error: \$e");
  }
  
  return true;
}

class BackgroundService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  static Future<void> initialize() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'mybus_foreground', // id
      'MYBUS Tracking', // title
      description: 'This channel is used for important notifications.', 
      importance: Importance.low, 
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        // This will be executed when app is in foreground or background in separated isolate
        onStart: onStart,

        // auto start service
        autoStart: false,
        isForegroundMode: true,

        notificationChannelId: 'mybus_foreground',
        initialNotificationTitle: 'No Ponto',
        initialNotificationContent: 'Rastreamento ativo em segundo plano',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onStart,
      ),
    );
  }

  static Future<void> start() async {
    var isRunning = await _service.isRunning();
    if (!isRunning) {
      _service.startService();
    }
  }

  static Future<void> stop() async {
    var isRunning = await _service.isRunning();
    if (isRunning) {
      _service.invoke("stopService");
    }
  }
  
  static Future<void> sendTripData(List<Map<String, dynamic>> stops, int destIndex, int currentIndex) async {
    _service.invoke(
      "setTripData",
      {
        "stops": stops,
        "destinationIndex": destIndex,
        "currentIndex": currentIndex,
      },
    );
  }

  static Stream<Map<String, dynamic>?> get updateStream {
    return _service.on('update');
  }
}
