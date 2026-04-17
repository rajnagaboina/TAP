import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/tap_models.dart';

class TapResultScreen extends StatefulWidget {
  final TapResult result;
  final String targetUpn;

  const TapResultScreen({
    super.key,
    required this.result,
    required this.targetUpn,
  });

  @override
  State<TapResultScreen> createState() => _TapResultScreenState();
}

class _TapResultScreenState extends State<TapResultScreen> {
  bool _revealed = false;
  bool _copied = false;

  Future<void> _copyToClipboard() async {
    try {
      await Clipboard.setData(
          ClipboardData(text: widget.result.temporaryAccessPass));
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _copied = false);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Clipboard copy failed. Select the TAP text and copy manually.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiresAt = (widget.result.startDateTime != null
            ? widget.result.startDateTime!
                .add(Duration(minutes: widget.result.lifetimeInMinutes))
            : DateTime.now()
                .add(Duration(minutes: widget.result.lifetimeInMinutes)))
        .toLocal();

    final fmt = DateFormat('dd MMM yyyy HH:mm (zzz)');

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('TAP Generated'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.green.shade600, size: 28),
                        const SizedBox(width: 10),
                        Text(
                          'Temporary Access Pass Ready',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _infoRow('Target user', widget.targetUpn),
                    _infoRow('Lifetime',
                        '${widget.result.lifetimeInMinutes} minutes'),
                    _infoRow('Expires at (approx.)', fmt.format(expiresAt)),
                    _infoRow('One-time use',
                        widget.result.isUsableOnce ? 'Yes' : 'No'),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        border: Border.all(color: Colors.amber.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_outlined,
                                  size: 18, color: Colors.amber),
                              const SizedBox(width: 6),
                              Text(
                                'Show this to the user once – it will not be shown again.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: Colors.amber.shade800,
                                        fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _revealed = !_revealed),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: _revealed
                                    ? SelectableText(
                                        widget.result.temporaryAccessPass,
                                        key: const ValueKey('revealed'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .displaySmall
                                            ?.copyWith(
                                                letterSpacing: 6,
                                                fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      )
                                    : Text(
                                        '•' * widget.result.temporaryAccessPass.length,
                                        key: const ValueKey('hidden'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .displaySmall
                                            ?.copyWith(letterSpacing: 6),
                                        textAlign: TextAlign.center,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              _revealed
                                  ? 'Tap to hide'
                                  : 'Tap to reveal',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _copyToClipboard,
                            icon: Icon(_copied
                                ? Icons.check
                                : Icons.copy_outlined),
                            label: Text(_copied ? 'Copied!' : 'Copy TAP'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Generate another'),
                          ),
                        ),
                      ],
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

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 160,
              child: Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey.shade600)),
            ),
            Expanded(
                child: Text(value,
                    style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      );
}
