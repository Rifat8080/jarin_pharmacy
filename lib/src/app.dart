import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class PharmacyApp extends ConsumerWidget {
  const PharmacyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Jarin Pharmacy',
      initialRoute: AppRoutes.home,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case AppRoutes.home:
            return MaterialPageRoute(
              builder: (_) => const PharmacyHomePage(initialTab: 0),
              settings: settings,
            );
          case AppRoutes.sell:
            return MaterialPageRoute(
              builder: (_) => const PharmacyHomePage(initialTab: 1),
              settings: settings,
            );
          case AppRoutes.stock:
            return MaterialPageRoute(
              builder: (_) => const PharmacyHomePage(initialTab: 2),
              settings: settings,
            );
          case AppRoutes.bkash:
            return MaterialPageRoute(
              builder: (_) => const PharmacyHomePage(initialTab: 3),
              settings: settings,
            );
          case AppRoutes.reports:
            return MaterialPageRoute(
              builder: (_) => const PharmacyHomePage(initialTab: 4),
              settings: settings,
            );
          case AppRoutes.invoices:
            return MaterialPageRoute(
              builder: (_) => const InvoiceListPage(),
              settings: settings,
            );
          case AppRoutes.invoiceShow:
            final invoiceId = settings.arguments as String?;
            return MaterialPageRoute(
              builder: (_) => InvoiceDetailsPage(invoiceId: invoiceId ?? ''),
              settings: settings,
            );
          case AppRoutes.customers:
            return MaterialPageRoute(
              builder: (_) => const PharmacyHomePage(initialTab: 5),
              settings: settings,
            );
          case AppRoutes.customerShow:
            final customerId = settings.arguments as String?;
            return MaterialPageRoute(
              builder: (_) => CustomerProfilePage(customerId: customerId ?? ''),
              settings: settings,
            );
        }

        return MaterialPageRoute(
          builder: (_) => const PharmacyHomePage(initialTab: 0),
          settings: settings,
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: baseScheme,
        scaffoldBackgroundColor: baseScheme.surface,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        splashFactory: InkRipple.splashFactory,
        hoverColor: baseScheme.primary.withValues(alpha: 0.06),
        focusColor: baseScheme.primary.withValues(alpha: 0.10),
        textTheme: Typography.blackCupertino.copyWith(
          titleLarge: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: const TextStyle(fontWeight: FontWeight.w600),
          bodyMedium: const TextStyle(letterSpacing: 0.1),
        ),
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: baseScheme.surface,
          foregroundColor: baseScheme.onSurface,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: Color(0xFF1F2937),
          ),
        ),
        cardTheme: CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: baseScheme.surfaceContainerLow,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: baseScheme.outlineVariant),
          ),
        ),
        listTileTheme: ListTileThemeData(
          dense: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          iconColor: baseScheme.onSurfaceVariant,
          textColor: baseScheme.onSurface,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: baseScheme.surfaceContainerLow,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: baseScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: baseScheme.primary, width: 1.4),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            ),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return baseScheme.onPrimary.withValues(alpha: 0.18);
              }
              if (states.contains(WidgetState.hovered)) {
                return baseScheme.onPrimary.withValues(alpha: 0.12);
              }
              if (states.contains(WidgetState.focused)) {
                return baseScheme.onPrimary.withValues(alpha: 0.14);
              }
              return null;
            }),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            side: WidgetStatePropertyAll(
              BorderSide(color: baseScheme.outlineVariant),
            ),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return baseScheme.primary.withValues(alpha: 0.16);
              }
              if (states.contains(WidgetState.hovered)) {
                return baseScheme.primary.withValues(alpha: 0.08);
              }
              if (states.contains(WidgetState.focused)) {
                return baseScheme.primary.withValues(alpha: 0.12);
              }
              return null;
            }),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: baseScheme.surface,
          indicatorColor: baseScheme.secondaryContainer,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? baseScheme.onSecondaryContainer
                  : baseScheme.onSurfaceVariant,
            );
          }),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: baseScheme.outlineVariant,
          thickness: 1,
          space: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
