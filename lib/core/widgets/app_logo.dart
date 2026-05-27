import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppLogo extends StatelessWidget {
  final String? logoUrl;
  final double size;
  final double borderRadius;

  const AppLogo({
    super.key,
    this.logoUrl,
    this.size = 90,
    this.borderRadius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final url = logoUrl;
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('data:image')) {
        return _Base64Logo(url: url, size: size, borderRadius: borderRadius);
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.contain,
          placeholder: (_, __) => _Shimmer(size: size, borderRadius: borderRadius),
          errorWidget: (_, __, ___) => _DefaultIcon(size: size, borderRadius: borderRadius),
        ),
      );
    }
    return _DefaultIcon(size: size, borderRadius: borderRadius);
  }
}

class _Base64Logo extends StatelessWidget {
  final String url;
  final double size;
  final double borderRadius;

  const _Base64Logo({
    required this.url,
    required this.size,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final bytes = base64Decode(url.substring(url.indexOf(',') + 1));
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.memory(bytes, width: size, height: size, fit: BoxFit.contain),
      );
    } catch (_) {
      return _DefaultIcon(size: size, borderRadius: borderRadius);
    }
  }
}

class _Shimmer extends StatelessWidget {
  final double size;
  final double borderRadius;
  const _Shimmer({required this.size, required this.borderRadius});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      );
}

class _DefaultIcon extends StatelessWidget {
  final double size;
  final double borderRadius;
  const _DefaultIcon({required this.size, required this.borderRadius});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Icon(
          Icons.local_shipping_rounded,
          color: Colors.white,
          size: size * 0.55,
        ),
      );
}
