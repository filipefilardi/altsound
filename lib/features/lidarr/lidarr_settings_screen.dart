import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
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
  bool _testing = false;
  String? _error;
  bool? _testResult;
  String? _lastSuccessfulTestSignature;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(lidarrConfigProvider);
    _urlCtrl = TextEditingController(text: existing?.url ?? '');
    _keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    _urlCtrl.addListener(_onConnectionInputChanged);
    _keyCtrl.addListener(_onConnectionInputChanged);
  }

  @override
  void dispose() {
    _urlCtrl.removeListener(_onConnectionInputChanged);
    _keyCtrl.removeListener(_onConnectionInputChanged);
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  String _connectionSignature() {
    return '${_urlCtrl.text.trim()}|${_keyCtrl.text.trim()}';
  }

  void _onConnectionInputChanged() {
    final current = _connectionSignature();
    if (_lastSuccessfulTestSignature == current && _testResult == true) return;
    if (_testResult != null || _error != null) {
      setState(() {
        _testResult = null;
        _error = null;
      });
    }
  }

  Future<bool> _testConnection() async {
    if (!_formKey.currentState!.validate()) return false;
    setState(() {
      _testing = true;
      _error = null;
      _testResult = null;
    });
    final config = LidarrConfig(
      url: _urlCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
    );
    final repo = LidarrRepository(config);
    final ok = await repo.ping();
    if (!mounted) return false;
    if (!ok) {
      setState(() {
        _testing = false;
        _testResult = false;
        _lastSuccessfulTestSignature = null;
        _error = 'Could not reach Lidarr at that URL with this API key.';
      });
      return false;
    }
    setState(() {
      _testing = false;
      _testResult = true;
      _lastSuccessfulTestSignature = _connectionSignature();
    });
    return true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final testedCurrentValues = _testResult == true &&
        _lastSuccessfulTestSignature == _connectionSignature();
    if (!testedCurrentValues) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test the connection first before saving.'),
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final config = LidarrConfig(
      url: _urlCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
    );
    await ref.read(lidarrConfigProvider.notifier).save(config);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lidarr connected.')),
    );
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Lidarr?'),
        content: const Text(
          'AltSound will no longer be able to request new music until you reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Disconnect',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(lidarrConfigProvider.notifier).clear();
    if (!mounted) return;
    setState(() {
      _urlCtrl.clear();
      _keyCtrl.clear();
      _testResult = null;
      _error = null;
      _lastSuccessfulTestSignature = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(lidarrConfigProvider);
    final connected = config != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Lidarr')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Hero(),
                const SizedBox(height: 24),
                if (connected) ...[
                  _ConnectedBanner(
                    url: config.url,
                    onDisconnect:
                        (_saving || _testing) ? null : _confirmDisconnect,
                  ),
                  const SizedBox(height: 24),
                ],
                _SectionLabel(connected ? 'Update connection' : 'Connection'),
                const SizedBox(height: 10),
                _FormCard(
                  children: [
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
                        labelText: 'API key',
                        prefixIcon: Icon(Icons.vpn_key_outlined),
                      ),
                      autocorrect: false,
                      obscureText: true,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _StatusRow(
                    icon: Icons.error_outline,
                    color: AppColors.error,
                    message: _error!,
                  ),
                ],
                if (_testResult == true) ...[
                  const SizedBox(height: 16),
                  const _StatusRow(
                    icon: Icons.check_circle_outline,
                    color: Color(0xFF66CC8A),
                    message: 'Connection looks good.',
                  ),
                ],
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: const StadiumBorder(),
                    side: const BorderSide(color: AppColors.divider),
                    foregroundColor: AppColors.textPrimary,
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  onPressed: (_saving || _testing) ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 20),
                  label: Text(_testing ? 'Testing…' : 'Test connection'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: (_saving || _testing) ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.onAccent,
                          ),
                        )
                      : Text(connected ? 'Update connection' : 'Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              gradient: AppGradients.accent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.travel_explore_outlined,
              color: AppColors.onAccent,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Discover new music',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Connect Lidarr to search for artists and albums. Requests download to your server, then appear in your library after import.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connected banner
// ---------------------------------------------------------------------------

class _ConnectedBanner extends StatelessWidget {
  const _ConnectedBanner({required this.url, required this.onDisconnect});

  final String url;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF66CC8A).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF66CC8A),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connected',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  url,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onDisconnect,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form card + helpers
// ---------------------------------------------------------------------------

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: color, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
