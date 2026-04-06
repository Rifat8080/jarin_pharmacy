import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/auth_controller.dart';
import 'presentation/auth_gate.dart';
import 'presentation/app_controller.dart';
import 'presentation/app_routes.dart';
import 'presentation/home_page.dart';
import 'presentation/invoice_pages.dart';

final appControllerProvider = ChangeNotifierProvider<PharmacyAppController>((
  ref,
) {
  final controller = PharmacyAppController();
  controller.initialize();
  return controller;
});

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  final controller = AuthController();
  controller.initialize();
  return controller;
});

class PharmacyApp extends ConsumerWidget {
  const PharmacyApp({super.key});

  Widget _protected(Widget child) {
    return AuthGate(child: child);
  }

  PageRoute<T> _instantRoute<T>({
    required Widget child,
    required RouteSettings settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => child,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const seedColor = Color(0xFF2563EB);
    final generatedScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    final baseScheme = generatedScheme.copyWith(
      primary: const Color(0xFF2563EB),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDCEBFF),
      onPrimaryContainer: const Color(0xFF0A2A66),
      secondary: const Color(0xFF0EA5E9),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFD9F2FF),
      onSecondaryContainer: const Color(0xFF083B52),
      tertiary: const Color(0xFF60A5FA),
      onTertiary: const Color(0xFF062B5B),
      tertiaryContainer: const Color(0xFFE4F0FF),
      onTertiaryContainer: const Color(0xFF0C3266),
      surface: const Color(0xFFF7FBFF),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF3F8FF),
      surfaceContainer: const Color(0xFFECF5FF),
      surfaceContainerHigh: const Color(0xFFE4F0FF),
      surfaceContainerHighest: const Color(0xFFD7E8FF),
      outline: const Color(0xFFA8C5E8),
      outlineVariant: const Color(0xFFD6E8FF),
      shadow: const Color(0xFF7FA8D6),
      scrim: const Color(0xFF0A2540),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Jarin Pharmacy',
      themeAnimationCurve: Curves.easeOut,
      themeAnimationDuration: Duration.zero,
      initialRoute: AppRoutes.home,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case AppRoutes.home:
            return _instantRoute(
              child: _protected(const PharmacyHomePage(initialTab: 0)),
              settings: settings,
            );
          case AppRoutes.sell:
            return _instantRoute(
              child: _protected(const PharmacyHomePage(initialTab: 1)),
              settings: settings,
            );
          case AppRoutes.stock:
            return _instantRoute(
              child: _protected(const PharmacyHomePage(initialTab: 2)),
              settings: settings,
            );
          case AppRoutes.bkash:
            return _instantRoute(
              child: _protected(const PharmacyHomePage(initialTab: 3)),
              settings: settings,
            );
          case AppRoutes.reports:
            return _instantRoute(
              child: _protected(const PharmacyHomePage(initialTab: 4)),
              settings: settings,
            );
          case AppRoutes.invoices:
            return _instantRoute(
              child: _protected(const InvoiceListPage()),
              settings: settings,
            );
          case AppRoutes.invoiceShow:
            final invoiceId = settings.arguments as String?;
            return _instantRoute(
              child: _protected(InvoiceDetailsPage(invoiceId: invoiceId ?? '')),
              settings: settings,
            );
          case AppRoutes.customers:
            return _instantRoute(
              child: _protected(const PharmacyHomePage(initialTab: 5)),
              settings: settings,
            );
          case AppRoutes.customerShow:
            final customerId = settings.arguments as String?;
            return _instantRoute(
              child: _protected(CustomerProfilePage(customerId: customerId ?? '')),
              settings: settings,
            );
        }

        return _instantRoute(
          child: _protected(const PharmacyHomePage(initialTab: 0)),
          settings: settings,
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: baseScheme,
        scaffoldBackgroundColor: const Color(0xFFEFF6FF),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        splashFactory: InkRipple.splashFactory,
        hoverColor: baseScheme.primary.withValues(alpha: 0.06),
        focusColor: baseScheme.primary.withValues(alpha: 0.10),
        textTheme: Typography.blackMountainView.copyWith(
          displaySmall: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
          headlineMedium: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          headlineSmall: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleLarge: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          titleSmall: const TextStyle(fontWeight: FontWeight.w600),
          bodyLarge: const TextStyle(letterSpacing: 0.0),
          bodyMedium: const TextStyle(letterSpacing: 0.0),
          labelLarge: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.0,
          ),
        ),
        appBarTheme: AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: baseScheme.surface,
          foregroundColor: const Color(0xFF111827),
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          shadowColor: baseScheme.shadow.withValues(alpha: 0.12),
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: Color(0xFF111827),
          ),
        ),
        cardTheme: CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: baseScheme.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        listTileTheme: ListTileThemeData(
          dense: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          iconColor: baseScheme.onSurfaceVariant,
          textColor: const Color(0xFF111827),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7FBFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD6E8FF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: baseScheme.primary, width: 1.6),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          floatingLabelStyle: TextStyle(
            color: baseScheme.primary,
            fontWeight: FontWeight.w600,
          ),
          hintStyle: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontWeight: FontWeight.w400,
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            elevation: const WidgetStatePropertyAll(0),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            ),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return baseScheme.onPrimary.withValues(alpha: 0.18);
              }
              if (states.contains(WidgetState.hovered)) {
                return baseScheme.onPrimary.withValues(alpha: 0.12);
              }
              return null;
            }),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            side: WidgetStatePropertyAll(
              BorderSide(color: baseScheme.outlineVariant),
            ),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return baseScheme.primary.withValues(alpha: 0.14);
              }
              if (states.contains(WidgetState.hovered)) {
                return baseScheme.primary.withValues(alpha: 0.06);
              }
              return null;
            }),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return baseScheme.primary.withValues(alpha: 0.08);
              }
              if (states.contains(WidgetState.pressed)) {
                return baseScheme.primary.withValues(alpha: 0.14);
              }
              return null;
            }),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          highlightElevation: 2,
          backgroundColor: baseScheme.primary,
          foregroundColor: baseScheme.onPrimary,
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          side: BorderSide(color: baseScheme.outlineVariant),
          backgroundColor: const Color(0xFFF7FBFF),
          selectedColor: baseScheme.primaryContainer,
          showCheckmark: false,
          labelStyle: TextStyle(
            color: baseScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        dialogTheme: DialogThemeData(
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: baseScheme.surfaceContainerLowest,
          indicatorColor: baseScheme.primaryContainer,
          elevation: 0,
          height: 68,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 11,
              color: selected
                  ? baseScheme.onPrimaryContainer
                  : baseScheme.onSurfaceVariant,
            );
          }),
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: baseScheme.primary,
          linearTrackColor: baseScheme.primaryContainer.withValues(alpha: 0.5),
          circularTrackColor: baseScheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: const Color(0xFF123B63),
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          },
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFD6E8FF),
          thickness: 1,
          space: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF123B63),
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        badgeTheme: BadgeThemeData(
          backgroundColor: baseScheme.error,
          textColor: baseScheme.onError,
          smallSize: 8,
        ),
      ),
    );
  }
}
