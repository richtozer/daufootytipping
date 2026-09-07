import 'dart:convert';

import 'package:daufootytipping/services/app_resume_diagnostics.dart';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ResumeDiagnosticsPage extends StatefulWidget {
  const ResumeDiagnosticsPage({
    required this.selectedCompDbKey,
    super.key,
  });

  final String? selectedCompDbKey;

  @override
  State<ResumeDiagnosticsPage> createState() => _ResumeDiagnosticsPageState();
}

class _ResumeDiagnosticsPageState extends State<ResumeDiagnosticsPage> {
  late Future<List<String>> _diagnosticChunks;
  int _selectedChunkIndex = -1;
  bool _probeOperationInProgress = false;

  @override
  void initState() {
    super.initState();
    _diagnosticChunks = AppResumeDiagnostics.exportTextChunks();
  }

  void _reload() {
    setState(() {
      _selectedChunkIndex = -1;
      _diagnosticChunks = AppResumeDiagnostics.exportTextChunks();
    });
  }

  Future<void> _copyChunk(
    String diagnostics,
    int chunkIndex,
    int chunkCount,
  ) async {
    try {
      await Clipboard.setData(ClipboardData(text: diagnostics));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Resume diagnostics chunk ${chunkIndex + 1} of $chunkCount copied',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not copy diagnostics chunk: $error')),
      );
    }
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

  Future<void> _setSecondaryProbeActive(bool active) async {
    final String? compDbKey = widget.selectedCompDbKey;
    if (active && (compDbKey == null || compDbKey.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No competition is selected.')),
      );
      return;
    }
    setState(() {
      _probeOperationInProgress = true;
    });
    try {
      if (active) {
        await AppResumeDiagnostics.startSecondaryProbe(
          gamesPath: '${p.gamesPathRoot}/$compDbKey',
        );
      } else {
        await AppResumeDiagnostics.stopSecondaryProbe();
      }
      _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Secondary client probe failed: $error')),
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
                      onPressed:
                          _probeOperationInProgress ||
                              AppResumeDiagnostics.secondaryProbeActive
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
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Secondary Firebase client',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'After the primary probe is running, start this client. '
                      'It uses a separate FirebaseApp with persistence disabled '
                      'and observes connection, probe, config, and games data. '
                      'Selected competition: '
                      '${widget.selectedCompDbKey ?? "none"}.',
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed:
                          _probeOperationInProgress ||
                              (!AppResumeDiagnostics.secondaryProbeActive &&
                                  (widget.selectedCompDbKey == null ||
                                      !AppResumeDiagnostics
                                          .extendedProbeActive))
                          ? null
                          : () => _setSecondaryProbeActive(
                              !AppResumeDiagnostics.secondaryProbeActive,
                            ),
                      icon: Icon(
                        AppResumeDiagnostics.secondaryProbeActive
                            ? Icons.stop_circle_outlined
                            : Icons.hub_outlined,
                      ),
                      label: Text(
                        AppResumeDiagnostics.secondaryProbeActive
                            ? 'Stop secondary client'
                            : 'Start secondary client',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<String>>(
              future: _diagnosticChunks,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load resume diagnostics: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final List<String> chunks =
                    snapshot.data ?? const <String>[];
                if (chunks.isEmpty) {
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
                final int chunkIndex = _selectedChunkIndex < 0
                    ? chunks.length - 1
                    : _selectedChunkIndex.clamp(0, chunks.length - 1);
                final String diagnostics = chunks[chunkIndex];
                final int chunkBytes = utf8.encode(diagnostics).length;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Events are stored on this device and survive an app restart.',
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Chunk ${chunkIndex + 1} of ${chunks.length} '
                                '($chunkBytes bytes)',
                              ),
                              IconButton(
                                tooltip: 'Previous chunk',
                                onPressed: chunkIndex == 0
                                    ? null
                                    : () {
                                        setState(() {
                                          _selectedChunkIndex = chunkIndex - 1;
                                        });
                                      },
                                icon: const Icon(Icons.chevron_left),
                              ),
                              IconButton(
                                tooltip: 'Next chunk',
                                onPressed: chunkIndex == chunks.length - 1
                                    ? null
                                    : () {
                                        setState(() {
                                          _selectedChunkIndex = chunkIndex + 1;
                                        });
                                      },
                                icon: const Icon(Icons.chevron_right),
                              ),
                              FilledButton.icon(
                                onPressed: () => _copyChunk(
                                  diagnostics,
                                  chunkIndex,
                                  chunks.length,
                                ),
                                icon: const Icon(Icons.copy),
                                label: const Text('Copy chunk'),
                              ),
                            ],
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
