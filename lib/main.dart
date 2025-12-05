import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/bus_provider.dart';
import 'screens/splash_screen.dart';
import 'services/favorites_service.dart';

void main() async {
  // Ensure Flutter bindings are initialized before using platform channels
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize FavoritesService to fix path_provider plugin
  await FavoritesService().init();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => BusProvider())],
      child: MaterialApp(
        title: 'MyBus',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const SplashScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
