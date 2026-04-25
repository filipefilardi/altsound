import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/lidarr/lidarr_config.dart';
import '../../data/lidarr/lidarr_repository.dart';

class LidarrSettingsScreen extends ConsumerStatefulWidget {
  const LidarrSettingsScreen({super.key});

  @override
  ConsumerState<LidarrSettingsScreen> createState() =>
      _LidarrSettingsScreenState();
}

class _LidarrSettingsScreenState extends ConsumerState<LidarrSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  bool _saving = false;
  String? _error;
  bool? _testResult;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(lidarrConfigProvider);
    _urlCtrl = TextEditingController(text: existing?.url ?? '');
    _keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _testResult = null;
    });
    final config = LidarrConfig(
      url: _urlCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
    );
    final repo = LidarrRepository(config);
    final ok = await repo.ping();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _testResult = false;
        _error = 'Could not reach Lidarr at that URL with this API key.';
      });
      return;
    }
    await ref.read(lidarrConfigProvider.notifier).save(config);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _testResult = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lidarr connected.')),
    );
  }

  Future<void> _disconnect() async {
    await ref.read(lidarrConfigProvider.notifier).clear();
    if (!mounted) return;
    setState(() {
      _urlCtrl.clear();
      _keyCtrl.clear();
      _testResult = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(lidarrConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Lidarr')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Header(),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lidarr URL',
                    hintText: 'https://lidarr.example.com',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _keyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  autocorrect: false,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(color: AppColors.error)),
                ],
                if (_testResult == true) ...[
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.check_circle, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Connected'),
                    ],
                  ),
                ],
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.black),
                        )
                      : Text(config == null
                          ? 'CONNECT LIDARR'
                          : 'UPDATE CONNECTION'),
                ),
                if (config != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _saving ? null : _disconnect,
                    child: const Text('Disconnect Lidarr',
                        style: TextStyle(color: AppColors.error)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Connect Lidarr',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          'Search for new artists and albums. Jellymusic will ask Lidarr to download them, then they\'ll appear in your library after Lidarr imports them.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
