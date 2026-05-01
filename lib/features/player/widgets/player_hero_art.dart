import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

const double kPlayerArtCornerRadius = 20;

String playerArtHeroTag(String mediaId) => 'jelly-now-art-$mediaId';

class PlayerHeroArt extends StatelessWidget {
  const PlayerHeroArt({
    required this.size,
    required this.mediaItem,
    this.hero = true,
    super.key,
  });

  final double size;
  final MediaItem mediaItem;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(kPlayerArtCornerRadius);
    final artUri = mediaItem.artUri;
    final isLocal = artUri?.scheme == 'file';
    final child = ClipRRect(
      borderRadius: r,
      child: SizedBox(
        width: size,
        height: size,
        child: artUri == null
            ? const _ArtFallback()
            : isLocal
            ? Image(
                image: FileImage(File(artUri.toFilePath())),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _ArtFallback(),
              )
            : CachedNetworkImage(
                imageUrl: artUri.toString(),
                fit: BoxFit.cover,
                placeholder: (_, __) => const _ArtFallback(),
                errorWidget: (_, __, ___) => const _ArtFallback(),
              ),
      ),
    );
    if (!hero) return child;
    return Hero(
      tag: playerArtHeroTag(mediaItem.id),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class _ArtFallback extends StatelessWidget {
  const _ArtFallback();
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceElevated,
      child: const Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 64,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}
