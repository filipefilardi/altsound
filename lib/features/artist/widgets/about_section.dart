import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/data/wikipedia/wikipedia_repository.dart';

/// Renders the "About" sliver for the artist screen using the Wikipedia bio
/// from [artistBioProvider]. Hides itself when no bio is available.
class AboutSection extends ConsumerWidget {
  const AboutSection({required this.artistName, super.key});
  final String artistName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bio = ref.watch(artistBioProvider(artistName)).value;
    if (bio == null || bio.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _ExpandableBio(bio: bio),
          ],
        ),
      ),
    );
  }
}

class _ExpandableBio extends StatefulWidget {
  const _ExpandableBio({required this.bio});
  final String bio;

  @override
  State<_ExpandableBio> createState() => _ExpandableBioState();
}

class _ExpandableBioState extends State<_ExpandableBio> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Text(
        widget.bio,
        maxLines: _expanded ? null : 3,
        overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}
