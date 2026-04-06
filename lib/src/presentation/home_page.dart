import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../core/backup/backup_service.dart';
import '../core/backup/save_file_helper.dart';
import '../domain/models.dart';
import 'app_controller.dart';
import 'app_routes.dart';
import 'invoice_pages.dart';

const int _lowStockThreshold = 10;
const int _criticalStockThreshold = 3;
const Duration _microAnimationDuration = Duration(milliseconds: 90);

String _money(num value) {
  return NumberFormat.currency(symbol: '৳', decimalDigits: 2).format(value);
}

String _dateTimeLabel(DateTime value) {
  return DateFormat('dd MMM yyyy, hh:mm a').format(value);
}

String _categoryLabel(ProductCategory category) {
  return switch (category) {
    ProductCategory.medicine => 'Medicine',
    ProductCategory.stationery => 'Stationery',
  };
}

String _bkashTypeLabel(BkashType type) {
  return switch (type) {
    BkashType.cashIn => 'Cash In',
    BkashType.cashOut => 'Cash Out',
    BkashType.sendMoney => 'Send Money',
    BkashType.billPayment => 'Bill Payment',
    BkashType.commission => 'Commission',
    BkashType.transfer => 'Transfer',
  };
}

String _stockDisplay(Product product) {
  if (product.trackInPieces && product.unitsPerPack > 1) {
    final packs = product.stockQty ~/ product.unitsPerPack;
    final pieces = product.stockQty % product.unitsPerPack;
    return '$packs pack, $pieces pcs';
  }
  return '${product.stockQty} units';
}

String _stockShortDisplay(Product product) {
  if (product.trackInPieces && product.unitsPerPack > 1) {
    final packs = product.stockQty ~/ product.unitsPerPack;
    final pieces = product.stockQty % product.unitsPerPack;
    return '${packs}P ${pieces}pc';
  }
  return '${product.stockQty}';
}

String _quantityDisplay(Product product, int quantity) {
  if (product.trackInPieces && product.unitsPerPack > 1) {
    final packs = quantity ~/ product.unitsPerPack;
    final pieces = quantity % product.unitsPerPack;
    return '$packs pack, $pieces pcs';
  }
  return '$quantity units';
}

String _deltaQuantityDisplay(Product? product, int deltaQuantity) {
  final sign = deltaQuantity >= 0 ? '+' : '-';
  final absolute = deltaQuantity.abs();

  if (product != null && product.trackInPieces && product.unitsPerPack > 1) {
    final packs = absolute ~/ product.unitsPerPack;
    final pieces = absolute % product.unitsPerPack;
    return '$sign$packs pack, $pieces pcs';
  }

  return '$sign$absolute units';
}

double? _extractDgdaPrice(DgdaMedicine medicine) {
  final texts = <String>{
    medicine.packageContainer,
    medicine.packageSize,
    medicine.allData['medicine_package_container'] ?? '',
    medicine.allData['medicine_package_size'] ?? '',
  };

  final unitPattern = RegExp(
    r'unit\s*price\s*:\s*৳\s*([0-9]+(?:\.[0-9]+)?)',
    caseSensitive: false,
  );
  final currencyPattern = RegExp(r'৳\s*([0-9]+(?:\.[0-9]+)?)');

  for (final text in texts) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      continue;
    }

    final unitMatch = unitPattern.firstMatch(normalized);
    if (unitMatch != null) {
      final parsed = double.tryParse(unitMatch.group(1) ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
  }

  for (final text in texts) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      continue;
    }

    final currencyMatch = currencyPattern.firstMatch(normalized);
    if (currencyMatch != null) {
      final parsed = double.tryParse(currencyMatch.group(1) ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
  }

  return null;
}

int? _extractDgdaUnitsPerPack(DgdaMedicine medicine) {
  final texts = <String>{
    medicine.packageContainer,
    medicine.packageSize,
    medicine.allData['medicine_package_container'] ?? '',
    medicine.allData['medicine_package_size'] ?? '',
  };

  final packPattern = RegExp(r"\(?\s*(\d+)\s*'s\s*pack", caseSensitive: false);

  for (final text in texts) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      continue;
    }

    final match = packPattern.firstMatch(normalized);
    if (match == null) {
      continue;
    }

    final parsed = int.tryParse(match.group(1) ?? '');
    if (parsed != null && parsed > 0) {
      return parsed;
    }
  }

  return null;
}

String _formatDgdaFieldLabel(String rawKey) {
  final withSpaces = rawKey.replaceAll('_', ' ').trim();
  if (withSpaces.isEmpty) {
    return withSpaces;
  }

  final words = withSpaces.split(RegExp(r'\s+'));
  return words
      .map((word) {
        if (word.isEmpty) {
          return word;
        }
        return '${word[0].toUpperCase()}${word.substring(1)}';
      })
      .join(' ');
}

String _cleanDgdaFieldValue(String value) {
  var cleaned = value;
  cleaned = cleaned.replaceAll(RegExp(r'<[^>]*>'), ' ');
  cleaned = cleaned.replaceAll('&nbsp;', ' ');
  cleaned = cleaned.replaceAll('&amp;', '&');
  cleaned = cleaned.replaceAll('&quot;', '"');
  cleaned = cleaned.replaceAll('&#39;', "'");
  cleaned = cleaned.replaceAll('&lt;', '<');
  cleaned = cleaned.replaceAll('&gt;', '>');
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned;
}

class _SellCartItem {
  _SellCartItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
  });

  final Product product;
  int quantity;
  double unitPrice;

  double get total => quantity * unitPrice;
}

class PharmacyHomePage extends ConsumerStatefulWidget {
  const PharmacyHomePage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<PharmacyHomePage> createState() => _PharmacyHomePageState();
}

class _PharmacyHomePageState extends ConsumerState<PharmacyHomePage> {
  int _selectedTab = 0;

  String get _activeTabTitle {
    return switch (_selectedTab) {
      0 => 'Jarin Pharmacy',
      1 => 'Sell',
      2 => 'Stock',
      3 => 'bKash',
      4 => 'Reports',
      5 => 'Customers',
      _ => 'Jarin Pharmacy',
    };
  }

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final lowStockCount = controller.products
        .where(
          (product) =>
              product.stockQty > 0 && product.stockQty <= _lowStockThreshold,
        )
        .length;
    final outOfStockCount = controller.products
        .where((product) => product.stockQty == 0)
        .length;

    final selectedPage = switch (_selectedTab) {
      0 => _DashboardTab(controller: controller, onNavigate: _navigateTo),
      1 => _SellTab(controller: controller),
      2 => _InventoryTab(controller: controller),
      3 => _BkashTab(controller: controller),
      4 => _ReportsTab(controller: controller, onPickDate: _pickReportDate),
      5 => const CustomerListPage(showScaffold: false),
      _ => _DashboardTab(controller: controller, onNavigate: _navigateTo),
    };

    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 860;
    final isWideRail = width >= 1200;

    Widget tabContent = Column(
      children: [
        if (controller.errorMessage != null)
          MaterialBanner(
            content: Text(controller.errorMessage!),
            actions: [
              TextButton(
                onPressed: controller.refreshAll,
                child: const Text('Retry'),
              ),
            ],
          ),
        Expanded(child: selectedPage),
      ],
    );

