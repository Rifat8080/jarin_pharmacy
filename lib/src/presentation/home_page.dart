import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../domain/models.dart';
import 'app_controller.dart';
import 'app_routes.dart';
import 'invoice_pages.dart';

const int _lowStockThreshold = 10;
const int _criticalStockThreshold = 3;
const double _desktopMaxContentWidth = 1480;
const Duration _microAnimationDuration = Duration(milliseconds: 140);

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
    BkashType.commission => 'Commission',
  };
}

String _stockDisplay(Product product) {
  if (product.trackInPieces &&
      product.category == ProductCategory.medicine &&
      product.unitsPerPack > 1) {
    final packs = product.stockQty ~/ product.unitsPerPack;
    final pieces = product.stockQty % product.unitsPerPack;
    return '$packs pack, $pieces pcs';
  }
  return '${product.stockQty} units';
}

String _stockShortDisplay(Product product) {
  if (product.trackInPieces &&
      product.category == ProductCategory.medicine &&
      product.unitsPerPack > 1) {
    final packs = product.stockQty ~/ product.unitsPerPack;
    final pieces = product.stockQty % product.unitsPerPack;
    return '${packs}P ${pieces}pc';
  }
  return '${product.stockQty}';
}

String _quantityDisplay(Product product, int quantity) {
  if (product.trackInPieces &&
      product.category == ProductCategory.medicine &&
      product.unitsPerPack > 1) {
    final packs = quantity ~/ product.unitsPerPack;
    final pieces = quantity % product.unitsPerPack;
    return '$packs pack, $pieces pcs';
  }
  return '$quantity units';
}

String _deltaQuantityDisplay(Product? product, int deltaQuantity) {
  final sign = deltaQuantity >= 0 ? '+' : '-';
  final absolute = deltaQuantity.abs();

  if (product != null &&
      product.trackInPieces &&
      product.category == ProductCategory.medicine &&
      product.unitsPerPack > 1) {
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
  bool _focusMode = false;

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

  String get _activeTabSubtitle {
    return switch (_selectedTab) {
      0 => 'Offline Smart POS',
      1 => 'Create and manage bills',
      2 => 'Products and inventory records',
      3 => 'Wallet transactions',
      4 => 'Business performance overview',
      5 => 'Customer profiles and dues',
      _ => 'Offline Smart POS',
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

    final pages = <Widget>[
      _DashboardTab(
        controller: controller,
        onNavigate: _navigateTo,
        focusMode: _focusMode,
      ),
      _SellTab(controller: controller, focusMode: _focusMode),
      _InventoryTab(controller: controller, focusMode: _focusMode),
      _BkashTab(controller: controller),
      _ReportsTab(controller: controller, onPickDate: _pickReportDate),
      const CustomerListPage(showScaffold: false),
    ];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_activeTabTitle),
            if (!_focusMode)
              Text(
                _activeTabSubtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _focusMode = !_focusMode;
                  });
                },
                icon: Icon(
                  _focusMode ? Icons.visibility : Icons.visibility_outlined,
                  size: 18,
                ),
                label: Text(_focusMode ? 'Focus On' : 'Focus Off'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: controller.isLoading ? null : controller.refreshAll,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.18),
                    Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.98),
                  ],
                ),
              ),
            ),
          ),
          Column(
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
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _desktopMaxContentWidth,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).colorScheme.shadow.withValues(alpha: 0.06),
                              blurRadius: 22,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              textScaler: _focusMode
                                  ? const TextScaler.linear(1.08)
                                  : const TextScaler.linear(1),
                            ),
                            child: _AnimatedTabStack(
                              selectedIndex: _selectedTab,
                              children: pages,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (controller.isLoading)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Theme.of(
                    context,
                  ).colorScheme.scrim.withValues(alpha: 0.08),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: NavigationBar(
          height: 72,
          labelBehavior: _focusMode
              ? NavigationDestinationLabelBehavior.onlyShowSelected
              : null,
          selectedIndex: _selectedTab,
          onDestinationSelected: (index) {
            if (index == _selectedTab) {
              return;
            }
            Navigator.of(context).pushReplacementNamed(_routeForTab(index));
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.point_of_sale_outlined),
              selectedIcon: Icon(Icons.point_of_sale),
              label: 'Sell',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: lowStockCount + outOfStockCount > 0,
                label: Text('${lowStockCount + outOfStockCount}'),
                child: const Icon(Icons.inventory_2_outlined),
              ),
              selectedIcon: const Icon(Icons.inventory_2),
              label: 'Stock',
            ),
            const NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: 'bKash',
            ),
            const NavigationDestination(
              icon: Icon(Icons.query_stats_outlined),
              selectedIcon: Icon(Icons.query_stats),
              label: 'Reports',
            ),
            const NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Customers',
            ),
          ],
        ),
      ),
    );
  }

  void _navigateTo(int index) {
    if (index == _selectedTab) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(_routeForTab(index));
  }

  String _routeForTab(int index) {
    return switch (index) {
      0 => AppRoutes.home,
      1 => AppRoutes.sell,
      2 => AppRoutes.stock,
      3 => AppRoutes.bkash,
      4 => AppRoutes.reports,
      5 => AppRoutes.customers,
      _ => AppRoutes.home,
    };
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
}

