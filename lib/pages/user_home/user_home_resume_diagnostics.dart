import 'package:daufootytipping/services/app_resume_diagnostics.dart';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ResumeDiagnosticsPage extends StatefulWidget {
  const ResumeDiagnosticsPage({super.key});

  @override
  State<ResumeDiagnosticsPage> createState() => _ResumeDiagnosticsPageState();
}

class _ResumeDiagnosticsPageState extends State<ResumeDiagnosticsPage> {
  late Future<String> _diagnostics;
  bool _probeOperationInProgress = false;

  @override
  void initState() {
    super.initState();
    _diagnostics = AppResumeDiagnostics.exportText();
  }

  void _reload() {
    setState(() {
      _diagnostics = AppResumeDiagnostics.exportText();
    });
  }

  Future<void> _copy(String diagnostics) async {
    await Clipboard.setData(ClipboardData(text: diagnostics));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Resume diagnostics copied')),
    );
  }

  Future<void> _setExtendedProbeActive(bool active) async {
    setState(() {
      _probeOperationInProgress = true;
    });
    try {
      if (active) {
        await AppResumeDiagnostics.startExtendedProbe(
          database: configuredRealtimeDatabase,
        );
      } else {
        await AppResumeDiagnostics.stopExtendedProbe();
      }
      _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Diagnostic probe failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _probeOperationInProgress = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Android resume diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Reload diagnostics',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Extended RTDB probe',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Start only after stale data is visible. Then write '
                      'unique bare string or number nonces from the backend '
                      'to this path and to /AppConfig/resumeProbe.',
                    ),
                    const SizedBox(height: 6),
                    const SelectableText(
                      AppResumeDiagnostics.diagnosticProbePath,
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _probeOperationInProgress
                          ? null
                          : () => _setExtendedProbeActive(
                              !AppResumeDiagnostics.extendedProbeActive,
                            ),
                      icon: Icon(
                        AppResumeDiagnostics.extendedProbeActive
                            ? Icons.stop
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        AppResumeDiagnostics.extendedProbeActive
                            ? 'Stop probe'
                            : 'Start probe',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<String>(
              future: _diagnostics,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final String diagnostics = snapshot.data ?? '';
                if (diagnostics.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No resume diagnostics have been recorded in this build.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Events are stored on this device and survive an app restart.',
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () => _copy(diagnostics),
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          diagnostics,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
