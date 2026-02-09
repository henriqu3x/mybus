import 'package:flutter/services.dart';

class ForegroundServiceChannel {
  static const MethodChannel _channel =
      MethodChannel('foreground_location');

  static Future<void> start() async {
    await _channel.invokeMethod('startService');
  }

  static Future<void> stop() async {
    await _channel.invokeMethod('stopService');
  }
}
