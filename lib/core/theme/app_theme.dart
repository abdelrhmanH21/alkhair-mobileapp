import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Palette: dairy-trust blue + white, warm gold accent ─────────────────────
  static const Color primary   = Color(0xFF0D47B1); // deep trustworthy navy-blue
  static const Color secondary = Color(0xFF1565C0); // lighter, energetic blue
  static const Color accent    = Color(0xFFF5A623); // warm gold — CTAs/highlights
  static const Color danger    = Color(0xFFD32F2F);
  static const Color surface   = Color(0xFFF7F9FC); // off-white, cool tint
  static const Color cardBg    = Colors.white;

  // ── Elevation tokens ──────────────────────────────────────────────────────
  static const double elevationLow  = 1.5;
  static const double elevationMed  = 4.0;
  static const double elevationHigh = 8.0;
  static const Color shadowColor    = Color(0x1A0D47B1); // soft, tinted shadow

  static TextTheme get _textTheme => GoogleFonts.cairoTextTheme().copyWith(
        headlineMedium: GoogleFonts.cairo(
            fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87),
        titleLarge: GoogleFonts.cairo(
            fontSize: 19, fontWeight: FontWeight.bold, color: Colors.black87),
        titleMedium: GoogleFonts.cairo(
            fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
        bodyLarge: GoogleFonts.cairo(fontSize: 15, color: Colors.black87),
        bodyMedium: GoogleFonts.cairo(fontSize: 13, color: Colors.black54),
        labelSmall: GoogleFonts.cairo(
            fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54),
      );

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          secondary: secondary,
          surface: surface,
          error: danger,
        ),
        scaffoldBackgroundColor: surface,
        textTheme: _textTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: GoogleFonts.cairo(
              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        cardTheme: CardThemeData(
          color: cardBg,
          elevation: elevationLow,
          shadowColor: shadowColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          elevation: elevationMed,
          indicatorColor: primary.withValues(alpha: 0.12),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected ? primary : Colors.grey.shade600,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(color: selected ? primary : Colors.grey.shade500);
          }),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: elevationLow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}
