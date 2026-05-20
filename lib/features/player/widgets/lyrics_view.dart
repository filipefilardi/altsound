import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/empty_state.dart';
import 'package:altsound/core/widgets/error_state.dart';
import 'package:altsound/core/widgets/skeleton.dart';
import 'package:altsound/data/jellyfin/models/lyrics.dart';
import 'package:altsound/features/player/lyrics_provider.dart';
import 'package:altsound/features/player/player_providers.dart';

/// Renders the lyrics for [trackId]. Designed to fill its parent's bounds —
/// place it inside an [Expanded] so it can scroll within the available space.
class LyricsView extends ConsumerWidget {
  const LyricsView({required this.trackId, super.key});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lyricsProvider(trackId));
    return async.when(
      loading: () => const _LoadingLyrics(),
      error: (_, _) => ErrorStateView(
        icon: PiconsRegular.cloudSlash,
        title: 'Could not load lyrics',
        message: 'Check your connection and try again.',
        onRetry: () => ref.invalidate(lyricsProvider(trackId)),
      ),
      data: (lyrics) {
        if (lyrics == null || lyrics.isEmpty) {
          return const EmptyState(
            icon: PiconsRegular.microphoneStage,
            title: 'No lyrics available',
            message: 'This track has no lyrics on the Jellyfin server.',
          );
        }
        return lyrics.isSynced
            ? _SyncedLyrics(lyrics: lyrics)
            : _PlainLyrics(lyrics: lyrics);
      },
    );
  }
}

class _LoadingLyrics extends StatelessWidget {
  const _LoadingLyrics();

  static const _widths = <double>[
    0.85,
    0.7,
    0.9,
    0.6,
    0.8,
    0.75,
    0.65,
    0.55,
    0.8,
    0.7,
  ];

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width;
    return Skeleton.group(
      // ListView (not Column) so the placeholder gracefully scrolls when the
      // available height is shorter than the rendered shimmer rows.
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xl,
        ),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _widths.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Center(
            child: Skeleton.line(
              width: maxWidth * _widths[i] * 0.8,
              height: 16,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({required this.lyrics});

  final Lyrics lyrics;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: lyrics.lines.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          lyrics.lines[i].text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppColors.textPrimary,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _SyncedLyrics extends ConsumerStatefulWidget {
  const _SyncedLyrics({required this.lyrics});

  final Lyrics lyrics;

  @override
  ConsumerState<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  int _activeIndex = -1;
  bool _userScrollPaused = false;
  DateTime? _lastUserScroll;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  int _findActiveIndex(Duration position) {
    final lines = widget.lyrics.lines;
    int lo = 0;
    int hi = lines.length - 1;
    int best = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final start = lines[mid].start;
      if (start == null || start <= position) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }

  void _scrollToActive() {
    if (_activeIndex < 0 || _userScrollPaused) return;
    final ctx = _keys[_activeIndex]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.4,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  void _markUserScroll() {
    _lastUserScroll = DateTime.now();
    if (!_userScrollPaused) setState(() => _userScrollPaused = true);
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      final last = _lastUserScroll;
      if (last == null) return;
      if (DateTime.now().difference(last) >= const Duration(seconds: 4)) {
        setState(() => _userScrollPaused = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(effectivePositionProvider);
    final newIndex = _findActiveIndex(position);
    if (newIndex != _activeIndex) {
      _activeIndex = newIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToActive();
      });
    }

    final activeStyle = GoogleFonts.fraunces(
      textStyle: Theme.of(context).textTheme.titleLarge,
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w600,
      height: 1.35,
    );
    final inactiveStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: AppColors.textSecondary.withValues(alpha: 0.55),
      height: 1.4,
    );

    return NotificationListener<UserScrollNotification>(
      onNotification: (n) {
        if (n.direction != ScrollDirection.idle) _markUserScroll();
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        itemCount: widget.lyrics.lines.length,
        itemBuilder: (_, i) {
          final line = widget.lyrics.lines[i];
          final isActive = i == _activeIndex;
          return Padding(
            key: _keyFor(i),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: line.start == null
                  ? null
                  : () {
                      ref.read(playerControllerProvider).seek(line.start!);
                      if (_userScrollPaused) {
                        setState(() => _userScrollPaused = false);
                      }
                    },
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style:
                    (isActive ? activeStyle : inactiveStyle) ??
                    const TextStyle(),
                textAlign: TextAlign.center,
                child: Text(
                  line.text.isEmpty ? '♪' : line.text,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
