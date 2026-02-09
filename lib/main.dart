import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/bus_provider.dart';
import 'screens/splash_screen.dart';
import 'services/favorites_service.dart';
import 'services/notification_service.dart';
import 'services/geofence_manager.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Serviços que usam platform channels
  await FavoritesService().init();

  await NotificationService().init();
  await NotificationService().requestPermissions();

  // 🔥 ISSO ESTAVA FALTANDO
  await GeofenceManager.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => BusProvider())],
      child: MaterialApp(
        title: 'No Ponto',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const SplashScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
