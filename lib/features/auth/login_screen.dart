import 'dart:ui' show ImageFilter;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_gradients.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/utils/dio_error_message.dart';
import 'package:altsound/core/widgets/glass_popover.dart';
import 'package:altsound/data/jellyfin/auth_repository.dart';
import 'package:altsound/data/jellyfin/jellyfin_api.dart';
import 'package:altsound/features/auth/auth_controller.dart';
import 'package:altsound/features/auth/widgets/login_error_banner.dart';

enum _LoginStep { server, account }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialServerUrl});

  final String? initialServerUrl;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  _LoginStep _step = _LoginStep.server;
  late Future<List<SavedJellyfinServer>> _savedServersFuture;
  JellyfinPublicServerInfo? _serverInfo;
  String? _serverError;
  bool _checkingServer = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _savedServersFuture = _loadSavedServers();
    _serverCtrl.addListener(_onServerUrlChanged);
    final initialServerUrl = widget.initialServerUrl;
    if (initialServerUrl != null && initialServerUrl.isNotEmpty) {
      _serverCtrl.text = initialServerUrl;
      _serverInfo = JellyfinPublicServerInfo(serverUrl: initialServerUrl);
      _step = _LoginStep.account;
    }
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialServerUrl;
    if (next != oldWidget.initialServerUrl && next != null && next.isNotEmpty) {
      _serverCtrl.text = next;
      _serverInfo = JellyfinPublicServerInfo(serverUrl: next);
      _serverError = null;
      _step = _LoginStep.account;
    }
  }

  @override
  void dispose() {
    _serverCtrl.removeListener(_onServerUrlChanged);
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _onServerUrlChanged() {
    if (!mounted || _step != _LoginStep.server || _checkingServer) return;
    setState(() {});
  }

  void _submit() {
    if (_step == _LoginStep.server) {
      _continueWithServer();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    ref
        .read(authControllerProvider.notifier)
        .login(
          serverUrl: _serverInfo?.serverUrl ?? _serverCtrl.text.trim(),
          username: _userCtrl.text.trim(),
          password: _passCtrl.text,
        );
  }

  Future<void> _continueWithServer() async {
    if (_serverCtrl.text.trim().isEmpty) return;
    setState(() {
      _checkingServer = true;
      _serverError = null;
    });
    try {
      final info = await ref
          .read(authRepositoryProvider)
          .publicServerInfo(_serverCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _serverInfo = info;
        _serverCtrl.text = info.serverUrl;
        _savedServersFuture = _loadSavedServers();
        _step = _LoginStep.account;
      });
    } on JellyfinAuthException catch (e) {
      if (!mounted) return;
      setState(() => _serverError = e.message);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _serverError = userFacingDioMessage(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverError = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _checkingServer = false);
    }
  }

  void _changeServer() {
    setState(() {
      _step = _LoginStep.server;
      _serverInfo = null;
      _serverError = null;
      _serverCtrl.clear();
      _userCtrl.clear();
      _passCtrl.clear();
    });
  }

  Future<List<SavedJellyfinServer>> _loadSavedServers() async {
    final servers = await ref.read(authRepositoryProvider).savedServers();
    final current = _serverInfo;
    if (mounted &&
        current != null &&
        (current.serverName == null || current.serverName!.isEmpty)) {
      for (final server in servers) {
        if (server.serverUrl == current.serverUrl) {
          setState(() => _serverInfo = server.toPublicInfo());
          break;
        }
      }
    }
    return servers;
  }

  void _selectSavedServer(SavedJellyfinServer server) {
    setState(() {
      _serverCtrl.text = server.serverUrl;
      _serverInfo = server.toPublicInfo();
      _serverError = null;
      _userCtrl.text = server.lastUsername ?? '';
      _passCtrl.clear();
      _step = _LoginStep.account;
    });
  }

  Future<void> _forgetSavedServer(SavedJellyfinServer server) async {
    await ref.read(authRepositoryProvider).forgetServer(server.serverUrl);
    if (!mounted) return;
    final nextSavedServers = _loadSavedServers();
    setState(() {
      _savedServersFuture = nextSavedServers;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final loading = state is AuthLoading;
    final errorMessage = _step == _LoginStep.server
        ? _serverError
        : state is AuthUnauthenticated
        ? state.error
        : null;
    final busy = loading || _checkingServer;
    final canSubmit =
        !busy &&
        (_step == _LoginStep.account || _serverCtrl.text.trim().isNotEmpty);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.loginBackdrop),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xxl),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.xxl),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.22),
                        ),
                        color: AppColors.surface.withValues(alpha: 0.78),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.xl,
                          AppSpacing.lg,
                          AppSpacing.xl,
                        ),
                        child: Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _LoginBrand(
                                subtitle: _step == _LoginStep.server
                                    ? 'Choose your Jellyfin server'
                                    : 'Sign in to your Jellyfin account',
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _LoginStepIndicator(
                                step: _step,
                                onServerTap: _step == _LoginStep.account
                                    ? _changeServer
                                    : null,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  child: _step == _LoginStep.server
                                      ? FutureBuilder<
                                          List<SavedJellyfinServer>
                                        >(
                                          key: const ValueKey('server-step'),
                                          future: _savedServersFuture,
                                          builder: (context, snapshot) {
                                            return _ServerStep(
                                              controller: _serverCtrl,
                                              savedServers:
                                                  snapshot.data ?? const [],
                                              loadingSavedServers:
                                                  snapshot.connectionState ==
                                                  ConnectionState.waiting,
                                              onSelectSavedServer:
                                                  _selectSavedServer,
                                              onForgetSavedServer:
                                                  _forgetSavedServer,
                                              onSubmitted: _submit,
                                            );
                                          },
                                        )
                                      : _AccountStep(
                                          key: const ValueKey('account-step'),
                                          serverInfo: _serverInfo,
                                          usernameController: _userCtrl,
                                          passwordController: _passCtrl,
                                          obscurePassword: _obscure,
                                          onTogglePassword: () => setState(
                                            () => _obscure = !_obscure,
                                          ),
                                          onSubmitted: _submit,
                                        ),
                                ),
                              ),
                              if (errorMessage != null) ...[
                                const SizedBox(height: AppSpacing.md),
                                LoginErrorBanner(message: errorMessage),
                              ],
                              const SizedBox(height: AppSpacing.xl),
                              ElevatedButton(
                                onPressed: canSubmit ? _submit : null,
                                child: busy
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: AppColors.onAccent,
                                        ),
                                      )
                                    : Text(
                                        _step == _LoginStep.server
                                            ? 'CONTINUE'
                                            : 'SIGN IN',
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'AltSound',
          style: Theme.of(context).textTheme.displayMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _LoginStepIndicator extends StatelessWidget {
  const _LoginStepIndicator({required this.step, this.onServerTap});

  final _LoginStep step;
  final VoidCallback? onServerTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: _LoginStepPill(
                icon: PiconsRegular.hardDrives,
                label: 'Server',
                active: step == _LoginStep.server,
                onTap: onServerTap,
              ),
            ),
            Expanded(
              child: _LoginStepPill(
                icon: PiconsRegular.user,
                label: 'Account',
                active: step == _LoginStep.account,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginStepPill extends StatelessWidget {
  const _LoginStepPill({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.onAccent : AppColors.textSecondary;
    return Material(
      color: active ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerStep extends StatelessWidget {
  const _ServerStep({
    required this.controller,
    required this.savedServers,
    required this.loadingSavedServers,
    required this.onSelectSavedServer,
    required this.onForgetSavedServer,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final List<SavedJellyfinServer> savedServers;
  final bool loadingSavedServers;
  final ValueChanged<SavedJellyfinServer> onSelectSavedServer;
  final ValueChanged<SavedJellyfinServer> onForgetSavedServer;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loadingSavedServers)
          const _SavedServersSkeleton()
        else if (savedServers.isNotEmpty) ...[
          const _SectionHeader(label: 'SAVED SERVERS'),
          const SizedBox(height: AppSpacing.sm),
          for (final server in savedServers) ...[
            _SavedServerTile(
              server: server,
              onTap: () => onSelectSavedServer(server),
              onForget: () => onForgetSavedServer(server),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.sm),
        ],
        _SectionHeader(
          label: savedServers.isEmpty ? 'SERVER URL' : 'USE ANOTHER SERVER',
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => onSubmitted(),
          decoration: const InputDecoration(
            hintText: 'https://jellyfin.example.com',
            prefixIcon: Icon(PiconsRegular.hardDrives),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.labelLarge);
  }
}

class _SavedServerTile extends StatelessWidget {
  const _SavedServerTile({
    required this.server,
    required this.onTap,
    required this.onForget,
  });

  final SavedJellyfinServer server;
  final VoidCallback onTap;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    return _ServerTile(
      title: _serverTitle(server.serverName),
      subtitle: server.serverUrl,
      onTap: onTap,
      onDelete: onForget,
    );
  }
}

String _serverTitle(String? serverName) {
  final name = serverName?.trim();
  return name == null || name.isEmpty ? 'Jellyfin server' : name;
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.title,
    this.subtitle,
    this.readOnly = false,
    this.onTap,
    this.onDelete,
  });

  final String title;
  final String? subtitle;
  final bool readOnly;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: readOnly
          ? AppColors.primary.withValues(alpha: 0.12)
          : AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: readOnly ? null : onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: readOnly
                  ? AppColors.primary.withValues(alpha: 0.28)
                  : AppColors.divider,
              width: 0.5,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm + 2,
              readOnly ? AppSpacing.md : AppSpacing.xs,
              AppSpacing.sm + 2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (readOnly) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4ADE80),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Server options',
                    onPressed: () => _showServerOptions(context),
                    icon: const Icon(PiconsRegular.dotsThree, size: 20),
                    color: AppColors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showServerOptions(BuildContext context) {
    return showGlassPopover<void>(
      context: context,
      width: 240,
      builder: (_) => SafeArea(
        child: GlassPopoverItem(
          icon: PiconsRegular.trash,
          label: 'Delete server',
          destructive: true,
          onTap: onDelete!,
        ),
      ),
    );
  }
}

class _SavedServersSkeleton extends StatelessWidget {
  const _SavedServersSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: AppColors.surfaceElevated,
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _AccountStep extends StatelessWidget {
  const _AccountStep({
    super.key,
    required this.serverInfo,
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onTogglePassword,
    required this.onSubmitted,
  });

  final JellyfinPublicServerInfo? serverInfo;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ServerTile(
          title: _serverTitle(serverInfo?.serverName),
          subtitle: serverInfo?.serverUrl,
          readOnly: true,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: usernameController,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixIcon: Icon(PiconsRegular.user),
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: passwordController,
          obscureText: obscurePassword,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(PiconsRegular.lock),
            suffixIcon: IconButton(
              icon: Icon(
                obscurePassword ? PiconsRegular.eye : PiconsRegular.eyeSlash,
              ),
              onPressed: onTogglePassword,
            ),
          ),
        ),
      ],
    );
  }
}
