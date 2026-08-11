import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/server_config.dart';

/// Lets the user point the app at a different backend without a rebuild.
///
/// This exists for one specific situation: the app runs on physical phones
/// over wifi we don't control. If the router hands out a different subnet
/// than the one baked in at build time, every screen fails with what looks
/// like a dead server. Rebuilding four phones costs a laptop, a cable and --
/// on iOS -- Xcode and a provisioning profile. Re-typing a host costs
/// seconds.
///
/// Deliberately reachable from the login screen, i.e. *before* authenticating.
/// A wrong host makes login itself hang, so a settings screen that lived
/// behind login would be unreachable exactly when it is needed.
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

/// Outcome of the "Test connection" probe, kept as a small enum so the UI
/// can distinguish "not tried yet" from "tried and failed" -- otherwise a
/// blank result reads as a silent failure.
enum _ProbeState { idle, running, success, failure }

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  late final TextEditingController _controller;
  _ProbeState _probe = _ProbeState.idle;
  String? _probeDetail;

  /// The probe runs against whatever is typed in the field, not against the
  /// saved host, so the user can verify an address before committing to it.
  static const Duration _probeTimeout = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ServerConfig.instance.host);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final host = ServerConfig.normalizeHost(_controller.text);
    if (host.isEmpty) {
      setState(() {
        _probe = _ProbeState.failure;
        _probeDetail = 'Enter a host first, e.g. 192.168.1.64:8000';
      });
      return;
    }

    setState(() {
      _probe = _ProbeState.running;
      _probeDetail = null;
    });

    // Hits the same unauthenticated endpoint ServerConfig documents as the
    // health check. A 200 here proves the host, port, firewall and Django's
    // ALLOWED_HOSTS are all correct in one shot -- those are four separate
    // failure modes that otherwise all present identically as "login hangs".
    final uri = Uri.parse('http://$host/api/v1/ambulances/districts/');
    try {
      final response = await http.get(uri).timeout(_probeTimeout);
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _probe = _ProbeState.success;
          _probeDetail = 'Reached the backend at $host.';
        });
      } else if (response.statusCode == 400) {
        // The single most likely misconfiguration on demo day, and the one
        // whose default message ("Bad Request") explains nothing.
        setState(() {
          _probe = _ProbeState.failure;
          _probeDetail =
              'Server replied 400. The backend is running but is refusing '
              'this address -- add it to ALLOWED_HOSTS in settings.py and '
              'restart the server.';
        });
      } else {
        setState(() {
          _probe = _ProbeState.failure;
          _probeDetail = 'Server replied ${response.statusCode}.';
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _probe = _ProbeState.failure;
        _probeDetail =
            'No response within ${_probeTimeout.inSeconds}s. Check that the '
            'phone and the server are on the same wifi, that the server was '
            'started with 0.0.0.0:8000, and that the firewall allows port 8000.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _probe = _ProbeState.failure;
        _probeDetail = 'Could not connect: $e';
      });
    }
  }

  Future<void> _save() async {
    final host = ServerConfig.normalizeHost(_controller.text);
    if (host.isEmpty) return;
    await ServerConfig.instance.setHost(host);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backend set to $host')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    await ServerConfig.instance.resetToDefault();
    if (!mounted) return;
    setState(() {
      _controller.text = ServerConfig.instance.host;
      _probe = _ProbeState.idle;
      _probeDetail = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ServerConfig.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Server settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Backend address',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'The host and port where the MedAlert server is running. Change '
            'this if the wifi network assigns a different address.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Host and port',
              hintText: '192.168.1.64:8000',
              border: OutlineInputBorder(),
              prefixText: 'http://',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Build default: ${config.compiledDefault}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _probe == _ProbeState.running ? null : _testConnection,
                  icon: _probe == _ProbeState.running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Test connection'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ),
            ],
          ),
          if (_probeDetail != null) ...[
            const SizedBox(height: 16),
            _ProbeResult(state: _probe, detail: _probeDetail!),
          ],
          if (config.isOverridden) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.restore),
              label: Text('Reset to build default (${config.compiledDefault})'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProbeResult extends StatelessWidget {
  const _ProbeResult({required this.state, required this.detail});

  final _ProbeState state;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = state == _ProbeState.success;
    final color =
        success ? theme.colorScheme.primary : theme.colorScheme.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(detail, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