class _DashboardTab extends StatefulWidget {
  const _DashboardTab({
    required this.controller,
    required this.onNavigate,
    required this.focusMode,
  });

  final PharmacyAppController controller;
  final void Function(int index) onNavigate;
  final bool focusMode;

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
                        'Add medicine stock by packs and extra pieces',
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
            pieceInput >= product.unitsPerPack ||
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
      note: 'Quick stock-in (pack)',
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
    final lowStockProducts =
        controller.products
            .where((product) => product.stockQty <= _lowStockThreshold)
            .toList()
          ..sort((left, right) => left.stockQty.compareTo(right.stockQty));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Today at a glance',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: widget.focusMode ? 4 : 8),
        TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Universal search: type product and quick Sell/Stock In',
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
        ),
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          if (!widget.focusMode)
            Text(
              'Search Results (Enter=Sell, Ctrl+Enter=Stock In)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 6),
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
        ],
        if (report != null)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryCard(
                title: 'Sales',
                value: _money(report.salesBilling),
                icon: Icons.trending_up,
                color: Colors.green,
              ),
              _SummaryCard(
                title: 'Purchases',
                value: _money(report.purchaseBilling),
                icon: Icons.shopping_bag_outlined,
                color: Colors.blue,
              ),
              _SummaryCard(
                title: 'Net Profit',
                value: _money(report.netProfit),
                icon: Icons.account_balance,
                color: report.netProfit >= 0 ? Colors.teal : Colors.red,
              ),
              _SummaryCard(
                title: 'Due',
                value: _money(report.dueAmount),
                icon: Icons.request_quote_outlined,
                color: Colors.deepOrange,
              ),
              _SummaryCard(
                title: 'Stock Value',
                value: _money(report.stockValue),
                icon: Icons.inventory,
                color: Colors.orange,
              ),
            ],
          )
        else
          const _EmptyStateCard(
            title: 'No dashboard data yet',
            message: 'Add products and start recording purchases or sales.',
          ),
        if (report != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Net P/L = Gross Profit - Due Amount - Inventory Loss + bKash Commission',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _QuickActionTile(
              title: 'New Bill',
              subtitle: 'Sell products fast',
              icon: Icons.point_of_sale,
              color: Colors.green,
              onTap: () => widget.onNavigate(1),
            ),
            _QuickActionTile(
              title: 'Stock',
              subtitle: 'Receive, edit, adjust',
              icon: Icons.add_business,
              color: Colors.blue,
              onTap: () => widget.onNavigate(2),
            ),
            _QuickActionTile(
              title: 'Reports',
              subtitle: 'Check business summary',
              icon: Icons.inventory_2,
              color: Colors.orange,
              onTap: () => widget.onNavigate(4),
            ),
            _QuickActionTile(
              title: 'bKash',
              subtitle: 'Record service entries',
              icon: Icons.account_balance_wallet,
              color: Colors.pink,
              onTap: () => widget.onNavigate(3),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Stock alerts',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (lowStockProducts.isEmpty)
          const _EmptyStateCard(
            title: 'No low-stock products',
            message: 'Everything currently has healthy stock levels.',
          )
        else
          ...lowStockProducts
              .take(8)
              .map((product) => _StockAlertTile(product: product)),
      ],
    );
  }
}

class _SellTab extends StatefulWidget {
  const _SellTab({required this.controller, required this.focusMode});

