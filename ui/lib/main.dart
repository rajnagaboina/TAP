import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthService(),
      child: const TapGeneratorApp(),
    ),
  );
}

class TapGeneratorApp extends StatelessWidget {
  const TapGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TAP Generator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0078D4), // Microsoft blue
        ),
        useMaterial3: true,
      ),
      home: const _AppLoader(),
    );
  }
}

class _AppLoader extends StatefulWidget {
  const _AppLoader();

  @override
  State<_AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<_AppLoader> {
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await context.read<AuthService>().initAsync();
    if (mounted) setState(() => _initializing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final isAuth = context.watch<AuthService>().isAuthenticated;
    if (!isAuth) {
      // Easy Auth will handle the redirect to Entra login.
      // If somehow the user is not authenticated (local dev), show a message.
      return const Scaffold(
        body: Center(
          child: Text('Redirecting to sign-in…'),
        ),
      );
    }
    return const HomeScreen();
  }
}
