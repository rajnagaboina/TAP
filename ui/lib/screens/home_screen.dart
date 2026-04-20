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
  int _selectedDuration = 30;
  bool _isLoading = false;
  UserSummary? _selectedUser;
  String? _userFieldError;

  final List<int> _durations = [15, 30, 45, 60];

  Future<void> _submit() async {
    setState(() => _userFieldError = _selectedUser == null ? 'Please select a user.' : null);
    if (_selectedUser == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final tapService = TapService(context.read<AuthService>());
      final result = await tapService.generateTap(
        targetUpn: _selectedUser!.upn,
        lifetimeInMinutes: _selectedDuration,
      );

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TapResultScreen(result: result, targetUpn: _selectedUser!.upn),
        ),
      );
      setState(() {
        _selectedUser = null;
        _selectedDuration = 30;
        _userFieldError = null;
      });
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
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;

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
            onPressed: () => context.read<AuthService>().signOut(),
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
                    _UserSearchField(
                      selectedUser: _selectedUser,
                      errorText: _userFieldError,
                      tapService: TapService(auth),
                      onSelected: (u) => setState(() {
                        _selectedUser = u;
                        _userFieldError = null;
                      }),
                      onCleared: () => setState(() {
                        _selectedUser = null;
                        _userFieldError = null;
                      }),
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

class _UserSearchField extends StatefulWidget {
  final UserSummary? selectedUser;
  final String? errorText;
  final TapService tapService;
  final ValueChanged<UserSummary> onSelected;
  final VoidCallback onCleared;

  const _UserSearchField({
    required this.selectedUser,
    required this.errorText,
    required this.tapService,
    required this.onSelected,
    required this.onCleared,
  });

  @override
  State<_UserSearchField> createState() => _UserSearchFieldState();
}

class _UserSearchFieldState extends State<_UserSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void didUpdateWidget(_UserSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedUser == null && oldWidget.selectedUser != null) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedUser != null) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: 'Target User',
          prefixIcon: const Icon(Icons.person_outline),
          border: const OutlineInputBorder(),
          errorText: widget.errorText,
          suffixIcon: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Clear selection',
            onPressed: widget.onCleared,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.selectedUser!.fullName,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              widget.selectedUser!.upn,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return Autocomplete<UserSummary>(
      optionsBuilder: (textEditingValue) async {
        final q = textEditingValue.text.trim();
        if (q.length < 2) return const [];
        try {
          return await widget.tapService.searchUsers(q);
        } catch (_) {
          return const [];
        }
      },
      displayStringForOption: (u) => u.upn,
      onSelected: (u) {
        _controller.text = u.upn;
        widget.onSelected(u);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 456, maxHeight: 280),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final u = options.elementAt(index);
                  return ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(u.fullName),
                    subtitle: Text(u.upn),
                    onTap: () => onSelected(u),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return TextField(
          controller: textController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Target User',
            hintText: 'Type name or email to search…',
            prefixIcon: const Icon(Icons.person_outline),
            border: const OutlineInputBorder(),
            errorText: widget.errorText,
          ),
        );
      },
    );
  }
}
