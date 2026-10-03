import 'package:flutter/material.dart';

import '../../core/models/team.dart';
import '../theme/app_theme.dart';

/// Procedural club crest: rounded shield filled with the club color and the
/// club's initials. No image assets required.
///
/// [heroTag] opts the crest into a [Hero] transition. It is off by default
/// because two crests for the same club on one screen (an app bar and a
/// fixture card, say) would otherwise register duplicate hero tags and throw.
class ClubCrest extends StatelessWidget {
  const ClubCrest({
    super.key,
    required this.team,
    this.size = 40,
    this.heroTag,
  });

  final Team team;
  final double size;

  /// When set, the crest participates in a [Hero] animation under this tag.
  final String? heroTag;

  Color get _clubColor {
    final hex = team.color.replaceFirst('#', '');
    if (hex.length == 6) {
      final value = int.tryParse('FF$hex', radix: 16);
      if (value != null) return Color(value);
    }
    return AppTheme.pitchGreen;
  }

  String get _initials {
    final source = team.shortName.isNotEmpty ? team.shortName : team.name;
    final words = source
        .split(RegExp(r'[\s_]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length >= 2) {
      return (words[0][0] + words[1][0]).toUpperCase();
    }
    return source.substring(0, source.length.clamp(1, 3)).toUpperCase();
  }

  bool get _isLightClubColor {
    final c = _clubColor;
    final luminance =
        0.299 * (c.r * 255.0) + 0.587 * (c.g * 255.0) + 0.114 * (c.b * 255.0);
    return luminance > 160;
  }

  @override
  Widget build(BuildContext context) {
    final contrast = _isLightClubColor ? Colors.black87 : Colors.white;
    final crest = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _clubColor,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          color: contrast,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
          letterSpacing: 0.5,
        ),
      ),
    );
    final tag = heroTag;
    return tag == null ? crest : Hero(tag: tag, child: crest);
  }
}