    if (useRail) {
      return Scaffold(
        backgroundColor: const Color(0xFFEFF6FF),
        body: Stack(
          children: [
            Row(
              children: [
                _buildDesktopRail(
                  isWideRail,
                  lowStockCount + outOfStockCount,
                  controller,
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: scheme.outlineVariant,
                ),
                Expanded(child: tabContent),
              ],
            ),
            if (controller.isLoading)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: scheme.scrim.withValues(alpha: 0.06),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFEFF6FF),
      appBar: _buildMobileAppBar(scheme),
      body: Stack(
        children: [
          tabContent,
          if (controller.isLoading)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: scheme.scrim.withValues(alpha: 0.06),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(lowStockCount, outOfStockCount),
    );
  }

  PreferredSizeWidget _buildMobileAppBar(ColorScheme scheme) {
    return AppBar(
      toolbarHeight: 58,
      titleSpacing: 16,
      elevation: 0,
      shadowColor: scheme.shadow.withValues(alpha: 0.12),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.secondary],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                'JP',
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _activeTabTitle,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ],
      ),
      actions: [
        IconButton.filledTonal(
          tooltip: 'Lock app',
          onPressed: () => ref.read(authControllerProvider).lock(),
          icon: const Icon(Icons.lock_outline, size: 18),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Backup & Restore',
          onPressed: () => _showBackupDialog(context),
          icon: Icon(Icons.backup_outlined, size: 18, color: scheme.onSurface),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Profile',
          onPressed: () => _showProfileDialog(context),
          icon: Icon(
            Icons.manage_accounts_outlined,
            size: 18,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildDesktopRail(
    bool wide,
    int alertBadge,
    PharmacyAppController controller,
  ) {
    const sideColor = Color(0xFF0A2540);
    const selectedHighlight = Color(0xFF2563EB);
    const selectedIcon = Color(0xFF93C5FD);
    const unselectedIcon = Color(0xFF7DA8D6);
    const labelColor = Color(0xFFD7EAFE);

    final items = [
      (Icons.home_outlined, Icons.home_rounded, 'Home'),
      (Icons.point_of_sale_outlined, Icons.point_of_sale_rounded, 'Sell'),
      (Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Stock'),
      (
        Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet_rounded,
        'bKash',
      ),
      (Icons.query_stats_outlined, Icons.query_stats_rounded, 'Reports'),
      (Icons.people_outline, Icons.people_rounded, 'Customers'),
    ];

    return Container(
      width: wide ? 200 : 68,
      color: sideColor,
      child: Column(
        children: [
          // ── Logo header ──
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 14 : 8,
              vertical: 20,
            ),
            child: wide
                ? Row(
                    children: [
                      _buildLogoChip(),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Jarin',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              'Pharmacy',
                              style: TextStyle(
                                color: Color(0xFF9CC3E9),
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Center(child: _buildLogoChip()),
          ),
          // ── Nav items ──
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: wide ? 8 : 6),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final sel = index == _selectedTab;
                final hasBadge = index == 2 && alertBadge > 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Tooltip(
                    message: wide ? '' : item.$3,
                    preferBelow: false,
                    child: InkWell(
                      onTap: () => _navigateTo(index),
                      borderRadius: BorderRadius.circular(10),
                      hoverColor: Colors.white.withValues(alpha: 0.06),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: EdgeInsets.symmetric(
                          horizontal: wide ? 12 : 0,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: sel
                              ? selectedHighlight.withValues(alpha: 0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: sel
                              ? Border.all(
                                  color: selectedHighlight.withValues(
                                    alpha: 0.30,
                                  ),
                                )
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: wide
                              ? MainAxisAlignment.start
                              : MainAxisAlignment.center,
                          children: [
                            hasBadge
                                ? Badge(
                                    label: Text('$alertBadge'),
                                    child: Icon(
                                      sel ? item.$2 : item.$1,
                                      color: sel
                                          ? selectedIcon
                                          : unselectedIcon,
                                      size: 22,
                                    ),
                                  )
                                : Icon(
                                    sel ? item.$2 : item.$1,
                                    color: sel ? selectedIcon : unselectedIcon,
                                    size: 22,
                                  ),
                            if (wide) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.$3,
                                  style: TextStyle(
                                    color: sel ? Colors.white : labelColor,
                                    fontWeight: sel
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (sel)
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: selectedIcon,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // ── Bottom utilities ──
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 8 : 6,
              vertical: 12,
            ),
            child: Column(
              children: [
                const Divider(color: Color(0xFF123B63), height: 8),
                const SizedBox(height: 4),
                if (wide)
                  Row(
                    children: [
                      _buildRailIconBtn(
                        icon: Icons.lock_outline,
                        tooltip: 'Lock app',
                        onPressed: () =>
                            ref.read(authControllerProvider).lock(),
                      ),
                      _buildRailIconBtn(
                        icon: Icons.manage_accounts_outlined,
                        tooltip: 'Profile',
                        onPressed: () => _showProfileDialog(context),
                      ),
                      _buildRailIconBtn(
                        icon: Icons.backup_outlined,
                        tooltip: 'Backup & Restore',
                        onPressed: () => _showBackupDialog(context),
                      ),
                      _buildRailIconBtn(
                        icon: Icons.refresh,
                        tooltip: 'Refresh',
                        onPressed: controller.isLoading
                            ? null
                            : controller.refreshAll,
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      _buildRailIconBtn(
                        icon: Icons.lock_outline,
                        tooltip: 'Lock',
                        onPressed: () =>
                            ref.read(authControllerProvider).lock(),
                      ),
                      _buildRailIconBtn(
                        icon: Icons.backup_outlined,
                        tooltip: 'Backup',
                        onPressed: () => _showBackupDialog(context),
                      ),
                      _buildRailIconBtn(
                        icon: Icons.refresh,
                        tooltip: 'Refresh',
                        onPressed: controller.isLoading
                            ? null
                            : controller.refreshAll,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoChip() {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF38BDF8)],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Text(
          'JP',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildRailIconBtn({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 18,
        color: onPressed != null
            ? const Color(0xFF7DA8D6)
            : const Color(0xFF31577E),
      ),
    );
  }

  Widget _buildBottomNav(int lowStockCount, int outOfStockCount) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: NavigationBar(
        height: 68,
        labelBehavior: null,
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          if (index == _selectedTab) {
            return;
          }
          setState(() => _selectedTab = index);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale_rounded),
            label: 'Sell',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: lowStockCount + outOfStockCount > 0,
              label: Text('${lowStockCount + outOfStockCount}'),
              child: const Icon(Icons.inventory_2_outlined),
            ),
            selectedIcon: const Icon(Icons.inventory_2_rounded),
            label: 'Stock',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'bKash',
          ),
          const NavigationDestination(
            icon: Icon(Icons.query_stats_outlined),
            selectedIcon: Icon(Icons.query_stats_rounded),
            label: 'Reports',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Customers',
          ),
        ],
      ),
    );
  }

  void _navigateTo(int index) {
    if (index == _selectedTab) {
      return;
    }
    setState(() => _selectedTab = index);
  }

  Future<void> _pickReportDate() async {
    final controller = ref.read(appControllerProvider);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: controller.reportAnchorDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) {
      return;
    }

    await controller.setReportAnchorDate(pickedDate);
  }

  // ── Backup & Restore ──────────────────────────────────────────────────────

  Future<void> _exportBackup() async {
    final controller = ref.read(appControllerProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preparing backup…'),
        duration: Duration(seconds: 2),
      ),
    );
    try {
      final bytes = await controller.exportBackup();
      final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final filename = 'jarin_pharmacy_backup_$ts.json';
      await saveBackupFile(filename, bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup saved as $filename'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _importBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
      dialogTitle: 'Select Backup File',
    );

    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null || !mounted) return;

    final controller = ref.read(appControllerProvider);

    // Step 1: integrity + format validation
    final validation = await controller.validateBackup(bytes);
    if (!mounted) return;
    if (!validation.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validation.error ?? 'Invalid backup file.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    // Step 2: conflict analysis (no DB writes)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Analysing backup for conflicts…'),
        duration: Duration(seconds: 4),
      ),
    );
    final report = await controller.analyzeConflicts(bytes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // Step 3: show conflict-preview dialog so the user can choose
    final choice = await showDialog<_ImportChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ConflictPreviewDialog(report: report),
    );
    if (choice == null || !mounted) return;

    // Step 4: execute chosen strategy
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          choice == _ImportChoice.merge
              ? 'Merging — adding new records…'
              : 'Restoring — replacing all data…',
        ),
        duration: const Duration(seconds: 4),
      ),
    );

    final ImportResult importResult;
    if (choice == _ImportChoice.merge) {
      importResult = await controller.mergeBackup(bytes);
    } else {
      importResult = await controller.importBackup(bytes);
    }

    if (!mounted) return;
    if (importResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            choice == _ImportChoice.merge
                ? 'Merge complete — new records added, local data preserved.'
                : 'Full restore complete — all data replaced.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(importResult.error ?? 'Import failed.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _showProfileDialog(BuildContext context) {
    final authCtrl = ref.read(authControllerProvider);
    final emailCtrl = TextEditingController(
      text: authCtrl.registeredEmail ?? '',
    );
    final currentPwCtrl = TextEditingController();
    final newPwCtrl = TextEditingController();
    final confirmPwCtrl = TextEditingController();
    var obscureCurrent = true;
    var obscureNew = true;
    var obscureConfirm = true;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.manage_accounts_outlined, size: 22),
                SizedBox(width: 10),
                Text('Edit Profile'),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: currentPwCtrl,
                    obscureText: obscureCurrent,
                    decoration: InputDecoration(
                      labelText: 'Current password (required)',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(
                          () => obscureCurrent = !obscureCurrent,
                        ),
                        icon: Icon(
                          obscureCurrent
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 24),
                  Text(
                    'New password (leave blank to keep current)',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: newPwCtrl,
                    obscureText: obscureNew,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setDialogState(() => obscureNew = !obscureNew),
                        icon: Icon(
                          obscureNew
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmPwCtrl,
                    obscureText: obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirm new password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(
                          () => obscureConfirm = !obscureConfirm,
                        ),
                        icon: Icon(
                          obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMsg!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final currentPw = currentPwCtrl.text;
                  final newEmail = emailCtrl.text.trim();
                  final newPw = newPwCtrl.text;
                  final confirmPw = confirmPwCtrl.text;

                  if (currentPw.isEmpty) {
                    setDialogState(
                      () => errorMsg = 'Current password is required.',
                    );
                    return;
                  }
                  if (newPw.isNotEmpty) {
                    if (newPw.length < 6) {
                      setDialogState(
                        () => errorMsg =
                            'New password must be at least 6 characters.',
                      );
                      return;
                    }
                    if (newPw != confirmPw) {
                      setDialogState(
                        () => errorMsg = 'New passwords do not match.',
                      );
                      return;
                    }
                  }

                  bool anyError = false;
                  final ctrl = ref.read(authControllerProvider);

                  if (newEmail != (authCtrl.registeredEmail ?? '')) {
                    final ok = await ctrl.updateEmail(
                      currentPassword: currentPw,
                      newEmail: newEmail,
                    );
                    if (!ok) {
                      setDialogState(
                        () => errorMsg =
                            'Failed to update email. Check current password.',
                      );
                      anyError = true;
                    }
                  }

                  if (!anyError && newPw.isNotEmpty) {
                    final ok = await ctrl.changePassword(
                      currentPassword: currentPw,
                      newPassword: newPw,
                    );
                    if (!ok) {
                      setDialogState(
                        () => errorMsg =
                            'Failed to change password. Check current password.',
                      );
                      anyError = true;
                    }
                  }

                  if (!anyError && ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile updated successfully.'),
                      ),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBackupDialog(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.backup_rounded, size: 22),
            SizedBox(width: 10),
            Text('Backup & Restore'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BackupOptionTile(
              icon: Icons.cloud_upload_outlined,
              iconColor: scheme.primary,
              title: 'Export Backup',
              subtitle:
                  'Save all business data to a timestamped JSON file '
                  'with a SHA-256 integrity checksum.',
              onTap: () {
                Navigator.pop(ctx);
                _exportBackup();
              },
            ),
            const SizedBox(height: 8),
            _BackupOptionTile(
              icon: Icons.cloud_download_outlined,
              iconColor: const Color(0xFF059669),
              title: 'Import Backup',
              subtitle:
                  'Restore from a backup file. Replaces all current '
                  'data after checksum verification.',
              onTap: () {
                Navigator.pop(ctx);
                _importBackup();
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Login credentials are never included in backups — '
                      'each device keeps its own authentication.',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatefulWidget {
  const _DashboardTab({required this.controller, required this.onNavigate});

  final PharmacyAppController controller;
  final void Function(int index) onNavigate;

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> get _searchResults {
    if (_query.trim().isEmpty) {
      return const <Product>[];
    }
    final query = _query.toLowerCase();
    final products = widget.controller.products.where((product) {
      return product.name.toLowerCase().contains(query);
    }).toList();
    products.sort((a, b) => a.name.compareTo(b.name));
    return products;
  }

  Future<void> _showQuickStockIn(Product product) async {
    final isMedicine = product.trackInPieces && product.unitsPerPack > 1;
    final packController = TextEditingController(text: '1');
    final pieceController = TextEditingController(text: '0');
    final qtyController = TextEditingController(text: '1');
    final priceController = TextEditingController(
      text: (product.buyPrice * product.unitsPerPack).toStringAsFixed(2),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: Text('Quick Stock In • ${product.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isMedicine)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Add stock by packs and extra pieces',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (isMedicine) const SizedBox(height: 12),
                  if (isMedicine) ...[
                    TextField(
                      controller: packController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Packs'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pieceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Extra Pieces',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Pieces above one pack are auto-counted.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ] else
                    TextField(
                      controller: qtyController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Units'),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: isMedicine
                          ? 'Buy price per pack'
                          : 'Buy price per unit',
                      prefixText: '৳ ',
                    ),
                  ),
                  if (isMedicine)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '1 pack = ${product.unitsPerPack} pieces',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) {
      return;
    }

    final qtyInput = int.tryParse(qtyController.text.trim());
    final packInput = int.tryParse(packController.text.trim()) ?? 0;
    final pieceInput = int.tryParse(pieceController.text.trim()) ?? 0;
    final priceInput = double.tryParse(priceController.text.trim());
    if (priceInput == null || priceInput <= 0) {
      return;
    }

    if (isMedicine &&
        (packInput < 0 ||
            pieceInput < 0 ||
            (packInput == 0 && pieceInput == 0))) {
      return;
    }

    if (!isMedicine && (qtyInput == null || qtyInput <= 0)) {
      return;
    }

    final quantityInPieces = isMedicine
        ? (packInput * product.unitsPerPack) + pieceInput
        : qtyInput!;
    final buyPerPiece = isMedicine
        ? priceInput / (product.unitsPerPack <= 0 ? 1 : product.unitsPerPack)
        : priceInput;

    await widget.controller.recordPurchase(
      productId: product.id!,
      quantity: quantityInPieces,
      unitPrice: buyPerPiece,
      note: 'Quick stock-in (pack/piece)',
    );
  }

  Future<void> _showQuickSell(Product product) async {
    final byPiece = product.trackInPieces && product.unitsPerPack > 1;
    var mode = byPiece ? 'piece' : 'pack';
    final qtyController = TextEditingController(text: '1');
    final priceController = TextEditingController(
      text: byPiece
          ? product.sellPrice.toStringAsFixed(2)
          : (product.sellPrice * product.unitsPerPack).toStringAsFixed(2),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: Text('Quick Sell • ${product.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (byPiece)
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'piece', label: Text('Piece')),
                        ButtonSegment(value: 'pack', label: Text('Pack')),
                      ],
                      selected: {mode},
                      onSelectionChanged: (selection) {
                        setStateDialog(() {
                          mode = selection.first;
                          priceController.text = mode == 'piece'
                              ? product.sellPrice.toStringAsFixed(2)
                              : (product.sellPrice * product.unitsPerPack)
                                    .toStringAsFixed(2);
                        });
                      },
                    ),
                  if (byPiece) const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: mode == 'piece' ? 'Pieces' : 'Packs',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: mode == 'piece'
                          ? 'Sell price per piece'
                          : 'Sell price per pack',
                      prefixText: '৳ ',
                    ),
                  ),
                  if (byPiece)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '1 pack = ${product.unitsPerPack} pieces',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) {
      return;
    }

    final qtyInput = int.tryParse(qtyController.text.trim());
    final priceInput = double.tryParse(priceController.text.trim());
    if (qtyInput == null ||
        qtyInput <= 0 ||
        priceInput == null ||
        priceInput <= 0) {
      return;
    }

    final quantityInPieces = mode == 'piece'
        ? qtyInput
        : qtyInput * (product.unitsPerPack <= 0 ? 1 : product.unitsPerPack);
    final sellPerPiece = mode == 'piece'
        ? priceInput
        : priceInput / (product.unitsPerPack <= 0 ? 1 : product.unitsPerPack);

    await widget.controller.recordSale(
      productId: product.id!,
      quantity: quantityInPieces,
      unitPrice: sellPerPiece,
      note: mode == 'piece' ? 'Quick sell (piece)' : 'Quick sell (pack)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final report = controller.dashboardReport;
    final scheme = Theme.of(context).colorScheme;
    final lowStockProducts =
        controller.products
            .where((product) => product.stockQty <= _lowStockThreshold)
            .toList()
          ..sort((left, right) => left.stockQty.compareTo(right.stockQty));

    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
        ? 'Good Afternoon'
        : 'Good Evening';
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(DateTime.now());

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── Hero header ──
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1D4ED8), Color(0xFF2563EB), Color(0xFF38BDF8)],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // decorative cross emblem
              Positioned(
                right: -8,
                top: -12,
                child: Opacity(
                  opacity: 0.08,
                  child: Text(
                    '+',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 110,
                      height: 1,
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Jarin Pharmacy',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                      letterSpacing: -0.6,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: Colors.white54,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.74),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Search ──
              TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText:
                      'Search product • Enter to sell • Ctrl+Enter to stock in',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () => setState(() {
                            _query = '';
                            _searchController.clear();
                          }),
                          icon: const Icon(Icons.clear, size: 18),
                        ),
                ),
              ),
              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Search results — Enter=Sell, Ctrl+Enter=Stock In',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ..._searchResults
                    .take(8)
                    .map(
                      (product) => _KeyboardProductActionRow(
                        product: product,
                        onQuickSell: () => _showQuickSell(product),
                        onQuickStockIn: () => _showQuickStockIn(product),
                      ),
                    ),
                const Divider(height: 24),
              ] else
                const SizedBox(height: 20),

              // ── Stats ──
              if (report != null) ...[
                Row(
                  children: [
                    Text(
                      "Today's Performance",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: report.netProfit >= 0
                            ? scheme.primaryContainer.withValues(alpha: 0.6)
                            : scheme.errorContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            report.netProfit >= 0
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 12,
                            color: report.netProfit >= 0
                                ? scheme.primary
                                : scheme.error,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            report.netProfit >= 0 ? 'Profitable' : 'Loss',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: report.netProfit >= 0
                                  ? scheme.primary
                                  : scheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth >= 1000
                        ? 4
                        : constraints.maxWidth >= 680
                        ? 3
                        : constraints.maxWidth >= 440
                        ? 2
                        : 1;
                    return GridView.count(
                      crossAxisCount: cols,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.72,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _SummaryCard(
                          title: 'Sales',
                          value: _money(report.salesBilling),
                          icon: Icons.trending_up_rounded,
                          color: const Color(0xFF2563EB),
                        ),
                        _SummaryCard(
                          title: 'Purchases',
                          value: _money(report.purchaseBilling),
                          icon: Icons.shopping_cart_rounded,
                          color: scheme.primary,
                        ),
                        _SummaryCard(
                          title: 'Net Profit',
                          value: _money(report.netProfit),
                          icon: Icons.account_balance_rounded,
                          color: report.netProfit >= 0
                              ? const Color(0xFF2563EB)
                              : scheme.error,
                        ),
                        _SummaryCard(
                          title: 'Due Amount',
                          value: _money(report.dueAmount),
                          icon: Icons.receipt_long_rounded,
                          color: const Color(0xFF38BDF8),
                        ),
                        _SummaryCard(
                          title: 'Stock Value',
                          value: _money(report.stockValue),
                          icon: Icons.inventory_2_rounded,
                          color: scheme.tertiary,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Net P/L = Gross Profit − Due Amount − Inventory Loss + bKash Commission',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else
                const _EmptyStateCard(
                  title: 'No data yet',
                  message: 'Record purchases or sales to see today\'s summary.',
                ),

              const SizedBox(height: 22),

              // ── Quick actions ──
              Text(
                'Quick Actions',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final crossCount = totalWidth >= 600
                      ? 5
                      : totalWidth >= 380
                      ? 3
                      : 2;
                  final tileWidth =
                      (totalWidth - (crossCount - 1) * 10) / crossCount;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: tileWidth,
                        child: _QuickActionTile(
                          title: 'New Bill',
                          subtitle: 'Sell products',
                          icon: Icons.point_of_sale_rounded,
                          color: const Color(0xFF2563EB),
                          onTap: () => widget.onNavigate(1),
                        ),
                      ),
                      SizedBox(
                        width: tileWidth,
                        child: _QuickActionTile(
                          title: 'Stock In',
                          subtitle: 'Add inventory',
                          icon: Icons.add_business_rounded,
                          color: scheme.primary,
                          onTap: () => widget.onNavigate(2),
                        ),
                      ),
                      SizedBox(
                        width: tileWidth,
                        child: _QuickActionTile(
                          title: 'Reports',
                          subtitle: 'Business overview',
                          icon: Icons.query_stats_rounded,
                          color: scheme.tertiary,
                          onTap: () => widget.onNavigate(4),
                        ),
                      ),
                      SizedBox(
                        width: tileWidth,
                        child: _QuickActionTile(
                          title: 'bKash',
                          subtitle: 'Wallet entries',
                          icon: Icons.account_balance_wallet_rounded,
                          color: const Color(0xFF0EA5E9),
                          onTap: () => widget.onNavigate(3),
                        ),
                      ),
                      SizedBox(
                        width: tileWidth,
                        child: _QuickActionTile(
                          title: 'Customers',
                          subtitle: 'View profiles',
                          icon: Icons.people_rounded,
                          color: const Color(0xFF60A5FA),
                          onTap: () => widget.onNavigate(5),
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 22),

              // ── Stock alerts ──
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Stock Alerts',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${lowStockProducts.length} items',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (lowStockProducts.isEmpty)
                const _EmptyStateCard(
                  title: 'No stock alerts',
                  message: 'All products have healthy stock levels.',
                )
              else
                ...lowStockProducts
                    .take(8)
                    .map((product) => _StockAlertTile(product: product)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SellTab extends StatefulWidget {
  const _SellTab({required this.controller});

  final PharmacyAppController controller;

  @override
  State<_SellTab> createState() => _SellTabState();
}

class _SellTabState extends State<_SellTab> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final List<_SellCartItem> _cart = <_SellCartItem>[];
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<Product> get _filteredProducts {
    return widget.controller.products.where((product) {
      return product.stockQty > 0 &&
          (_query.isEmpty ||
              product.name.toLowerCase().contains(_query.toLowerCase()));
    }).toList();
  }

  double get _grandTotal {
    return _cart.fold<double>(0, (sum, item) => sum + item.total);
  }

  String _cartQuantityLabel(Product product, int quantity) {
    if (product.trackInPieces && product.unitsPerPack > 1) {
      final packs = quantity ~/ product.unitsPerPack;
      final pieces = quantity % product.unitsPerPack;
      return '$packs pack, $pieces pcs';
    }
    return '$quantity unit';
  }

  void _addProductToCart(Product product, {int quantityToAdd = 1}) {
    if (quantityToAdd <= 0) {
      return;
    }
    setState(() {
      final existingIndex = _cart.indexWhere(
        (item) => item.product.id == product.id,
      );
      if (existingIndex >= 0) {
        final existing = _cart[existingIndex];
        if (existing.quantity + quantityToAdd <= product.stockQty) {
          existing.quantity += quantityToAdd;
        }
      } else {
        if (quantityToAdd > product.stockQty) {
          return;
        }
        _cart.add(
          _SellCartItem(
            product: product,
            quantity: quantityToAdd,
            unitPrice: product.sellPrice,
          ),
        );
      }
    });
  }

  bool _changeCartQuantity(int index, int delta) {
    var removed = false;
    setState(() {
      final current = _cart[index];
      final nextQuantity = current.quantity + delta;
      if (nextQuantity <= 0) {
        _cart.removeAt(index);
        removed = true;
        return;
      }
      if (nextQuantity <= current.product.stockQty) {
        current.quantity = nextQuantity;
      }
    });
    return removed;
  }

  Future<void> _editCartPrice(int index) async {
    final item = _cart[index];
    final controller = TextEditingController(
      text: item.unitPrice.toStringAsFixed(2),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Price for ${item.product.name}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Unit Sell Price',
              prefixText: '৳ ',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Update'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final parsed = double.tryParse(controller.text.trim());
    if (parsed == null || parsed <= 0) {
      return;
    }

    setState(() {
      item.unitPrice = parsed;
    });
  }

  Future<void> _showDgdaDataDialog({
    required String title,
    required Map<String, String> data,
  }) async {
    final entries =
        data.entries
            .map(
              (entry) => MapEntry(
                _formatDgdaFieldLabel(entry.key),
                _cleanDgdaFieldValue(entry.value),
              ),
            )
            .where((entry) => entry.value.isNotEmpty)
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 760,
            height: 560,
            child: entries.isEmpty
                ? const Center(child: Text('No DGDA metadata found.'))
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          entry.key,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(entry.value),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _recordSaleCart() async {
    if (_cart.isEmpty) {
      return;
    }

    final customers = widget.controller.customers
        .where((customer) => customer.id != null)
        .toList();
    String? selectedCustomerId;
    final customerController = TextEditingController();
    final customerPhoneController = TextEditingController();
    final billNoteController = TextEditingController(
      text: _noteController.text.trim(),
    );
    final totalAmount = _grandTotal;
    final cashReceivedController = TextEditingController(
      text: totalAmount.toStringAsFixed(2),
    );
    final changeReturnedController = TextEditingController(text: '0');
    var changeEditedManually = false;

    void syncReturnedAmount() {
      if (changeEditedManually) {
        return;
      }
      final cashValue =
          double.tryParse(cashReceivedController.text.trim()) ?? 0;
      final changeValue = (cashValue - totalAmount).clamp(0, double.infinity);
      changeReturnedController.text = changeValue.toStringAsFixed(2);
    }

    cashReceivedController.addListener(syncReturnedAmount);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            void onCustomerSelected(String? value) {
              selectedCustomerId = value;
              if (value == null || value.isEmpty) {
                return;
              }

              Customer? selected;
              for (final customer in customers) {
                if (customer.id == value) {
                  selected = customer;
                  break;
                }
              }

              if (selected == null) {
                return;
              }

              customerController.text = selected.name;
              customerPhoneController.text = selected.phone ?? '';
            }

            final receivedAmount =
                double.tryParse(cashReceivedController.text.trim()) ?? 0;
            final returnedAmount =
                double.tryParse(changeReturnedController.text.trim()) ?? 0;
            final paidAmount = (receivedAmount - returnedAmount).clamp(
              0,
              double.infinity,
            );
            final dueAmount = (totalAmount - paidAmount).clamp(
              0,
              double.infinity,
            );

            return AlertDialog(
              title: const Text('Create Invoice'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          _DialogSummaryRow(
                            label: 'Total',
                            value: _money(totalAmount),
                            emphasize: true,
                          ),
                          const SizedBox(height: 6),
                          _DialogSummaryRow(
                            label: 'Received',
                            value: _money(receivedAmount),
                          ),
                          const SizedBox(height: 6),
                          _DialogSummaryRow(
                            label: 'Paid',
                            value: _money(paidAmount),
                          ),
                          const SizedBox(height: 6),
                          _DialogSummaryRow(
                            label: 'Due',
                            value: _money(dueAmount),
                          ),
                          const SizedBox(height: 6),
                          _DialogSummaryRow(
                            label: 'Change',
                            value: _money(returnedAmount),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCustomerId ?? '',
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('Walk-in / New customer'),
                      ),
                      ...customers.map(
                        (customer) => DropdownMenuItem<String>(
                          value: customer.id!,
                          child: Text(
                            customer.phone == null ||
                                    customer.phone!.trim().isEmpty
                                ? customer.name
                                : '${customer.name} • ${customer.phone}',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setStateDialog(() {
                        onCustomerSelected(value);
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Select Existing Customer',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: customerController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Customer Name (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: customerPhoneController,
                    decoration: const InputDecoration(
                      labelText: 'Customer Phone (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: billNoteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Invoice Note (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cashReceivedController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setStateDialog(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Customer Gave',
                      prefixText: '৳ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: changeReturnedController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) {
                      changeEditedManually = true;
                      setStateDialog(() {});
                    },
                    decoration: const InputDecoration(
                      labelText: 'Returned to Customer',
                      prefixText: '৳ ',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Create Bill'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final cashReceived = double.tryParse(cashReceivedController.text.trim());
    final changeReturned = double.tryParse(
      changeReturnedController.text.trim(),
    );
    if (cashReceived == null || changeReturned == null) {
      return;
    }
    if (cashReceived < 0 ||
        changeReturned < 0 ||
        changeReturned > cashReceived) {
      return;
    }

    try {
      final invoice = await widget.controller.createInvoice(
        lines: _cart
            .map(
              (item) => InvoiceLineInput(
                productId: item.product.id!,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
              ),
            )
            .toList(),
        selectedCustomerId:
            (selectedCustomerId == null || selectedCustomerId!.isEmpty)
            ? null
            : selectedCustomerId,
        customerName: customerController.text.trim().isEmpty
            ? null
            : customerController.text.trim(),
        customerPhone: customerPhoneController.text.trim().isEmpty
            ? null
            : customerPhoneController.text.trim(),
        note: billNoteController.text.trim().isEmpty
            ? null
            : billNoteController.text.trim(),
        cashReceived: cashReceived,
        changeReturned: changeReturned,
      );

      setState(() {
        _cart.clear();
        _noteController.clear();
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${invoice.invoice.invoiceNumber} created successfully.',
          ),
        ),
      );

      Navigator.of(
        context,
      ).pushNamed(AppRoutes.invoiceShow, arguments: invoice.invoice.id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to record bill: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = _filteredProducts;

    Widget buildProductPane() {
      return filteredProducts.isEmpty
          ? const _EmptyStateCard(
              title: 'No products in stock',
              message: 'Add products in the Stock tab to start billing.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              itemCount: filteredProducts.length,
              itemBuilder: (context, index) {
                final product = filteredProducts[index];
                final hasDgdaData = product.hasDgdaData;
                final supportsPiecePack =
                    product.trackInPieces && product.unitsPerPack > 1;
                final inCart = _cart.where(
                  (item) => item.product.id == product.id,
                );
                final quantityInCart = inCart.isEmpty
                    ? 0
                    : inCart.first.quantity;
                final scheme = Theme.of(context).colorScheme;
                final inCartAccent = quantityInCart > 0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        _addProductToCart(product, quantityToAdd: 1);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () =>
                            _addProductToCart(product, quantityToAdd: 1),
                        child: Container(
                          decoration: BoxDecoration(
                            color: inCartAccent
                                ? scheme.primaryContainer.withValues(
                                    alpha: 0.18,
                                  )
                                : scheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: inCartAccent
                                  ? scheme.primary.withValues(alpha: 0.35)
                                  : scheme.outlineVariant.withValues(
                                      alpha: 0.5,
                                    ),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            product.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: inCartAccent
                                                      ? scheme.primary
                                                      : null,
                                                ),
                                          ),
                                        ),
                                        if (hasDgdaData)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              left: 6,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: scheme.primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              'DGDA',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: scheme
                                                        .onPrimaryContainer,
                                                  ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${_categoryLabel(product.category)} · ${_money(product.sellPrice)} · Stock ${_stockDisplay(product)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              supportsPiecePack
                                  ? Wrap(
                                      spacing: 6,
                                      children: [
                                        OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                          ),
                                          onPressed: () => _addProductToCart(
                                            product,
                                            quantityToAdd: product.unitsPerPack,
                                          ),
                                          child: const Text('Pack'),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                          ),
                                          onPressed: () => _addProductToCart(
                                            product,
                                            quantityToAdd: 1,
                                          ),
                                          child: Text(
                                            quantityInCart == 0
                                                ? 'Piece'
                                                : _cartQuantityLabel(
                                                    product,
                                                    quantityInCart,
                                                  ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        backgroundColor: inCartAccent
                                            ? scheme.primary
                                            : null,
                                      ),
                                      onPressed: () => _addProductToCart(
                                        product,
                                        quantityToAdd: 1,
                                      ),
                                      icon: Icon(
                                        quantityInCart == 0
                                            ? Icons.add
                                            : Icons.shopping_cart_rounded,
                                        size: 16,
                                      ),
                                      label: Text(
                                        quantityInCart == 0
                                            ? 'Add'
                                            : 'x$quantityInCart',
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
    }

    Widget buildCartPane() {
      final scheme = Theme.of(context).colorScheme;
      return Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border(left: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          children: [
            // ── Cart header ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.receipt_long,
                      size: 16,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Bill',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${_cart.length} item${_cart.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _cart.isEmpty
                  ? const _EmptyStateCard(
                      title: 'Cart is empty',
                      message: 'Tap a product to add it to the bill.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      itemCount: _cart.length,
                      itemBuilder: (context, index) {
                        final item = _cart[index];
                        final supportsPiecePack =
                            item.product.trackInPieces &&
                            item.product.unitsPerPack > 1;
                        final hasDgdaData = item.product.hasDgdaData;
                        final dgdaSummary = <String>[
                          if ((item.product.dgdaGenericName ?? '')
                              .trim()
                              .isNotEmpty)
                            item.product.dgdaGenericName!,
                          if ((item.product.dgdaStrength ?? '')
                              .trim()
                              .isNotEmpty)
                            item.product.dgdaStrength!,
                        ];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.product.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      _money(item.total),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: scheme.primary,
                                          ),
                                    ),
                                  ],
                                ),
                                if (dgdaSummary.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    dgdaSummary.join(' · '),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _QuantityStepper(
                                      quantity: item.quantity,
                                      onDecrease: () =>
                                          _changeCartQuantity(index, -1),
                                      onIncrease: () =>
                                          _changeCartQuantity(index, 1),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '× ${_money(item.unitPrice)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const Spacer(),
                                    if (supportsPiecePack)
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          _changeCartQuantity(
                                            index,
                                            -item.product.unitsPerPack,
                                          );
                                        },
                                        tooltip: 'Pack -',
                                        icon: const Icon(
                                          Icons
                                              .indeterminate_check_box_outlined,
                                          size: 18,
                                        ),
                                      ),
                                    if (supportsPiecePack)
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed:
                                            item.quantity +
                                                    item.product.unitsPerPack <=
                                                item.product.stockQty
                                            ? () => _changeCartQuantity(
                                                index,
                                                item.product.unitsPerPack,
                                              )
                                            : null,
                                        tooltip: 'Pack +',
                                        icon: const Icon(
                                          Icons.add_box_outlined,
                                          size: 18,
                                        ),
                                      ),
                                    if (hasDgdaData)
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _showDgdaDataDialog(
                                          title: item.product.name,
                                          data: item.product.dgdaData,
                                        ),
                                        tooltip: 'DGDA details',
                                        icon: const Icon(
                                          Icons.info_outline,
                                          size: 18,
                                        ),
                                      ),
                                    PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'price') {
                                          _editCartPrice(index);
                                        }
                                        if (value == 'remove') {
                                          setState(() {
                                            _cart.removeAt(index);
                                          });
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'price',
                                          child: Text('Edit Price'),
                                        ),
                                        PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Remove'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // ── Bill footer ──
            Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: 'Bill Note (optional)',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Total',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _money(_grandTotal),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.primary,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _cart.isEmpty
                              ? null
                              : () {
                                  setState(() {
                                    _cart.clear();
                                    _noteController.clear();
                                  });
                                },
                          child: const Text('Clear'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _cart.isEmpty ? null : _recordSaleCart,
                          icon: const Icon(Icons.receipt_long, size: 18),
                          label: const Text('Record Bill'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search medicine or stationery for billing',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              setState(() {
                                _query = '';
                                _searchController.clear();
                              });
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _query = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.invoices),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Invoices'),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1100;

              if (isWide) {
                return Row(
                  children: [
                    Expanded(flex: 5, child: buildProductPane()),
                    Expanded(flex: 4, child: buildCartPane()),
                  ],
                );
              }

              return Column(
                children: [
                  Expanded(flex: 5, child: buildProductPane()),
                  Divider(
                    height: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  Expanded(flex: 6, child: buildCartPane()),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _InventoryTab extends StatefulWidget {
  const _InventoryTab({required this.controller});

  final PharmacyAppController controller;

  @override
  State<_InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<_InventoryTab> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  List<Purchase> _stockInRecords = const [];
  List<InventoryAdjustment> _adjustmentRecords = const [];
  bool _isLoadingStockInRecords = false;
  ReportPeriod _stockInFilter = ReportPeriod.day;
  DateTime _stockInAnchorDate = DateTime.now();
  String _recordsView = 'stock_in';

  @override
  void initState() {
    super.initState();
    _loadStockInRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  (DateTime, DateTime) _stockInWindow() {
    final anchor = _stockInAnchorDate;
    if (_stockInFilter == ReportPeriod.day) {
      final start = DateTime(anchor.year, anchor.month, anchor.day);
      final end = start.add(const Duration(days: 1));
      return (start, end);
    }
    if (_stockInFilter == ReportPeriod.month) {
      final start = DateTime(anchor.year, anchor.month);
      final end = DateTime(anchor.year, anchor.month + 1);
      return (start, end);
    }
    final start = DateTime(anchor.year, anchor.month, anchor.day);
    final end = start.add(const Duration(days: 1));
    return (start, end);
  }

  String get _stockInFilterLabel {
    return switch (_stockInFilter) {
      ReportPeriod.day => DateFormat('dd MMM yyyy').format(_stockInAnchorDate),
      ReportPeriod.month => DateFormat('MMMM yyyy').format(_stockInAnchorDate),
      ReportPeriod.year => DateFormat('dd MMM yyyy').format(_stockInAnchorDate),
    };
  }

  Future<void> _pickStockInDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _stockInAnchorDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) {
      return;
    }

    setState(() {
      _stockInAnchorDate = pickedDate;
    });
    await _loadStockInRecords();
  }

  Future<void> _loadStockInRecords() async {
    setState(() {
      _isLoadingStockInRecords = true;
    });

    try {
      final (start, end) = _stockInWindow();
      final records = await widget.controller.getPurchasesInRange(start, end);
      final adjustments = await widget.controller
          .getInventoryAdjustmentsInRange(start, end);
      if (!mounted) {
        return;
      }
      setState(() {
        _stockInRecords = records;
        _adjustmentRecords = adjustments;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stockInRecords = const [];
        _adjustmentRecords = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingStockInRecords = false;
        });
      }
    }
  }

  List<Product> get _filteredProducts {
    final normalizedQuery = _query.trim().toLowerCase();

    return widget.controller.products.where((product) {
      if (normalizedQuery.isEmpty) {
        return true;
      }

      if (product.name.toLowerCase().contains(normalizedQuery) ||
          (product.dgdaGenericName ?? '').toLowerCase().contains(
            normalizedQuery,
          ) ||
          (product.dgdaManufacturer ?? '').toLowerCase().contains(
            normalizedQuery,
          ) ||
          (product.dgdaStrength ?? '').toLowerCase().contains(
            normalizedQuery,
          ) ||
          (product.dgdaDosageForm ?? '').toLowerCase().contains(
            normalizedQuery,
          )) {
        return true;
      }

      for (final value in product.dgdaData.values) {
        if (value.toLowerCase().contains(normalizedQuery)) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  Future<void> _showDgdaDataDialog({
    required String title,
    required Map<String, String> data,
  }) async {
    final entries =
        data.entries
            .map(
              (entry) => MapEntry(
                _formatDgdaFieldLabel(entry.key),
                _cleanDgdaFieldValue(entry.value),
              ),
            )
            .where((entry) => entry.value.isNotEmpty)
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 760,
            height: 560,
            child: entries.isEmpty
                ? const Center(child: Text('No DGDA metadata available.'))
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          entry.key,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(entry.value),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<DgdaMedicine?> _showDgdaMedicinePicker() async {
    final searchController = TextEditingController();
    var query = '';

    return showDialog<DgdaMedicine>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final medicines = widget.controller.searchDgdaMedicines(
              query,
              limit: 80,
            );

            return AlertDialog(
              title: const Text('Select DGDA Medicine'),
              content: SizedBox(
                width: 720,
                height: 520,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search by brand, generic, strength, DAR',
                      ),
                      onChanged: (value) {
                        setStateDialog(() {
                          query = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: query.trim().isEmpty
                          ? const Center(
                              child: Text('Type to search DGDA dataset.'),
                            )
                          : medicines.isEmpty
                          ? const Center(
                              child: Text('No DGDA medicine matched.'),
                            )
                          : ListView.separated(
                              itemCount: medicines.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final medicine = medicines[index];
                                final subtitleParts = <String>[
                                  if (medicine.type.isNotEmpty) medicine.type,
                                  if (medicine.genericName.isNotEmpty)
                                    medicine.genericName,
                                  if (medicine.manufacturer.isNotEmpty)
                                    medicine.manufacturer,
                                  if (medicine.packageContainer.isNotEmpty)
                                    medicine.packageContainer,
                                  if (medicine.darNumber.isNotEmpty)
                                    'DAR ${medicine.darNumber}',
                                ];

                                return ListTile(
                                  dense: true,
                                  title: Text(medicine.displayName),
                                  subtitle: subtitleParts.isEmpty
                                      ? null
                                      : Text(subtitleParts.join(' • ')),
                                  onTap: () =>
                                      Navigator.pop(dialogContext, medicine),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showStockInDialog(Product product) async {
    final isMedicine = product.trackInPieces && product.unitsPerPack > 1;
    final quantityController = TextEditingController(text: '1');
    final packController = TextEditingController(text: '1');
    final pieceController = TextEditingController(text: '0');
    final priceController = TextEditingController(
      text: (product.buyPrice * product.unitsPerPack).toStringAsFixed(2),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: Text('Stock In: ${product.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isMedicine)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Add stock by packs and extra pieces',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (isMedicine) const SizedBox(height: 12),
                  if (isMedicine) ...[
                    TextField(
                      controller: packController,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Packs'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pieceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Extra Pieces',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Pieces above one pack are auto-counted.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ] else
                    TextField(
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Units'),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: isMedicine
                          ? 'Buy price per pack'
                          : 'Buy price per unit',
                      prefixText: '৳ ',
                    ),
                  ),
                  if (isMedicine)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '1 pack = ${product.unitsPerPack} pieces',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final quantityInput = int.tryParse(quantityController.text.trim());
    final packInput = int.tryParse(packController.text.trim()) ?? 0;
    final pieceInput = int.tryParse(pieceController.text.trim()) ?? 0;
    final priceInput = double.tryParse(priceController.text.trim());
    if (priceInput == null || priceInput <= 0) {
      return;
    }

    if (isMedicine &&
        (packInput < 0 ||
            pieceInput < 0 ||
            (packInput == 0 && pieceInput == 0))) {
      return;
    }

    if (!isMedicine && (quantityInput == null || quantityInput <= 0)) {
      return;
    }

    final quantityInPieces = isMedicine
        ? (packInput * product.unitsPerPack) + pieceInput
        : quantityInput!;
    final buyPerPiece = isMedicine
        ? priceInput / (product.unitsPerPack <= 0 ? 1 : product.unitsPerPack)
        : priceInput;

    try {
      await widget.controller.recordPurchase(
        productId: product.id!,
        quantity: quantityInPieces,
        unitPrice: buyPerPiece,
      );
      await _loadStockInRecords();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to stock in: $error')));
    }
  }

  Future<void> _showProductDialog({Product? product}) async {
    final nameController = TextEditingController(text: product?.name ?? '');
    final initialUnitsPerPack = product?.unitsPerPack ?? 1;
    final initialStockQty = product?.stockQty ?? 0;
    final buyController = TextEditingController(
      text: product == null
          ? ''
          : (product.buyPrice * product.unitsPerPack).toStringAsFixed(2),
    );
    final sellController = TextEditingController(
      text: product == null
          ? ''
          : (product.sellPrice * product.unitsPerPack).toStringAsFixed(2),
    );
    final stockController = TextEditingController(
      text: product == null ? '0' : product.stockQty.toString(),
    );
    final stockPackController = TextEditingController(
      text: product == null
          ? '0'
          : (initialStockQty ~/
                    (initialUnitsPerPack <= 0 ? 1 : initialUnitsPerPack))
                .toString(),
    );
    final stockPieceController = TextEditingController(
      text: product == null
          ? '0'
          : (initialStockQty %
                    (initialUnitsPerPack <= 0 ? 1 : initialUnitsPerPack))
                .toString(),
    );
    final unitsPerPackController = TextEditingController(
      text: product == null ? '1' : product.unitsPerPack.toString(),
    );
    var selectedCategory = product?.category ?? ProductCategory.medicine;
    DgdaMedicine? selectedDgdaMedicine = product == null
        ? null
        : DgdaMedicine(
            brandId: product.dgdaBrandId ?? '',
            brandName: product.name,
            type: product.dgdaType ?? '',
            slug: product.dgdaSlug ?? '',
            genericName: product.dgdaGenericName ?? '',
            strength: product.dgdaStrength ?? '',
            dosageForm: product.dgdaDosageForm ?? '',
            manufacturer: product.dgdaManufacturer ?? '',
            darNumber: product.dgdaData['medicine_dar_number'] ?? '',
            packageContainer: product.dgdaPackageContainer ?? '',
            packageSize: product.dgdaPackageSize ?? '',
            drugClass: product.dgdaData['generic_drug_class'] ?? '',
            indication: product.dgdaData['generic_indication'] ?? '',
            monographLink: product.dgdaData['generic_monograph_link'] ?? '',
            allData: product.dgdaData,
          );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(product == null ? 'Add Product' : 'Edit Product'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    if (selectedCategory == ProductCategory.medicine) ...[
                      const SizedBox(height: 8),
                      if (widget.controller.hasDgdaDataset)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await _showDgdaMedicinePicker();
                              if (picked == null) {
                                return;
                              }

                              final parsedPrice = _extractDgdaPrice(picked);
                              final parsedUnitsPerPack =
                                  _extractDgdaUnitsPerPack(picked);

                              setStateDialog(() {
                                selectedDgdaMedicine = picked;
                                nameController.text = picked.displayName;
                                if (parsedPrice != null) {
                                  buyController.text = parsedPrice
                                      .toStringAsFixed(2);
                                  sellController.text = parsedPrice
                                      .toStringAsFixed(2);
                                }
                                if (parsedUnitsPerPack != null) {
                                  unitsPerPackController.text =
                                      parsedUnitsPerPack.toString();
                                }
                              });
                            },
                            icon: const Icon(Icons.medication_outlined),
                            label: Text(
                              selectedDgdaMedicine == null
                                  ? 'Pick from DGDA dataset'
                                  : 'Change DGDA medicine',
                            ),
                          ),
                        )
                      else
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'DGDA dataset not loaded. Add CSV to assets/data/dgda_medicines.csv',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (selectedDgdaMedicine != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            [
                              if (selectedDgdaMedicine!.genericName.isNotEmpty)
                                selectedDgdaMedicine!.genericName,
                              if (selectedDgdaMedicine!.manufacturer.isNotEmpty)
                                selectedDgdaMedicine!.manufacturer,
                              if (selectedDgdaMedicine!.drugClass.isNotEmpty)
                                selectedDgdaMedicine!.drugClass,
                              if (selectedDgdaMedicine!.darNumber.isNotEmpty)
                                'DAR ${selectedDgdaMedicine!.darNumber}',
                            ].join(' • '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _showDgdaDataDialog(
                                title: selectedDgdaMedicine!.displayName,
                                data: selectedDgdaMedicine!.allData,
                              ),
                              icon: const Icon(Icons.info_outline),
                              label: const Text('View full DGDA details'),
                            ),
                            TextButton(
                              onPressed: () {
                                setStateDialog(() {
                                  selectedDgdaMedicine = null;
                                });
                              },
                              child: const Text('Clear DGDA link'),
                            ),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ProductCategory>(
                      initialValue: selectedCategory,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: ProductCategory.values
                          .map(
                            (category) => DropdownMenuItem<ProductCategory>(
                              value: category,
                              child: Text(_categoryLabel(category)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setStateDialog(() {
                          selectedCategory = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: buyController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            (selectedCategory == ProductCategory.medicine ||
                                selectedCategory == ProductCategory.stationery)
                            ? 'Buy Price per Pack'
                            : 'Buy Price per Unit',
                        prefixText: '৳ ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sellController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            (selectedCategory == ProductCategory.medicine ||
                                selectedCategory == ProductCategory.stationery)
                            ? 'Sell Price per Pack'
                            : 'Sell Price per Unit',
                        prefixText: '৳ ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller:
                          (selectedCategory == ProductCategory.medicine ||
                              selectedCategory == ProductCategory.stationery)
                          ? stockPackController
                          : stockController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            (selectedCategory == ProductCategory.medicine ||
                                selectedCategory == ProductCategory.stationery)
                            ? 'Current Stock (packs)'
                            : 'Current Stock (units)',
                      ),
                    ),
                    if (selectedCategory == ProductCategory.medicine ||
                        selectedCategory == ProductCategory.stationery) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: stockPieceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Extra Pieces',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Pieces above one pack are auto-counted.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: unitsPerPackController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Pieces per Pack',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Products in this category are sold by piece by default.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(product == null ? 'Save' : 'Update'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final buyPrice = double.tryParse(buyController.text.trim());
    final sellPrice = double.tryParse(sellController.text.trim());
    final stockQtyUnits = int.tryParse(stockController.text.trim());
    final stockPacks = int.tryParse(stockPackController.text.trim()) ?? 0;
    final stockPieces = int.tryParse(stockPieceController.text.trim()) ?? 0;
    final unitsPerPack = int.tryParse(unitsPerPackController.text.trim()) ?? 1;
    if (nameController.text.trim().isEmpty ||
        buyPrice == null ||
        sellPrice == null ||
        unitsPerPack <= 0) {
      return;
    }

    final usePackPieceInput =
        selectedCategory == ProductCategory.medicine ||
        selectedCategory == ProductCategory.stationery;
    final safeUnitsPerPack = usePackPieceInput ? unitsPerPack : 1;
    final buyPricePerUnit = usePackPieceInput
        ? buyPrice / safeUnitsPerPack
        : buyPrice;
    final sellPricePerUnit = usePackPieceInput
        ? sellPrice / safeUnitsPerPack
        : sellPrice;
    if ((usePackPieceInput && (stockPacks < 0 || stockPieces < 0)) ||
        (!usePackPieceInput && (stockQtyUnits == null || stockQtyUnits < 0))) {
      return;
    }

    final stockQty = usePackPieceInput
        ? (stockPacks * safeUnitsPerPack) + stockPieces
        : stockQtyUnits!;

    if (stockQty < 0) {
      return;
    }

    try {
      final selectedDgdaData = selectedDgdaMedicine?.allData ?? const {};
      final isMedicine = selectedCategory == ProductCategory.medicine;
      final payloadMeta = isMedicine
          ? selectedDgdaData
          : const <String, String>{};

      if (product == null) {
        await widget.controller.addProduct(
          name: nameController.text.trim(),
          category: selectedCategory,
          buyPrice: buyPricePerUnit,
          sellPrice: sellPricePerUnit,
          openingStock: stockQty,
          unitsPerPack: safeUnitsPerPack,
          trackInPieces: usePackPieceInput,
          dgdaBrandId: isMedicine ? selectedDgdaMedicine?.brandId : null,
          dgdaType: isMedicine ? selectedDgdaMedicine?.type : null,
          dgdaSlug: isMedicine ? selectedDgdaMedicine?.slug : null,
          dgdaGenericName: isMedicine
              ? selectedDgdaMedicine?.genericName
              : null,
          dgdaStrength: isMedicine ? selectedDgdaMedicine?.strength : null,
          dgdaDosageForm: isMedicine ? selectedDgdaMedicine?.dosageForm : null,
          dgdaManufacturer: isMedicine
              ? selectedDgdaMedicine?.manufacturer
              : null,
          dgdaPackageContainer: isMedicine
              ? selectedDgdaMedicine?.packageContainer
              : null,
          dgdaPackageSize: isMedicine
              ? selectedDgdaMedicine?.packageSize
              : null,
          dgdaData: payloadMeta,
        );
      } else {
        await widget.controller.updateProduct(
          productId: product.id!,
          name: nameController.text.trim(),
          category: selectedCategory,
          buyPrice: buyPricePerUnit,
          sellPrice: sellPricePerUnit,
          stockQty: stockQty,
          unitsPerPack: safeUnitsPerPack,
          trackInPieces: usePackPieceInput,
          dgdaBrandId: isMedicine ? selectedDgdaMedicine?.brandId : null,
          dgdaType: isMedicine ? selectedDgdaMedicine?.type : null,
          dgdaSlug: isMedicine ? selectedDgdaMedicine?.slug : null,
          dgdaGenericName: isMedicine
              ? selectedDgdaMedicine?.genericName
              : null,
          dgdaStrength: isMedicine ? selectedDgdaMedicine?.strength : null,
          dgdaDosageForm: isMedicine ? selectedDgdaMedicine?.dosageForm : null,
          dgdaManufacturer: isMedicine
              ? selectedDgdaMedicine?.manufacturer
              : null,
          dgdaPackageContainer: isMedicine
              ? selectedDgdaMedicine?.packageContainer
              : null,
          dgdaPackageSize: isMedicine
              ? selectedDgdaMedicine?.packageSize
              : null,
          dgdaData: payloadMeta,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save product: $error')));
    }
  }

  Future<void> _showAdjustmentDialog(Product product) async {
    final quantityController = TextEditingController();
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Adjust Stock: ${product.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current stock: ${product.stockQty}'),
              if (product.trackInPieces && product.unitsPerPack > 1)
                Text('(${_stockDisplay(product)})'),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Quantity Change',
                  hintText: '+5 or -2',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final deltaQty = int.tryParse(quantityController.text.trim());
    if (deltaQty == null) {
      return;
    }

    try {
      await widget.controller.recordInventoryAdjustment(
        productId: product.id!,
        deltaQty: deltaQty,
        reason: reasonController.text.trim().isEmpty
            ? 'Manual adjustment'
            : reasonController.text.trim(),
      );
      await _loadStockInRecords();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to adjust stock: $error')));
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Product'),
          content: Text('Delete ${product.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.controller.deleteProduct(product.id!);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete product: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = _filteredProducts;
    final productsById = <String, Product>{
      for (final product in widget.controller.products) product.id!: product,
    };
    final stockInRecords = _stockInRecords;
    final adjustmentRecords = _adjustmentRecords;

    Widget productsPane() {
      return filteredProducts.isEmpty
          ? const _EmptyStateCard(
              title: 'No products found',
              message: 'Add your first product with the button above.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              itemCount: filteredProducts.length,
              itemBuilder: (context, index) {
                final product = filteredProducts[index];
                final hasDgdaData =
                    product.category == ProductCategory.medicine &&
                    product.hasDgdaData;
                final hasPackPiece =
                    product.trackInPieces && product.unitsPerPack > 1;
                final stockColor = product.stockQty == 0
                    ? Theme.of(context).colorScheme.error
                    : product.stockQty <= _criticalStockThreshold
                    ? const Color(0xFF1D4ED8)
                    : product.stockQty <= _lowStockThreshold
                    ? const Color(0xFF38BDF8)
                    : const Color(0xFF16A34A);
                final scheme = Theme.of(context).colorScheme;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        _showStockInDialog(product);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Stock badge ──
                          hasPackPiece
                              ? _MedicineCountBadge(
                                  stockQty: product.stockQty,
                                  unitsPerPack: product.unitsPerPack,
                                  tone: stockColor,
                                )
                              : Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: stockColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _stockShortDisplay(product),
                                      style: TextStyle(
                                        color: stockColor,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                          const SizedBox(width: 10),
                          // ── Product info + actions (all inside Expanded) ──
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Name row with DGDA pill
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        product.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (hasDgdaData) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: scheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          'DGDA',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    scheme.onPrimaryContainer,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // Category · Buy · Sell chips
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 2,
                                  children: [
                                    Text(
                                      _categoryLabel(product.category),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                    Text(
                                      'Buy ${_money(product.buyPrice)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                    Text(
                                      'Sell ${_money(product.sellPrice)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                                if ((product.dgdaGenericName ?? '').isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '${product.dgdaGenericName}${(product.dgdaManufacturer ?? '').isNotEmpty ? ' · ${product.dgdaManufacturer}' : ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                // ── Actions row ──
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (hasDgdaData)
                                      IconButton(
                                        tooltip: 'DGDA details',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _showDgdaDataDialog(
                                          title: product.name,
                                          data: product.dgdaData,
                                        ),
                                        icon: const Icon(
                                          Icons.info_outline,
                                          size: 18,
                                        ),
                                      ),
                                    FilledButton.tonal(
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        minimumSize: const Size(0, 32),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () =>
                                          _showStockInDialog(product),
                                      child: const Text('Stock In'),
                                    ),
                                    PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') {
                                          _showProductDialog(product: product);
                                        }
                                        if (value == 'adjust') {
                                          _showAdjustmentDialog(product);
                                        }
                                        if (value == 'delete') {
                                          _deleteProduct(product);
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit'),
                                        ),
                                        PopupMenuItem(
                                          value: 'adjust',
                                          child: Text('Adjust Stock'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
    }

    Widget recordsPane() {
      final scheme = Theme.of(context).colorScheme;

      Widget stockInCard(int index) {
        final purchase = stockInRecords[index];
        final product = productsById[purchase.productId];
        final title = product?.name ?? purchase.productId;
        final hasPackPiece =
            product != null &&
            product.trackInPieces &&
            product.unitsPerPack > 1;
        final quantityLabel = product == null
            ? '${purchase.quantity} units'
            : _quantityDisplay(product, purchase.quantity);
        const stripColor = Color(0xFF16A34A);

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: stripColor),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            if (hasPackPiece) ...[
                              _MedicineCountBadge(
                                stockQty: purchase.quantity,
                                unitsPerPack: product.unitsPerPack,
                                tone: stripColor,
                                compact: true,
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 3),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      Text(
                                        _dateTimeLabel(purchase.createdAt),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                      Text(
                                        'Qty $quantityLabel',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: stripColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      Text(
                                        'Unit ${_money(purchase.unitPrice)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _money(purchase.total),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: stripColor,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      Widget adjustmentCard(int index) {
        final adjustment = adjustmentRecords[index];
        final product = productsById[adjustment.productId];
        final title = product?.name ?? adjustment.productId;
        final deltaLabel = _deltaQuantityDisplay(product, adjustment.deltaQty);
        final isLoss = adjustment.deltaQty < 0;
        final stripColor = isLoss ? scheme.error : const Color(0xFF16A34A);

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: stripColor),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 3),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      Text(
                                        _dateTimeLabel(adjustment.createdAt),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                      Text(
                                        adjustment.reason,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                      Text(
                                        'Qty $deltaLabel',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: stripColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (adjustment.lossValue > 0)
                              Text(
                                _money(adjustment.lossValue),
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: stripColor,
                                    ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stock Records',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<ReportPeriod>(
                    segments: const [
                      ButtonSegment<ReportPeriod>(
                        value: ReportPeriod.day,
                        label: Text('Today'),
                      ),
                      ButtonSegment<ReportPeriod>(
                        value: ReportPeriod.month,
                        label: Text('Month'),
                      ),
                      ButtonSegment<ReportPeriod>(
                        value: ReportPeriod.year,
                        label: Text('Custom'),
                      ),
                    ],
                    selected: <ReportPeriod>{_stockInFilter},
                    onSelectionChanged: (selection) async {
                      setState(() {
                        _stockInFilter = selection.first;
                      });
                      await _loadStockInRecords();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickStockInDate,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(_stockInFilterLabel),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'stock_in',
                  label: Text('Stock In'),
                ),
                ButtonSegment<String>(
                  value: 'adjustments',
                  label: Text('Adjustments'),
                ),
              ],
              selected: <String>{_recordsView},
              onSelectionChanged: (selection) {
                setState(() {
                  _recordsView = selection.first;
                });
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _isLoadingStockInRecords
                  ? const Center(child: CircularProgressIndicator())
                  : _recordsView == 'stock_in'
                  ? (stockInRecords.isEmpty
                        ? const SingleChildScrollView(
                            child: _EmptyStateCard(
                              title: 'No stock-in records',
                              message: 'No records match the selected filter.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: stockInRecords.length,
                            itemBuilder: (context, index) => stockInCard(index),
                          ))
                  : (adjustmentRecords.isEmpty
                        ? const SingleChildScrollView(
                            child: _EmptyStateCard(
                              title: 'No adjustments',
                              message:
                                  'No adjustments match the selected filter.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: adjustmentRecords.length,
                            itemBuilder: (context, index) =>
                                adjustmentCard(index),
                          )),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search products',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              setState(() {
                                _query = '';
                                _searchController.clear();
                              });
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _query = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _showProductDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Add Product'),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1200;

              if (isWide) {
                return Row(
                  children: [
                    Expanded(flex: 3, child: productsPane()),
                    VerticalDivider(
                      width: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    Expanded(flex: 2, child: recordsPane()),
                  ],
                );
              }

              return Column(
                children: [
                  Expanded(flex: 3, child: productsPane()),
                  Divider(
                    height: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  Expanded(flex: 2, child: recordsPane()),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BkashTab extends StatefulWidget {
  const _BkashTab({required this.controller});

  final PharmacyAppController controller;

  @override
  State<_BkashTab> createState() => _BkashTabState();
}

class _BkashTabState extends State<_BkashTab> {
  static const List<BkashType> _transactionTypes = [
    BkashType.cashIn,
    BkashType.cashOut,
    BkashType.sendMoney,
    BkashType.billPayment,
    BkashType.transfer,
  ];

  String? _selectedAccountId;
  bool _showReports = false;
  String _reportPeriod = 'daily'; // daily, weekly, monthly, yearly
  DateTime _selectedDate = DateTime.now();

  void _ensureSelectedAccount() {
    final accounts = widget.controller.bkashAccounts;
    if (accounts.isEmpty) {
      _selectedAccountId = null;
      return;
    }

    final exists = accounts.any((account) => account.id == _selectedAccountId);
    if (!exists) {
      _selectedAccountId = accounts.first.id;
    }
  }

  Future<void> _showAddAccountDialog() async {
    final nameController = TextEditingController();
    final bkashBalanceController = TextEditingController(text: '0');
    final cashBalanceController = TextEditingController(text: '0');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add bKash Account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Account Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bkashBalanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Current bKash Balance',
                    prefixText: '৳ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cashBalanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Current Cash Balance',
                    prefixText: '৳ ',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final name = nameController.text.trim();
    final openingBkash = double.tryParse(bkashBalanceController.text.trim());
    final openingCash = double.tryParse(cashBalanceController.text.trim());

    if (name.isEmpty || openingBkash == null || openingCash == null) {
      return;
    }

    try {
      await widget.controller.addBkashAccount(
        name: name,
        openingBkashBalance: openingBkash,
        openingCashBalance: openingCash,
      );
      if (!mounted) {
        return;
      }
      final account = widget.controller.bkashAccounts.firstWhere(
        (item) => item.name == name,
        orElse: () => widget.controller.bkashAccounts.first,
      );
      setState(() {
        _selectedAccountId = account.id;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add account: $error')));
    }
  }

  Future<void> _showEditAccountDialog(BkashAccount account) async {
    final nameController = TextEditingController(text: account.name);
    final bkashBalanceController = TextEditingController(
      text: account.bkashBalance.toString(),
    );
    final cashBalanceController = TextEditingController(
      text: account.cashBalance.toString(),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit bKash Account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Account Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bkashBalanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'bKash Balance',
                    prefixText: '৳ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cashBalanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cash Balance',
                    prefixText: '৳ ',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final name = nameController.text.trim();
    final bkash = double.tryParse(bkashBalanceController.text.trim());
    final cash = double.tryParse(cashBalanceController.text.trim());

    if (name.isEmpty || bkash == null || cash == null) {
      return;
    }

    try {
      await widget.controller.updateBkashAccount(
        accountId: account.id,
        name: name,
        bkashBalance: bkash,
        cashBalance: cash,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAccountId = account.id;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update account: $error')),
      );
    }
  }

  Future<void> _showDeleteAccountDialog(BkashAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: Text(
            'Are you sure you want to delete "${account.name}"? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.controller.deleteBkashAccount(account.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAccountId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted successfully')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete account: $error')),
      );
    }
  }

  Future<void> _showBkashDialog() async {
    final accounts = widget.controller.bkashAccounts;
    if (accounts.isEmpty) {
      await _showAddAccountDialog();
      return;
    }

    var selectedAccountId = _selectedAccountId ?? accounts.first.id;
    String? selectedToAccountId = accounts.length > 1
        ? accounts.firstWhere((a) => a.id != selectedAccountId).id
        : null;
    final amountController = TextEditingController();
    final chargeController = TextEditingController(text: '0');
    final noteController = TextEditingController();
    var selectedType = BkashType.cashIn;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final isTransfer = selectedType == BkashType.transfer;
            // Accounts selectable as destination (exclude source)
            final destAccounts = accounts
                .where((a) => a.id != selectedAccountId)
                .toList();

            return AlertDialog(
              title: const Text('Record bKash Transaction'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedAccountId,
                      decoration: InputDecoration(
                        labelText: isTransfer ? 'From Account' : 'Account',
                      ),
                      items: accounts
                          .map(
                            (account) => DropdownMenuItem<String>(
                              value: account.id,
                              child: Text(account.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() {
                          selectedAccountId = value;
                          // Reset toAccount if it's now the same as source
                          final destList = accounts
                              .where((a) => a.id != value)
                              .toList();
                          if (selectedToAccountId == value ||
                              selectedToAccountId == null) {
                            selectedToAccountId = destList.isNotEmpty
                                ? destList.first.id
                                : null;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<BkashType>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: _transactionTypes
                          .map(
                            (type) => DropdownMenuItem<BkashType>(
                              value: type,
                              child: Text(_bkashTypeLabel(type)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() {
                          selectedType = value;
                        });
                      },
                    ),
                    // Show "To Account" only when type is transfer
                    if (isTransfer) ...[
                      const SizedBox(height: 12),
                      destAccounts.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.orange.shade200,
                                ),
                              ),
                              child: const Text(
                                'Add at least 2 accounts to use transfers.',
                                style: TextStyle(fontSize: 12),
                              ),
                            )
                          : DropdownButtonFormField<String>(
                              initialValue: selectedToAccountId,
                              decoration: const InputDecoration(
                                labelText: 'To Account',
                              ),
                              items: destAccounts
                                  .map(
                                    (account) => DropdownMenuItem<String>(
                                      value: account.id,
                                      child: Text(account.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setStateDialog(
                                  () => selectedToAccountId = value,
                                );
                              },
                            ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixText: '৳ ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: chargeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Charge',
                        prefixText: '৳ ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                      ),
                    ),
                    // Inline hint for Cash In
                    if (selectedType == BkashType.cashIn)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF16A34A,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(
                                0xFF16A34A,
                              ).withValues(alpha: 0.25),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 14,
                                color: Color(0xFF16A34A),
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Cash In adds to bKash wallet and deducts from cash on hand.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF16A34A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final amount = double.tryParse(amountController.text.trim());
    final charge = double.tryParse(chargeController.text.trim());
    if (amount == null || charge == null) return;

    // Validate transfer has a destination
    if (selectedType == BkashType.transfer && selectedToAccountId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination account.')),
      );
      return;
    }

    try {
      await widget.controller.recordBkash(
        accountId: selectedAccountId,
        type: selectedType,
        amount: amount,
        charge: charge,
        note: noteController.text.trim().isEmpty
            ? null
            : noteController.text.trim(),
        toAccountId: selectedType == BkashType.transfer
            ? selectedToAccountId
            : null,
      );
      if (!mounted) return;
      setState(() => _selectedAccountId = selectedAccountId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save bKash entry: $error')),
      );
    }
  }

  Future<void> _deleteBkash(BkashTransaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete bKash Entry'),
          content: Text('Delete ${_bkashTypeLabel(transaction.type)} entry?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.controller.deleteBkash(transaction.id!);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete bKash entry: $error')),
      );
    }
  }

  Future<void> _showDatePickerDialog(String period) async {
    final now = DateTime.now();
    DateTime? selectedDate;

    if (period == 'daily') {
      selectedDate = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: now,
      );
    } else if (period == 'monthly') {
      selectedDate = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: now,
      );
    } else if (period == 'yearly') {
      selectedDate = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: now,
      );
    } else if (period == 'weekly') {
      selectedDate = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: now,
      );
    }

    if (selectedDate == null) {
      return;
    }

    setState(() {
      _selectedDate = selectedDate!;
    });
  }

  Widget _buildReportSummaryCard(BkashReportSummary report) {
    final scheme = Theme.of(context).colorScheme;
    final totalFlow = report.totalInflow + report.totalOutflow;
    final inflowRatio = totalFlow == 0 ? 0.0 : report.totalInflow / totalFlow;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.accountName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${DateFormat('dd MMM yyyy').format(report.startDate)} - ${DateFormat('dd MMM yyyy').format(report.endDate)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(report.period),
                  avatar: Icon(
                    Icons.calendar_month_outlined,
                    size: 16,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _FinanceKpiChip(
                  label: 'Current Cash',
                  value: _money(report.closingCashBalance),
                  icon: Icons.payments_outlined,
                  tone: scheme.secondary,
                ),
                _FinanceKpiChip(
                  label: 'Current bKash',
                  value: _money(report.closingBkashBalance),
                  icon: Icons.account_balance_wallet_outlined,
                  tone: scheme.primary,
                ),
                _FinanceKpiChip(
                  label: 'Net Change',
                  value: _money(report.netChange),
                  icon: report.netChange >= 0
                      ? Icons.trending_up
                      : Icons.trending_down,
                  tone: report.netChange >= 0 ? scheme.secondary : scheme.error,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Cashflow Ratio',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: inflowRatio,
                      minHeight: 10,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        scheme.secondary,
                      ),
                      backgroundColor: scheme.error.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(inflowRatio * 100).toStringAsFixed(0)}% inflow',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Opening Balance',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('bKash: ${_money(report.openingBkashBalance)}'),
                Text('Cash: ${_money(report.openingCashBalance)}'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Transactions',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildTransactionRow(
              'Cash In',
              report.totalCashIn,
              const Color(0xFF2563EB),
            ),
            _buildTransactionRow('Cash Out', report.totalCashOut, Colors.red),
            _buildTransactionRow(
              'Send Money',
              report.totalSendMoney,
              const Color(0xFF0EA5E9),
            ),
            _buildTransactionRow(
              'Bill Payment',
              report.totalBillPayment,
              const Color(0xFF38BDF8),
            ),
            _buildTransactionRow(
              'Commission',
              report.totalCommission,
              scheme.primary,
            ),
            const Divider(height: 12),
            Text(
              'Closing Balance',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'bKash: ${_money(report.closingBkashBalance)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Cash: ${_money(report.closingCashBalance)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Net Change',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _money(report.netChange),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: report.netChange >= 0
                          ? scheme.secondary
                          : scheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionRow(String label, double amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            _money(amount),
            style: TextStyle(color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsView() {
    final accounts = widget.controller.bkashAccounts;
    if (accounts.isEmpty) {
      return const Center(child: Text('No accounts available for reports'));
    }

    return FutureBuilder<BkashReportSummary?>(
      future: _fetchReport(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const Center(child: Text('No report data available'));
        }

        final report = snapshot.data!;

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1120;

            if (!wide) {
              return ListView(
                padding: const EdgeInsets.all(8),
                children: [_buildReportSummaryCard(report)],
              );
            }

            return ListView(
              padding: const EdgeInsets.all(8),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: _buildReportSummaryCard(report)),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quick Insights',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              _DialogSummaryRow(
                                label: 'Total Inflow',
                                value: _money(report.totalInflow),
                                emphasize: true,
                              ),
                              const SizedBox(height: 8),
                              _DialogSummaryRow(
                                label: 'Total Outflow',
                                value: _money(report.totalOutflow),
                                emphasize: true,
                              ),
                              const Divider(height: 16),
                              _DialogSummaryRow(
                                label: 'Cash In Share',
                                value: report.totalInflow == 0
                                    ? '0%'
                                    : '${((report.totalCashIn / report.totalInflow) * 100).toStringAsFixed(0)}%',
                              ),
                              const SizedBox(height: 8),
                              _DialogSummaryRow(
                                label: 'Cash Out Share',
                                value: report.totalOutflow == 0
                                    ? '0%'
                                    : '${((report.totalCashOut / report.totalOutflow) * 100).toStringAsFixed(0)}%',
                              ),
                              const SizedBox(height: 8),
                              _DialogSummaryRow(
                                label: 'Send Money Share',
                                value: report.totalOutflow == 0
                                    ? '0%'
                                    : '${((report.totalSendMoney / report.totalOutflow) * 100).toStringAsFixed(0)}%',
                              ),
                              const SizedBox(height: 8),
                              _DialogSummaryRow(
                                label: 'Bill Payment Share',
                                value: report.totalOutflow == 0
                                    ? '0%'
                                    : '${((report.totalBillPayment / report.totalOutflow) * 100).toStringAsFixed(0)}%',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<BkashReportSummary?> _fetchReport() async {
    final selectedAccount = widget.controller.bkashAccounts.firstWhere(
      (account) => account.id == _selectedAccountId,
      orElse: () => widget.controller.bkashAccounts.first,
    );

    switch (_reportPeriod) {
      case 'daily':
        return widget.controller.getBkashDailyReport(
          accountId: selectedAccount.id,
          date: _selectedDate,
        );
      case 'weekly':
        return widget.controller.getBkashWeeklyReport(
          accountId: selectedAccount.id,
          date: _selectedDate,
        );
      case 'monthly':
        return widget.controller.getBkashMonthlyReport(
          accountId: selectedAccount.id,
          year: _selectedDate.year,
          month: _selectedDate.month,
        );
      case 'yearly':
        return widget.controller.getBkashYearlyReport(
          accountId: selectedAccount.id,
          year: _selectedDate.year,
        );
      default:
        return null;
    }
  }

  String _getDateLabel() {
    switch (_reportPeriod) {
      case 'daily':
        return DateFormat('dd MMM yyyy').format(_selectedDate);
      case 'weekly':
        final startOfWeek = _selectedDate.subtract(
          Duration(days: _selectedDate.weekday - 1),
        );
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        return '${DateFormat('dd MMM').format(startOfWeek)} - ${DateFormat('dd MMM yyyy').format(endOfWeek)}';
      case 'monthly':
        return DateFormat('MMMM yyyy').format(_selectedDate);
      case 'yearly':
        return _selectedDate.year.toString();
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureSelectedAccount();

    final accounts = widget.controller.bkashAccounts;
    final selectedAccount = accounts.isEmpty
        ? null
        : accounts.firstWhere(
            (account) => account.id == _selectedAccountId,
            orElse: () => accounts.first,
          );

    // ── Reports view ──
    if (_showReports) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _showReports = false),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Transactions'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showDatePickerDialog(_reportPeriod),
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_getDateLabel()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Daily'),
                  selected: _reportPeriod == 'daily',
                  onSelected: (_) => setState(() => _reportPeriod = 'daily'),
                ),
                FilterChip(
                  label: const Text('Weekly'),
                  selected: _reportPeriod == 'weekly',
                  onSelected: (_) => setState(() => _reportPeriod = 'weekly'),
                ),
                FilterChip(
                  label: const Text('Monthly'),
                  selected: _reportPeriod == 'monthly',
                  onSelected: (_) => setState(() => _reportPeriod = 'monthly'),
                ),
                FilterChip(
                  label: const Text('Yearly'),
                  selected: _reportPeriod == 'yearly',
                  onSelected: (_) => setState(() => _reportPeriod = 'yearly'),
                ),
              ],
            ),
            if (accounts.isNotEmpty) const SizedBox(height: 12),
            if (accounts.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _selectedAccountId,
                decoration: const InputDecoration(labelText: 'Account'),
                items: accounts
                    .map(
                      (account) => DropdownMenuItem<String>(
                        value: account.id,
                        child: Text(account.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedAccountId = value);
                },
              ),
            if (accounts.isNotEmpty) const SizedBox(height: 12),
            Expanded(
              child: accounts.isEmpty
                  ? const _EmptyStateCard(
                      title: 'No bKash accounts',
                      message: 'Create accounts to view reports.',
                    )
                  : _buildReportsView(),
            ),
          ],
        ),
      );
    }

    // ── Transactions view ──
    // Cash = sum of ALL accounts; bKash = per selected account
    final totalCash = accounts.fold(0.0, (sum, a) => sum + a.cashBalance);

    // Outgoing transactions for this account
    final outgoing = selectedAccount == null
        ? <BkashTransaction>[]
        : widget.controller.bkashTransactions
              .where((item) => item.accountId == selectedAccount.id)
              .toList();
    // Incoming transfers where this account is the destination
    final incomingTransfers = selectedAccount == null
        ? <BkashTransaction>[]
        : widget.controller.bkashTransactions
              .where(
                (item) =>
                    item.toAccountId == selectedAccount.id &&
                    item.type == BkashType.transfer,
              )
              .toList();
    // Merge and sort by date descending
    final transactions = [...outgoing, ...incomingTransfers]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Branded gradient header ──
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFBE185D),
                    Color(0xFFE2136E),
                    Color(0xFFF06292),
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'bKash',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const Spacer(),
                      // Action buttons – compact icons on narrow screens
                      if (constraints.maxWidth < 500) ...[
                        _BkashHeaderIconBtn(
                          icon: Icons.add_rounded,
                          tooltip: 'Record bKash',
                          onTap: _showBkashDialog,
                        ),
                        const SizedBox(width: 4),
                        _BkashHeaderIconBtn(
                          icon: Icons.account_balance_wallet_outlined,
                          tooltip: 'Add Account',
                          onTap: _showAddAccountDialog,
                        ),
                        const SizedBox(width: 4),
                        _BkashHeaderIconBtn(
                          icon: Icons.assessment_outlined,
                          tooltip: 'Reports',
                          onTap: () => setState(() => _showReports = true),
                        ),
                      ] else ...[
                        _BkashHeaderBtn(
                          icon: Icons.add_rounded,
                          label: 'Record',
                          onTap: _showBkashDialog,
                          filled: true,
                        ),
                        const SizedBox(width: 8),
                        _BkashHeaderBtn(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Add Account',
                          onTap: _showAddAccountDialog,
                        ),
                        const SizedBox(width: 8),
                        _BkashHeaderBtn(
                          icon: Icons.assessment_outlined,
                          label: 'Reports',
                          onTap: () => setState(() => _showReports = true),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Balance pills: Total Cash (all accounts) + per-account bKash
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Total Cash = sum of all accounts
                        _BkashBalancePill(
                          label: 'Total Cash',
                          amount: _money(totalCash),
                          icon: Icons.payments_rounded,
                          color: const Color(0xFF4ADE80),
                          highlight: true,
                        ),
                        ...accounts.map((account) {
                          final isSelected = account.id == _selectedAccountId;
                          return Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: GestureDetector(
                              onTap: () => setState(
                                () => _selectedAccountId = account.id,
                              ),
                              child: _BkashBalancePill(
                                label: '${account.name} bKash',
                                amount: _money(account.bkashBalance),
                                icon: Icons.account_balance_wallet_rounded,
                                color: const Color(0xFFFBCFE8),
                                highlight: isSelected,
                                selected: isSelected,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Account selector chips ──
            if (accounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: accounts.map((account) {
                            final isSelected = account.id == _selectedAccountId;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(account.name),
                                selected: isSelected,
                                onSelected: (_) => setState(
                                  () => _selectedAccountId = account.id,
                                ),
                                avatar: Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 15,
                                  color: isSelected
                                      ? const Color(0xFFE2136E)
                                      : null,
                                ),
                                selectedColor: const Color(
                                  0xFFE2136E,
                                ).withValues(alpha: 0.12),
                                checkmarkColor: const Color(0xFFE2136E),
                                side: BorderSide(
                                  color: isSelected
                                      ? const Color(
                                          0xFFE2136E,
                                        ).withValues(alpha: 0.5)
                                      : Colors.transparent,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    if (selectedAccount != null) ...[
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: 'Edit account',
                        onPressed: () =>
                            _showEditAccountDialog(selectedAccount),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: 'Delete account',
                        color: Theme.of(context).colorScheme.error,
                        onPressed: () =>
                            _showDeleteAccountDialog(selectedAccount),
                      ),
                    ],
                  ],
                ),
              ),

            // Per-account balance summary row
            if (selectedAccount != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2136E).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFE2136E).withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 15,
                        color: Color(0xFFE2136E),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          selectedAccount.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _BalanceBadge(
                        label: 'bKash',
                        amount: _money(selectedAccount.bkashBalance),
                        color: const Color(0xFFE2136E),
                      ),
                      const SizedBox(width: 10),
                      _BalanceBadge(
                        label: 'Cash',
                        amount: _money(selectedAccount.cashBalance),
                        color: const Color(0xFF16A34A),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // ── Transaction list ──
            Expanded(
              child: accounts.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: _EmptyStateCard(
                        title: 'No bKash accounts',
                        message:
                            'Create bKash accounts with current balances to start recording transactions.',
                      ),
                    )
                  : transactions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: _EmptyStateCard(
                        title: 'No bKash entries',
                        message:
                            'Record Cash In, Cash Out, Send Money, and Bill Payment for this account.',
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: transactions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final transaction = transactions[index];
                        final isIncoming =
                            transaction.toAccountId == selectedAccount?.id &&
                            transaction.type == BkashType.transfer;
                        final sourceName = isIncoming
                            ? widget.controller.bkashAccounts
                                  .where((a) => a.id == transaction.accountId)
                                  .map((a) => a.name)
                                  .firstOrNull
                            : null;
                        return _BkashTransactionTile(
                          transaction: transaction,
                          isIncomingTransfer: isIncoming,
                          sourceAccountName: sourceName,
                          onDelete: isIncoming
                              ? () {} // incoming transfers cannot be deleted from dest
                              : () => _deleteBkash(transaction),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// bKash UI helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Compact icon button shown in the bKash header on narrow screens.
class _BkashHeaderIconBtn extends StatelessWidget {
  const _BkashHeaderIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

/// Text button shown in the bKash header on wider screens.
class _BkashHeaderBtn extends StatelessWidget {
  const _BkashHeaderBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: filled
              ? Colors.white.withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill widget showing a balance amount in the bKash header.
class _BkashBalancePill extends StatelessWidget {
  const _BkashBalancePill({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    this.highlight = false,
    this.selected = false,
  });

  final String label;
  final String amount;
  final IconData icon;
  final Color color;
  final bool highlight;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.white.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? Colors.white.withValues(alpha: 0.70)
              : Colors.white.withValues(alpha: 0.25),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                ),
              ),
              Text(
                amount,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: -0.3,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small inline badge showing a labelled monetary value.
class _BalanceBadge extends StatelessWidget {
  const _BalanceBadge({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.75),
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: amount,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Styled tile for a single bKash transaction entry.
class _BkashTransactionTile extends StatelessWidget {
  const _BkashTransactionTile({
    required this.transaction,
    required this.onDelete,

    /// When true this transaction is an incoming transfer to the viewed account.
    this.isIncomingTransfer = false,
    this.sourceAccountName,
  });

  final BkashTransaction transaction;
  final VoidCallback onDelete;
  final bool isIncomingTransfer;
  final String? sourceAccountName;

  static const _colors = {
    BkashType.cashIn: Color(0xFF16A34A),
    BkashType.cashOut: Color(0xFFDC2626),
    BkashType.sendMoney: Color(0xFFEA580C),
    BkashType.billPayment: Color(0xFF7C3AED),
    BkashType.commission: Color(0xFF2563EB),
    BkashType.transfer: Color(0xFF0891B2),
  };

  static const _icons = {
    BkashType.cashIn: Icons.arrow_downward_rounded,
    BkashType.cashOut: Icons.arrow_upward_rounded,
    BkashType.sendMoney: Icons.send_rounded,
    BkashType.billPayment: Icons.receipt_long_rounded,
    BkashType.commission: Icons.stars_rounded,
    BkashType.transfer: Icons.swap_horiz_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // For incoming transfers, show as teal "Transfer In"
    final effectiveType = transaction.type;
    final color = isIncomingTransfer
        ? const Color(0xFF0E9F6E)
        : _colors[effectiveType] ?? scheme.primary;
    final iconData = isIncomingTransfer
        ? Icons.call_received_rounded
        : _icons[effectiveType] ?? Icons.monetization_on_outlined;

    final isCredit =
        isIncomingTransfer ||
        effectiveType == BkashType.cashIn ||
        effectiveType == BkashType.commission;
    final amountSign = isCredit ? '+' : '−';
    final label = isIncomingTransfer
        ? 'Transfer In'
        : _bkashTypeLabel(effectiveType);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Colored side accent + icon
            Container(
              width: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(iconData, color: color, size: 16),
                ),
              ),
            ),
            // Main content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Type chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        // Net amount
                        Text(
                          '$amountSign${_money(transaction.amount)}',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _dateTimeLabel(transaction.createdAt),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              if (isIncomingTransfer &&
                                  sourceAccountName != null)
                                Text(
                                  'From: $sourceAccountName',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: color.withValues(alpha: 0.85),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              if (transaction.note != null &&
                                  transaction.note!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    transaction.note!,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant
                                              .withValues(alpha: 0.8),
                                          fontStyle: FontStyle.italic,
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Charge badge
                        if (transaction.charge > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer.withValues(
                                alpha: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Charge ${_money(transaction.charge)}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: scheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Delete button
            IconButton(
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

enum _ReportMetric { performance, risk, wallet }

class _ReportsTab extends StatefulWidget {
  const _ReportsTab({required this.controller, required this.onPickDate});

  final PharmacyAppController controller;
  final VoidCallback onPickDate;

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  _ReportMetric _selectedMetric = _ReportMetric.performance;

  @override
  Widget build(BuildContext context) {
    final report = widget.controller.dashboardReport;
    final productNames = <String, String>{
      for (final product in widget.controller.products)
        product.id!: product.name,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        final columns = constraints.maxWidth >= 1360
            ? 4
            : constraints.maxWidth >= 1024
            ? 3
            : constraints.maxWidth >= 700
            ? 2
            : 1;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: isWide ? 520 : constraints.maxWidth - 32,
                    child: SegmentedButton<ReportPeriod>(
                      segments: const [
                        ButtonSegment<ReportPeriod>(
                          value: ReportPeriod.day,
                          label: Text('Day'),
                        ),
                        ButtonSegment<ReportPeriod>(
                          value: ReportPeriod.month,
                          label: Text('Month'),
                        ),
                        ButtonSegment<ReportPeriod>(
                          value: ReportPeriod.year,
                          label: Text('Year'),
                        ),
                      ],
                      selected: <ReportPeriod>{widget.controller.reportPeriod},
                      onSelectionChanged: (selection) {
                        widget.controller.setReportPeriod(selection.first);
                      },
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onPickDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      widget.controller.reportWindow?.label ?? 'Pick Date',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (report == null)
                const _EmptyStateCard(
                  title: 'No report data',
                  message: 'Start recording transactions to generate reports.',
                )
              else ...[
                _ReportTrendCard(
                  report: report,
                  selectedMetric: _selectedMetric,
                  onMetricChanged: (value) {
                    setState(() {
                      _selectedMetric = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  shrinkWrap: true,
                  childAspectRatio: 1.78,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _SummaryCard(
                      title: 'Sales Billing',
                      value: _money(report.salesBilling),
                      icon: Icons.receipt_long,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    _SummaryCard(
                      title: 'Purchase Billing',
                      value: _money(report.purchaseBilling),
                      icon: Icons.shopping_cart_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    _SummaryCard(
                      title: 'Gross Profit',
                      value: _money(report.grossProfit),
                      icon: Icons.ssid_chart,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    _SummaryCard(
                      title: 'Due Amount',
                      value: _money(report.dueAmount),
                      icon: Icons.request_quote_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    _SummaryCard(
                      title: 'Net Profit/Loss',
                      value: _money(report.netProfit),
                      icon: Icons.account_balance,
                      color: report.netProfit >= 0
                          ? Theme.of(context).colorScheme.secondary
                          : Theme.of(context).colorScheme.error,
                    ),
                    _SummaryCard(
                      title: 'Inventory Loss',
                      value: _money(report.inventoryLoss),
                      icon: Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    _SummaryCard(
                      title: 'bKash Commission',
                      value: _money(report.bkashCommission),
                      icon: Icons.account_balance_wallet,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    _SummaryCard(
                      title: 'Stock Value',
                      value: _money(report.stockValue),
                      icon: Icons.inventory_2,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.insights_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Net P/L = Gross Profit - Due Amount - Inventory Loss + bKash Commission',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Recent Loss Entries',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (widget.controller.adjustments.isEmpty)
                const _EmptyStateCard(
                  title: 'No loss entries',
                  message: 'No inventory adjustments recorded in this period.',
                )
              else
                ...widget.controller.adjustments.map((adjustment) {
                  final scheme = Theme.of(context).colorScheme;
                  final isLoss = adjustment.deltaQty < 0;
                  final stripColor = isLoss
                      ? scheme.error
                      : const Color(0xFF16A34A);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.45),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(width: 4, color: stripColor),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              productNames[adjustment
                                                      .productId] ??
                                                  adjustment.productId,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(height: 3),
                                            Wrap(
                                              spacing: 8,
                                              children: [
                                                Text(
                                                  adjustment.reason,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                                Text(
                                                  'Qty ${adjustment.deltaQty}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: stripColor,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                                Text(
                                                  _dateTimeLabel(
                                                    adjustment.createdAt,
                                                  ),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (adjustment.lossValue > 0)
                                        Text(
                                          _money(adjustment.lossValue),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: stripColor,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _ReportTrendCard extends StatelessWidget {
  const _ReportTrendCard({
    required this.report,
    required this.selectedMetric,
    required this.onMetricChanged,
  });

  final DashboardReport report;
  final _ReportMetric selectedMetric;
  final ValueChanged<_ReportMetric> onMetricChanged;

  @override
  Widget build(BuildContext context) {
    final series = switch (selectedMetric) {
      _ReportMetric.performance => <_ChartPoint>[
        _ChartPoint('Sales', report.salesBilling),
        _ChartPoint('Purchase', report.purchaseBilling),
        _ChartPoint('Gross', report.grossProfit),
        _ChartPoint('Net', report.netProfit),
      ],
      _ReportMetric.risk => <_ChartPoint>[
        _ChartPoint('Due', report.dueAmount),
        _ChartPoint('Loss', report.inventoryLoss),
        _ChartPoint('Net', report.netProfit),
      ],
      _ReportMetric.wallet => <_ChartPoint>[
        _ChartPoint('Cash In', report.bkashIn),
        _ChartPoint('Cash Out', report.bkashOut),
        _ChartPoint('Commission', report.bkashCommission),
      ],
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Text(
                  'Performance Trend',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SegmentedButton<_ReportMetric>(
                  segments: const [
                    ButtonSegment(
                      value: _ReportMetric.performance,
                      label: Text('Performance'),
                    ),
                    ButtonSegment(
                      value: _ReportMetric.risk,
                      label: Text('Risk'),
                    ),
                    ButtonSegment(
                      value: _ReportMetric.wallet,
                      label: Text('Wallet'),
                    ),
                  ],
                  selected: {
                    _ReportMetric.values.firstWhere(
                      (metric) => metric == selectedMetric,
                    ),
                  },
                  onSelectionChanged: (selection) {
                    onMetricChanged(selection.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            _BarSeriesChart(points: series),
          ],
        ),
      ),
    );
  }
}

class _ChartPoint {
  const _ChartPoint(this.label, this.value);

  final String label;
  final double value;
}

class _BarSeriesChart extends StatelessWidget {
  const _BarSeriesChart({required this.points});

  final List<_ChartPoint> points;

  @override
  Widget build(BuildContext context) {
    final maxAbs = points
        .map((point) => point.value.abs())
        .fold<double>(
          1,
          (previous, element) => element > previous ? element : previous,
        );

    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: points
          .map(
            (point) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      point.label,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (point.value.abs() / maxAbs).clamp(0, 1),
                        minHeight: 10,
                        backgroundColor: scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          point.value >= 0 ? scheme.primary : scheme.error,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 110,
                    child: Text(
                      _money(point.value),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _KeyboardProductActionRow extends StatelessWidget {
  const _KeyboardProductActionRow({
    required this.product,
    required this.onQuickSell,
    required this.onQuickStockIn,
  });

  final Product product;
  final VoidCallback onQuickSell;
  final VoidCallback onQuickStockIn;

  @override
  Widget build(BuildContext context) {
    final supportsPiecePack = product.trackInPieces && product.unitsPerPack > 1;

    return _HoverLift(
      child: Card(
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter &&
                HardwareKeyboard.instance.isControlPressed) {
              onQuickStockIn();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              onQuickSell();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.keyI) {
              onQuickStockIn();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.keyS) {
              onQuickSell();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: ListTile(
            title: Text(product.name),
            subtitle: Text(
              '${_categoryLabel(product.category)} • Stock ${_stockDisplay(product)} • '
              '${supportsPiecePack ? '${product.unitsPerPack} pcs/pack' : 'unit item'}',
            ),
            trailing: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onQuickStockIn,
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Stock In'),
                ),
                FilledButton.icon(
                  onPressed: onQuickSell,
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Sell'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _HoverLift(
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 13,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, color: color, size: 18),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              value,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                    color: scheme.onSurface,
                                  ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              title,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MedicineCountBadge extends StatelessWidget {
  const _MedicineCountBadge({
    required this.stockQty,
    required this.unitsPerPack,
    required this.tone,
    this.compact = false,
  });

  final int stockQty;
  final int unitsPerPack;
  final Color tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final safeUnits = unitsPerPack <= 0 ? 1 : unitsPerPack;
    final packs = stockQty ~/ safeUnits;
    final pieces = stockQty % safeUnits;
    final pieceRatio = (pieces / safeUnits).clamp(0, 1).toDouble();
    final textTheme = Theme.of(context).textTheme;

    return Tooltip(
      message: '$packs packs, $pieces pieces • $safeUnits pieces/pack',
      child: Container(
        width: compact ? 56 : 64,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 6,
          vertical: compact ? 4 : 5,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              tone.withValues(alpha: 0.24),
              tone.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(color: tone.withValues(alpha: 0.24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${packs}P',
              style: textTheme.labelLarge?.copyWith(
                color: tone,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${pieces}pc',
              style: textTheme.labelSmall?.copyWith(
                color: tone.withValues(alpha: 0.9),
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: pieceRatio,
                backgroundColor: tone.withValues(alpha: 0.14),
                valueColor: AlwaysStoppedAnimation<Color>(tone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _HoverLift(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StockAlertTile extends StatelessWidget {
  const _StockAlertTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final isOut = product.stockQty == 0;
    final isCritical = product.stockQty <= _criticalStockThreshold && !isOut;
    final color = isOut
        ? Theme.of(context).colorScheme.error
        : isCritical
        ? const Color(0xFF1D4ED8)
        : const Color(0xFF38BDF8);
    final label = isOut
        ? 'OUT'
        : isCritical
        ? 'CRITICAL'
        : 'LOW';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            product.name,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _stockShortDisplay(product),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: color,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int quantity;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onDecrease,
          style: IconButton.styleFrom(
            backgroundColor: scheme.surfaceContainerHigh,
            foregroundColor: scheme.onSurface,
          ),
          icon: const Icon(Icons.remove),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '$quantity',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          onPressed: onIncrease,
          style: IconButton.styleFrom(
            backgroundColor: scheme.secondaryContainer,
            foregroundColor: scheme.onSecondaryContainer,
          ),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inbox_rounded,
              color: scheme.primary.withValues(alpha: 0.7),
              size: 24,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DialogSummaryRow extends StatelessWidget {
  const _DialogSummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _FinanceKpiChip extends StatelessWidget {
  const _FinanceKpiChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [tone.withValues(alpha: 0.22), tone.withValues(alpha: 0.08)],
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HoverLift extends StatefulWidget {
  const _HoverLift({required this.child});

  final Widget child;

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: _microAnimationDuration,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -0.4 : 0, 0),
        decoration: BoxDecoration(
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.shadow.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}

// ── Backup dialog widgets ─────────────────────────────────────────────────────

class _BackupOptionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BackupOptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: scheme.outlineVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _BackupInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          const Text(': ', style: TextStyle(fontSize: 12)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

// ── Multi-device conflict resolution ─────────────────────────────────────────

enum _ImportChoice { merge, replace }

/// Displays a conflict analysis report and lets the user choose between
/// Smart Merge (safe, additive) and Full Replace (destructive).
class _ConflictPreviewDialog extends StatefulWidget {
  final ConflictReport report;
  const _ConflictPreviewDialog({required this.report});

  @override
  State<_ConflictPreviewDialog> createState() => _ConflictPreviewDialogState();
}

class _ConflictPreviewDialogState extends State<_ConflictPreviewDialog> {
  bool _confirmingReplace = false;

  static const Map<String, String> _tableLabels = {
    'products': 'Products',
    'customers': 'Customers',
    'bkash_accounts': 'bKash Accounts',
    'invoices': 'Invoices',
    'invoice_items': 'Invoice Items',
    'invoice_payments': 'Invoice Payments',
    'sales': 'Sales',
    'purchases': 'Purchases',
    'inventory_adjustments': 'Stock Adjustments',
    'bkash_transactions': 'bKash Transactions',
  };

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final scheme = Theme.of(context).colorScheme;

    DateTime? exportedDate;
    try {
      exportedDate = DateTime.parse(report.meta.exportedAt).toLocal();
    } catch (_) {}
    final dateLabel = exportedDate != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(exportedDate)
        : report.meta.exportedAt;
    final deviceLabel = report.meta.deviceId.length >= 8
        ? report.meta.deviceId.substring(0, 8).toUpperCase()
        : report.meta.deviceId.toUpperCase();

    final activeTables = report.tables
        .where((t) => t.localCount > 0 || t.backupCount > 0)
        .toList();

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.compare_arrows_rounded, size: 22),
          SizedBox(width: 10),
          Text('Import Preview'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Backup metadata ──
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    _BackupInfoRow(label: 'Exported', value: dateLabel),
                    _BackupInfoRow(label: 'Device', value: deviceLabel),
                    const _BackupInfoRow(
                      label: 'Integrity',
                      value: '✓ SHA-256 verified',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Status chips ──
              if (report.hasNewData)
                _StatusChip(
                  icon: Icons.add_circle_outline,
                  color: const Color(0xFF059669),
                  label:
                      '${report.totalNewInBackup} new record(s) in this backup — will be added on Smart Merge',
                ),
              if (report.localHasNewerRecords) ...[
                const SizedBox(height: 6),
                _StatusChip(
                  icon: Icons.history_rounded,
                  color: Colors.amber.shade700,
                  label:
                      'This device has records created after the backup was exported',
                ),
              ],
              if (report.hasConflicts) ...[
                const SizedBox(height: 6),
                _StatusChip(
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange.shade700,
                  label:
                      '${report.totalLocalOnly} local record(s) not present in backup — '
                      'kept on Smart Merge, permanently lost on Full Replace',
                ),
              ],
              if (!report.hasNewData &&
                  !report.hasConflicts &&
                  !report.localHasNewerRecords)
                _StatusChip(
                  icon: Icons.check_circle_outline,
                  color: scheme.primary,
                  label:
                      'Backup matches local data exactly — Smart Merge will have no effect',
                ),

              // ── Replace confirmation warning ──
              if (_confirmingReplace) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.delete_forever_outlined,
                        color: Colors.red.shade700,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'ALL current data will be permanently deleted and '
                          'replaced by the backup. This cannot be undone. '
                          'Tap "Confirm Replace" to proceed.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Table-by-table breakdown ──
              if (activeTables.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                const Text(
                  'Table-by-table preview',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                const _ConflictTableRow(
                  label: 'Table',
                  local: 'Local',
                  backup: 'Backup',
                  toAdd: '+ New',
                  localOnly: '± Local',
                  isHeader: true,
                ),
                ...activeTables.map(
                  (t) => _ConflictTableRow(
                    label: _tableLabels[t.table] ?? t.table,
                    local: '${t.localCount}',
                    backup: '${t.backupCount}',
                    toAdd: t.newInBackup > 0 ? '+${t.newInBackup}' : '—',
                    localOnly: t.localOnly > 0 ? '${t.localOnly}' : '—',
                    highlightAdd: t.newInBackup > 0,
                    highlightLocal: t.localOnly > 0,
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // ── Merge explanation ──
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.merge_type_rounded,
                      size: 16,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Smart Merge only adds records that are new in the backup. '
                        'Your local data is never overwritten or deleted.',
                        style: TextStyle(fontSize: 11, color: scheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (!_confirmingReplace)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300),
            ),
            onPressed: () => setState(() => _confirmingReplace = true),
            icon: const Icon(Icons.warning_amber_rounded, size: 16),
            label: const Text('Full Replace ▸'),
          )
        else
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300),
            ),
            onPressed: () => Navigator.pop(context, _ImportChoice.replace),
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: const Text('Confirm Replace'),
          ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _ImportChoice.merge),
          icon: const Icon(Icons.merge_type_rounded, size: 18),
          label: const Text('Smart Merge ✓'),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _StatusChip({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictTableRow extends StatelessWidget {
  final String label;
  final String local;
  final String backup;
  final String toAdd;
  final String localOnly;
  final bool isHeader;
  final bool highlightAdd;
  final bool highlightLocal;

  const _ConflictTableRow({
    required this.label,
    required this.local,
    required this.backup,
    required this.toAdd,
    required this.localOnly,
    this.isHeader = false,
    this.highlightAdd = false,
    this.highlightLocal = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = isHeader
        ? const TextStyle(fontWeight: FontWeight.w600, fontSize: 11)
        : const TextStyle(fontSize: 12);
    final addStyle = base.copyWith(
      color: highlightAdd ? const Color(0xFF059669) : null,
      fontWeight: highlightAdd ? FontWeight.w600 : base.fontWeight,
    );
    final localStyle = base.copyWith(
      color: highlightLocal ? Colors.orange.shade700 : null,
      fontWeight: highlightLocal ? FontWeight.w600 : base.fontWeight,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: isHeader ? scheme.surfaceContainerHighest : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label, style: base)),
          SizedBox(
            width: 44,
            child: Text(local, style: base, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 44,
            child: Text(backup, style: base, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 44,
            child: Text(toAdd, style: addStyle, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 44,
            child: Text(
              localOnly,
              style: localStyle,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
