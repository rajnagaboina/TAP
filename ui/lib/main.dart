import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/tap_models.dart';
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
    final auth = context.watch<AuthService>();
    if (!auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) => auth.redirectToLogin());
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!auth.isAuthorized) {
      return _AccessDeniedScreen(user: auth.currentUser!);
    }
    return const HomeScreen();
  }
}

class _AccessDeniedScreen extends StatelessWidget {
  final UserInfo user;

  const _AccessDeniedScreen({required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TAP Generator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => context.read<AuthService>().signOut(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline,
                      size: 56,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 20),
                  Text(
                    'Access Denied',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You are signed in as ${user.upn} but your account is not authorised to use this application.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'To gain access, Contact your IAM Support Team.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                    onPressed: () => context.read<AuthService>().signOut(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
