import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/tap_service.dart';
import '../models/tap_models.dart';
import 'tap_result_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _upnController = TextEditingController();
  int _selectedDuration = 30;
  bool _isLoading = false;

  final List<int> _durations = [15, 30, 45, 60];

  @override
  void dispose() {
    _upnController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final tapService = TapService(context.read<AuthService>());
      final result = await tapService.generateTap(
        targetUpn: _upnController.text.trim(),
        lifetimeInMinutes: _selectedDuration,
      );

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TapResultScreen(result: result, targetUpn: _upnController.text.trim()),
        ),
      );
      // Clear the form after returning from result screen
      _upnController.clear();
      setState(() => _selectedDuration = 30);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TAP Generator'),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  user.displayName.isNotEmpty ? user.displayName : user.upn,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () {
              context.read<AuthService>().signOut();
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Generate Temporary Access Pass',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Issues a one-time TAP for non-privileged users.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _upnController,
                      decoration: const InputDecoration(
                        labelText: 'Target User (UPN)',
                        hintText: 'user@yourdomain.com',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Please enter the target user UPN.';
                        }
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim())) {
                          return 'Enter a valid UPN (e.g. user@domain.com).';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<int>(
                      value: _selectedDuration,
                      decoration: const InputDecoration(
                        labelText: 'TAP Lifetime',
                        prefixIcon: Icon(Icons.timer_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: _durations
                          .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text('$d minutes'),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedDuration = v ?? 30),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _submit,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.vpn_key_outlined),
                      label: Text(_isLoading ? 'Generating…' : 'Generate TAP'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
