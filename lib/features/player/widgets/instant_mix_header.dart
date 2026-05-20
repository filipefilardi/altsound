import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:palette_generator/palette_generator.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/artwork_placeholder.dart';
import 'package:altsound/core/widgets/local_or_network_image.dart';

/// Header for the Instant Mix detail screen — sparkle-themed artwork tile
/// over a vertical gradient, with "Instant Mix" label, seed title, and track
/// count.
class InstantMixHeader extends StatelessWidget {
  const InstantMixHeader({
    required this.seedTitle,
    required this.artworkUrl,
    required this.trackCount,
    super.key,
  });

  final String? seedTitle;
  final String? artworkUrl;
  final int trackCount;

  @override
  Widget build(BuildContext context) {
    return _InstantMixHeaderBody(
      seedTitle: seedTitle,
      artworkUrl: artworkUrl,
      trackCount: trackCount,
    );
  }
}

class _InstantMixHeaderBody extends StatefulWidget {
  const _InstantMixHeaderBody({
    required this.seedTitle,
    required this.artworkUrl,
    required this.trackCount,
  });

  final String? seedTitle;
  final String? artworkUrl;
  final int trackCount;

  @override
  State<_InstantMixHeaderBody> createState() => _InstantMixHeaderBodyState();
}

class _InstantMixHeaderBodyState extends State<_InstantMixHeaderBody> {
  Color _backdrop = AppColors.surfaceElevated;

  @override
  void initState() {
    super.initState();
    _extractPalette();
  }

  @override
  void didUpdateWidget(covariant _InstantMixHeaderBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artworkUrl != widget.artworkUrl) {
      _extractPalette();
    }
  }

  Future<void> _extractPalette() async {
    final url = widget.artworkUrl;
    if (url == null || !url.startsWith('http')) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        size: const Size(200, 200),
        maximumColorCount: 8,
      );
      final c =
          palette.dominantColor?.color ??
          palette.vibrantColor?.color ??
          palette.darkVibrantColor?.color;
      if (c != null && mounted) {
        setState(
          () => _backdrop = Color.alphaBlend(
            c.withValues(alpha: 0.55),
            AppColors.background,
          ),
        );
      }
    } catch (_) {
      // ignore palette failures
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.seedTitle?.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _backdrop,
            Color.alphaBlend(
              _backdrop.withValues(alpha: 0.5),
              AppColors.background,
            ),
            AppColors.background,
          ],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textBlockHeight = widget.trackCount > 0 ? 86.0 : 66.0;
          final artSize = (constraints.maxHeight - textBlockHeight).clamp(
            96.0,
            220.0,
          );

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                      spreadRadius: -6,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    width: artSize,
                    height: artSize,
                    child: LocalOrNetworkImage(
                      source: widget.artworkUrl,
                      placeholderBuilder: (_) => const ArtworkPlaceholder(
                        icon: PiconsRegular.sparkle,
                        iconSize: 64,
                        iconColor: AppColors.primary,
                      ),
                      errorBuilder: (_) => const ArtworkPlaceholder(
                        icon: PiconsRegular.sparkle,
                        iconSize: 64,
                        iconColor: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Instant Mix',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                title == null || title.isEmpty
                    ? 'Generated by Jellyfin'
                    : title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (widget.trackCount > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${widget.trackCount} song${widget.trackCount == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
