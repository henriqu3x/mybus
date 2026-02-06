import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/bus_provider.dart';
import '../utils/app_theme.dart';
import 'home_map_screen.dart';
import 'terms_screen.dart';
import 'privacy_policy_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  bool _isLoading = true;
  bool _showTerms = false;

  @override
  void initState() {
    super.initState();

    // Setup animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    _animationController.forward();

    // Start loading data immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<BusProvider>(context, listen: false);
      provider.fetchLinhas();
      provider.fetchLogradouros();
      provider.buildGraph(); // Start building the graph in background
      
      _checkFirstTime();
    });
  }
  
  Future<void> _checkFirstTime() async {
    // Wait at least minimum splash duration
    await Future.delayed(const Duration(seconds: 3));
    
    final prefs = await SharedPreferences.getInstance();
    final hasAgreed = prefs.getBool('has_agreed_to_terms') ?? false;

    if (hasAgreed) {
      _navigateToHome();
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showTerms = true;
        });
      }
    }
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeMapScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }
  
  Future<void> _agreedAndContinue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_agreed_to_terms', true);
    _navigateToHome();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primary,
              AppTheme.primaryDark,
              AppTheme.backgroundDark,
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo/Icon
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spaceLg),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
                    ),
                    child: const Icon(
                      Icons.directions_bus_rounded,
                      size: 80,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceXl),
                  
                  // App Name
                  Text(
                    'No Ponto',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                  
                  // Tagline
                  Text(
                    'Seu transporte público inteligente',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withOpacity(0.9),
                        ),
                  ),
                  const SizedBox(height: AppTheme.spaceXxl),
                  
                  // Conditional Content: Loader OR Terms
                  if (_isLoading)
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withOpacity(0.8),
                        ),
                        strokeWidth: 3,
                      ),
                    ),
                    
                  if (_showTerms) ...[
                    Text(
                      'Para continuar, você deve concordar com nossos Termos de Uso e Políticas de Privacidade.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: _agreedAndContinue,
                      child: const Text('Concordar e Continuar', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 20,
                      children: [
                        TextButton(
                          onPressed: () {
                             Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => const TermsScreen()),
                            );
                          },
                          child: Text(
                            'Termos de Uso',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.white,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                             Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
                            );
                          },
                          child: Text(
                            'Políticas de Privacidade',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