  final PharmacyAppController controller;
  final bool focusMode;

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
    final entries = data.entries
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
          ? const Center(child: Text('No in-stock products found.'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
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

                return Card(
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        _addProductToCart(product, quantityToAdd: 1);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: ListTile(
                      title: Row(
                        children: [
                          Expanded(child: Text(product.name)),
                          if (hasDgdaData)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'DGDA',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                    ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '${_categoryLabel(product.category)} • ${_money(product.sellPrice)} • Stock ${_stockDisplay(product)}',
                      ),
                      trailing: supportsPiecePack
                          ? Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () => _addProductToCart(
                                    product,
                                    quantityToAdd: product.unitsPerPack,
                                  ),
                                  child: const Text('Pack'),
                                ),
                                FilledButton(
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
                              onPressed: () =>
                                  _addProductToCart(product, quantityToAdd: 1),
                              icon: const Icon(Icons.add),
                              label: Text(
                                quantityInCart == 0
                                    ? 'Add'
                                    : 'x$quantityInCart',
                              ),
                            ),
                    ),
                  ),
                );
              },
            );
    }

    Widget buildCartPane() {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Column(
          children: [
            ListTile(
              title: const Text('Current Bill'),
              subtitle: Text('${_cart.length} line item(s)'),
            ),
            Expanded(
              child: _cart.isEmpty
                  ? const Center(child: Text('Add products to start a bill.'))
                  : ListView.builder(
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
                            'Generic: ${item.product.dgdaGenericName}',
                          if ((item.product.dgdaDosageForm ?? '')
                              .trim()
                              .isNotEmpty)
                            'Form: ${item.product.dgdaDosageForm}',
                          if ((item.product.dgdaStrength ?? '')
                              .trim()
                              .isNotEmpty)
                            'Strength: ${item.product.dgdaStrength}',
                        ];

                        final subtitleBuffer = StringBuffer(
                          '${supportsPiecePack ? _cartQuantityLabel(item.product, item.quantity) : item.quantity} x ${_money(item.unitPrice)} = ${_money(item.total)}',
                        );
                        if (dgdaSummary.isNotEmpty) {
                          subtitleBuffer.write('\n${dgdaSummary.join(' • ')}');
                        }

                        return ListTile(
                          title: Text(item.product.name),
                          subtitle: Text(subtitleBuffer.toString()),
                          isThreeLine: dgdaSummary.isNotEmpty,
                          leading: _QuantityStepper(
                            quantity: item.quantity,
                            onDecrease: () => _changeCartQuantity(index, -1),
                            onIncrease: () => _changeCartQuantity(index, 1),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (supportsPiecePack)
                                IconButton(
                                  onPressed: () {
                                    final removed = _changeCartQuantity(
                                      index,
                                      -item.product.unitsPerPack,
                                    );
                                    if (removed && mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '${item.product.name} removed from bill.',
                                          ),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                  },
                                  tooltip: 'Pack -',
                                  icon: const Icon(
                                    Icons.indeterminate_check_box_outlined,
                                  ),
                                ),
                              if (supportsPiecePack)
                                IconButton(
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
                                  icon: const Icon(Icons.add_box_outlined),
                                ),
                              if (hasDgdaData)
                                IconButton(
                                  onPressed: () => _showDgdaDataDialog(
                                    title: item.product.name,
                                    data: item.product.dgdaData,
                                  ),
                                  tooltip: 'DGDA details',
                                  icon: const Icon(Icons.info_outline),
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
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '${item.product.name} removed from bill.',
                                          ),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    }
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
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: 'Bill Note (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        _money(_grandTotal),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                        child: FilledButton.icon(
                          onPressed: _cart.isEmpty ? null : _recordSaleCart,
                          icon: const Icon(Icons.receipt_long),
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
          padding: EdgeInsets.fromLTRB(16, widget.focusMode ? 10 : 16, 16, 8),
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
                  Expanded(flex: 6, child: buildProductPane()),
                  Divider(
                    height: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  Expanded(flex: 5, child: buildCartPane()),
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
  const _InventoryTab({required this.controller, required this.focusMode});

  final PharmacyAppController controller;
  final bool focusMode;

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
          (product.dgdaStrength ?? '').toLowerCase().contains(normalizedQuery) ||
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
    final entries = data.entries
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
                                  onTap: () => Navigator.pop(
                                    dialogContext,
                                    medicine,
                                  ),
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
                        'Add medicine stock by packs and extra pieces',
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
            pieceInput >= product.unitsPerPack ||
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
                        labelText: selectedCategory == ProductCategory.medicine
                            ? 'Buy Price per Pack'
                            : 'Buy Price',
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
                        labelText: selectedCategory == ProductCategory.medicine
                            ? 'Sell Price per Pack'
                            : 'Sell Price',
                        prefixText: '৳ ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: selectedCategory == ProductCategory.medicine
                          ? stockPackController
                          : stockController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: selectedCategory == ProductCategory.medicine
                            ? 'Current Stock (packs)'
                            : 'Current Stock',
                      ),
                    ),
                    if (selectedCategory == ProductCategory.medicine) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: stockPieceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Extra Pieces',
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
                          'Medicines are sold by piece by default.',
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

    final isMedicine = selectedCategory == ProductCategory.medicine;
    final safeUnitsPerPack = isMedicine ? unitsPerPack : 1;
    final buyPricePerUnit = isMedicine ? buyPrice / safeUnitsPerPack : buyPrice;
    final sellPricePerUnit = isMedicine
        ? sellPrice / safeUnitsPerPack
        : sellPrice;
    final stockQty = isMedicine
        ? (stockPacks * safeUnitsPerPack) + stockPieces
        : stockQtyUnits;
    if (stockQty == null ||
        stockQty < 0 ||
        stockPieces < 0 ||
        stockPieces >= safeUnitsPerPack) {
      return;
    }

    try {
      final selectedDgdaData = selectedDgdaMedicine?.allData ?? const {};
      if (product == null) {
        await widget.controller.addProduct(
          name: nameController.text.trim(),
          category: selectedCategory,
          buyPrice: buyPricePerUnit,
          sellPrice: sellPricePerUnit,
          openingStock: stockQty,
          unitsPerPack: safeUnitsPerPack,
          trackInPieces: isMedicine,
          dgdaBrandId: selectedDgdaMedicine?.brandId,
          dgdaType: selectedDgdaMedicine?.type,
          dgdaSlug: selectedDgdaMedicine?.slug,
          dgdaGenericName: selectedDgdaMedicine?.genericName,
          dgdaStrength: selectedDgdaMedicine?.strength,
          dgdaDosageForm: selectedDgdaMedicine?.dosageForm,
          dgdaManufacturer: selectedDgdaMedicine?.manufacturer,
          dgdaPackageContainer: selectedDgdaMedicine?.packageContainer,
          dgdaPackageSize: selectedDgdaMedicine?.packageSize,
          dgdaData: selectedDgdaData,
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
          trackInPieces: isMedicine,
          dgdaBrandId: selectedDgdaMedicine?.brandId,
          dgdaType: selectedDgdaMedicine?.type,
          dgdaSlug: selectedDgdaMedicine?.slug,
          dgdaGenericName: selectedDgdaMedicine?.genericName,
          dgdaStrength: selectedDgdaMedicine?.strength,
          dgdaDosageForm: selectedDgdaMedicine?.dosageForm,
          dgdaManufacturer: selectedDgdaMedicine?.manufacturer,
          dgdaPackageContainer: selectedDgdaMedicine?.packageContainer,
          dgdaPackageSize: selectedDgdaMedicine?.packageSize,
          dgdaData: selectedDgdaMedicine == null ? null : selectedDgdaData,
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
          ? const Center(child: Text('No products found.'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: filteredProducts.length,
              itemBuilder: (context, index) {
                final product = filteredProducts[index];
                final hasDgdaData = product.hasDgdaData;
                final stockColor = product.stockQty == 0
                    ? Colors.red
                    : product.stockQty <= _criticalStockThreshold
                    ? Colors.deepOrange
                    : product.stockQty <= _lowStockThreshold
                    ? Colors.orange
                    : Colors.green;

                return Card(
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        _showStockInDialog(product);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: ListTile(
                      title: Row(
                        children: [
                          Expanded(child: Text(product.name)),
                          if (hasDgdaData)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'DGDA',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                    ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '${_categoryLabel(product.category)} • Buy ${_money(product.buyPrice)} • Sell ${_money(product.sellPrice)} • Stock ${_stockDisplay(product)}${product.dgdaGenericName == null || product.dgdaGenericName!.isEmpty ? '' : '\nGeneric: ${product.dgdaGenericName}'}${product.dgdaManufacturer == null || product.dgdaManufacturer!.isEmpty ? '' : '\nManufacturer: ${product.dgdaManufacturer}'}',
                      ),
                      isThreeLine: product.dgdaGenericName != null,
                      leading: CircleAvatar(
                        backgroundColor: stockColor.withValues(alpha: 0.15),
                        child: Text(
                          _stockShortDisplay(product),
                          style: TextStyle(
                            color: stockColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      trailing: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 230),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasDgdaData)
                              IconButton(
                                tooltip: 'DGDA details',
                                onPressed: () => _showDgdaDataDialog(
                                  title: product.name,
                                  data: product.dgdaData,
                                ),
                                icon: const Icon(Icons.info_outline),
                              ),
                            TextButton.icon(
                              onPressed: () => _showStockInDialog(product),
                              icon: const Icon(Icons.add_box_outlined),
                              label: const Text('Stock In'),
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
                      ),
                    ),
                  ),
                );
              },
            );
    }

    Widget recordsPane() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stock In Records',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
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
                  icon: const Icon(Icons.calendar_today),
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
            const SizedBox(height: 8),
            Expanded(
              child: _isLoadingStockInRecords
                  ? const Center(child: CircularProgressIndicator())
                  : _recordsView == 'stock_in'
                  ? (stockInRecords.isEmpty
                        ? const Center(
                            child: Text('No stock in records for this filter.'),
                          )
                        : ListView.separated(
                            itemCount: stockInRecords.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final purchase = stockInRecords[index];
                              final product = productsById[purchase.productId];
                              final title = product?.name ?? purchase.productId;
                              final quantityLabel = product == null
                                  ? '${purchase.quantity} units'
                                  : _quantityDisplay(
                                      product,
                                      purchase.quantity,
                                    );

                              return Card(
                                child: ListTile(
                                  title: Text(title),
                                  subtitle: Text(
                                    '${_dateTimeLabel(purchase.createdAt)} • Qty $quantityLabel • Unit ${_money(purchase.unitPrice)}',
                                  ),
                                  trailing: Text(
                                    _money(purchase.total),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ))
                  : (adjustmentRecords.isEmpty
                        ? const Center(
                            child: Text(
                              'No adjustment records for this filter.',
                            ),
                          )
                        : ListView.separated(
                            itemCount: adjustmentRecords.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final adjustment = adjustmentRecords[index];
                              final product =
                                  productsById[adjustment.productId];
                              final title =
                                  product?.name ?? adjustment.productId;
                              final deltaLabel = _deltaQuantityDisplay(
                                product,
                                adjustment.deltaQty,
                              );

                              return Card(
                                child: ListTile(
                                  title: Text(title),
                                  subtitle: Text(
                                    '${_dateTimeLabel(adjustment.createdAt)} • ${adjustment.reason} • Qty $deltaLabel',
                                  ),
                                  trailing: Text(
                                    _money(adjustment.lossValue),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            },
                          )),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.focusMode ? 10 : 16, 16, 8),
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
  Future<void> _showBkashDialog() async {
    final amountController = TextEditingController();
    final chargeController = TextEditingController(text: '0');
    final noteController = TextEditingController();
    var selectedType = BkashType.cashIn;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Record bKash Transaction'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<BkashType>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: BkashType.values
                          .map(
                            (type) => DropdownMenuItem<BkashType>(
                              value: type,
                              child: Text(_bkashTypeLabel(type)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setStateDialog(() {
                          selectedType = value;
                        });
                      },
                    ),
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

    if (confirmed != true) {
      return;
    }

    final amount = double.tryParse(amountController.text.trim());
    final charge = double.tryParse(chargeController.text.trim());
    if (amount == null || charge == null) {
      return;
    }

    try {
      await widget.controller.recordBkash(
        type: selectedType,
        amount: amount,
        charge: charge,
        note: noteController.text.trim().isEmpty
            ? null
            : noteController.text.trim(),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
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

  @override
  Widget build(BuildContext context) {
    final report = widget.controller.dashboardReport;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: _showBkashDialog,
                icon: const Icon(Icons.add),
                label: const Text('Record bKash'),
              ),
              const SizedBox(width: 16),
              if (report != null)
                Expanded(
                  child: Text(
                    'In ${_money(report.bkashIn)} • Out ${_money(report.bkashOut)} • Commission ${_money(report.bkashCommission)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.controller.bkashTransactions.isEmpty
                ? const _EmptyStateCard(
                    title: 'No bKash entries',
                    message:
                        'Record bKash cash-in, cash-out, and commissions here.',
                  )
                : ListView.separated(
                    itemCount: widget.controller.bkashTransactions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final transaction =
                          widget.controller.bkashTransactions[index];
                      return Card(
                        child: ListTile(
                          title: Text(_bkashTypeLabel(transaction.type)),
                          subtitle: Text(
                            '${_dateTimeLabel(transaction.createdAt)} • Amount ${_money(transaction.amount)} • Charge ${_money(transaction.charge)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _money(transaction.netAmount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                onPressed: () => _deleteBkash(transaction),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReportsTab extends StatelessWidget {
  const _ReportsTab({required this.controller, required this.onPickDate});

  final PharmacyAppController controller;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final report = controller.dashboardReport;
    final productNames = <String, String>{
      for (final product in controller.products) product.id!: product.name,
    };

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Row(
            children: [
              Expanded(
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
                  selected: <ReportPeriod>{controller.reportPeriod},
                  onSelectionChanged: (selection) {
                    controller.setReportPeriod(selection.first);
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onPickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(controller.reportWindow?.label ?? 'Pick Date'),
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
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryCard(
                  title: 'Sales Billing',
                  value: _money(report.salesBilling),
                  icon: Icons.receipt_long,
                  color: Colors.green,
                ),
                _SummaryCard(
                  title: 'Purchase Billing',
                  value: _money(report.purchaseBilling),
                  icon: Icons.shopping_cart_outlined,
                  color: Colors.blue,
                ),
                _SummaryCard(
                  title: 'Gross Profit',
                  value: _money(report.grossProfit),
                  icon: Icons.ssid_chart,
                  color: Colors.teal,
                ),
                _SummaryCard(
                  title: 'Due Amount',
                  value: _money(report.dueAmount),
                  icon: Icons.request_quote_outlined,
                  color: Colors.deepOrange,
                ),
                _SummaryCard(
                  title: 'Net Profit/Loss',
                  value: _money(report.netProfit),
                  icon: Icons.account_balance,
                  color: report.netProfit >= 0 ? Colors.teal : Colors.red,
                ),
                _SummaryCard(
                  title: 'Inventory Loss',
                  value: _money(report.inventoryLoss),
                  icon: Icons.warning_amber_rounded,
                  color: Colors.red,
                ),
                _SummaryCard(
                  title: 'bKash Commission',
                  value: _money(report.bkashCommission),
                  icon: Icons.account_balance_wallet,
                  color: Colors.pink,
                ),
                _SummaryCard(
                  title: 'Stock Value',
                  value: _money(report.stockValue),
                  icon: Icons.inventory_2,
                  color: Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Net P/L = Gross Profit - Due Amount - Inventory Loss + bKash Commission',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
          if (controller.adjustments.isEmpty)
            const Text('No inventory loss adjustments in this period.')
          else
            ...controller.adjustments.map(
              (adjustment) => Card(
                child: ListTile(
                  title: Text(
                    productNames[adjustment.productId] ?? adjustment.productId,
                  ),
                  subtitle: Text(
                    '${adjustment.reason} • Qty ${adjustment.deltaQty} • ${_dateTimeLabel(adjustment.createdAt)}',
                  ),
                  trailing: Text(_money(adjustment.lossValue)),
                ),
              ),
            ),
        ],
      ),
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

    return SizedBox(
      width: 240,
      child: _HoverLift(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
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

    return SizedBox(
      width: 220,
      child: _HoverLift(
        child: Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
    final color = product.stockQty == 0
        ? Colors.red
        : product.stockQty <= _criticalStockThreshold
        ? Colors.deepOrange
        : Colors.orange;

    return _HoverLift(
      child: Card(
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.warning_amber_rounded, color: color),
          ),
          title: Text(product.name),
          subtitle: Text(
            '${_categoryLabel(product.category)} • Stock ${_stockDisplay(product)}',
          ),
          trailing: Text(
            _money(product.sellPrice),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.inbox_outlined,
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
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

class _AnimatedTabStack extends StatelessWidget {
  const _AnimatedTabStack({
    required this.selectedIndex,
    required this.children,
  });

  final int selectedIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: List.generate(children.length, (index) {
        final selected = index == selectedIndex;

        return IgnorePointer(
          ignoring: !selected,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: selected ? Offset.zero : const Offset(0.02, 0),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              opacity: selected ? 1 : 0,
              child: TickerMode(enabled: selected, child: children[index]),
            ),
          ),
        );
      }),
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
      child: AnimatedScale(
        duration: _microAnimationDuration,
        curve: Curves.easeOut,
        scale: _hovered ? 1.01 : 1,
        child: AnimatedContainer(
          duration: _microAnimationDuration,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -1 : 0, 0),
          child: widget.child,
        ),
      ),
    );
  }
}
