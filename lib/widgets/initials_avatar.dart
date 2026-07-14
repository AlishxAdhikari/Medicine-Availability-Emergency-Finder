import 'package:flutter/material.dart';

/// A circular avatar that shows the user's initials on a deterministic
/// colored background, used anywhere the app needs to represent "the
/// current user" without depending on a real uploaded photo.
///
/// If [imageUrl] is provided and non-empty, it's shown instead (so this
/// widget also doubles as the single place to swap in a real profile photo
/// later, e.g. once photo upload is implemented). Until then, every screen
/// shows the actual logged-in user's initials instead of a stock photo or a
/// broken asset reference.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 20,
    this.backgroundColor,
    this.textColor = Colors.white,
  });

  /// The name to derive initials from, e.g. `profile.fullName`.
  final String name;

  /// Optional real photo URL. When present and non-empty, this is shown
  /// instead of the initials.
  final String? imageUrl;

  /// Avatar radius in logical pixels (diameter is `radius * 2`).
  final double radius;

  /// Override the deterministic background color if needed.
  final Color? backgroundColor;

  final Color textColor;

  /// Small, muted palette that reads well with white text in both themes.
  static const List<Color> _palette = [
    Color(0xFF6750A4),
    Color(0xFF00696D),
    Color(0xFF984061),
    Color(0xFF8B5000),
    Color(0xFF3D5AFE),
    Color(0xFF00897B),
    Color(0xFF5D4037),
    Color(0xFF455A64),
  ];

  /// Up to two initials: first letter of the first word + first letter of
  /// the last word (e.g. "Anurodh Sharma" -> "AS"). Falls back to "?" for
  /// an empty/blank name, and a single letter for a single-word name.
  static String initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  /// Picks a color from [_palette] based on the name, so the same person
  /// always gets the same color rather than a random one on every rebuild.
  static Color _colorFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return _palette.first;
    final sum = trimmed.toLowerCase().codeUnits.fold<int>(0, (acc, c) => acc + c);
    return _palette[sum % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(imageUrl!),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? _colorFor(name),
      child: Text(
        initialsFor(name),
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.72,
        ),
      ),
    );
  }
}