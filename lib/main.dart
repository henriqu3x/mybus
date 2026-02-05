import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/bus_provider.dart';
import 'screens/splash_screen.dart';
import 'services/favorites_service.dart';
import 'services/notification_service.dart';
import 'utils/app_theme.dart';
import 'services/background_service.dart';

void main() async {
  // Ensure Flutter bindings are initialized before using platform channels
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize FavoritesService to fix path_provider plugin
  await FavoritesService().init();
  
  // Initialize NotificationService and request permissions
  await NotificationService().init();
  await NotificationService().requestPermissions();
  
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
