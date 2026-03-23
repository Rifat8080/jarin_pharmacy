import 'package:intl/intl.dart';

import 'models.dart';
import 'repositories.dart';

class ReportingService {
  ReportingService({required this.transactions, required this.products});

  final TransactionRepository transactions;
  final ProductRepository products;

  ReportWindow buildWindow({
    required ReportPeriod period,
    required DateTime anchor,
  }) {
    final normalized = DateTime(anchor.year, anchor.month, anchor.day);

    switch (period) {
      case ReportPeriod.day:
        final start = normalized;
        final end = start.add(const Duration(days: 1));
        return ReportWindow(
          start: start,
          end: end,
          label: DateFormat('dd MMM yyyy').format(start),
        );
      case ReportPeriod.month:
        final start = DateTime(normalized.year, normalized.month);
        final end = DateTime(normalized.year, normalized.month + 1);
        return ReportWindow(
          start: start,
          end: end,
          label: DateFormat('MMMM yyyy').format(start),
        );
      case ReportPeriod.year:
        final start = DateTime(normalized.year);
        final end = DateTime(normalized.year + 1);
        return ReportWindow(
          start: start,
          end: end,
          label: DateFormat('yyyy').format(start),
        );
    }
  }

  Future<DashboardReport> buildReport({
    required ReportPeriod period,
    required DateTime anchor,
  }) async {
    final window = buildWindow(period: period, anchor: anchor);

    final salesBilling = await transactions.sumForRange(
      table: 'sales',
      column: 'total',
      start: window.start,
      end: window.end,
    );

    final purchaseBilling = await transactions.sumForRange(
      table: 'purchases',
      column: 'total',
      start: window.start,
      end: window.end,
    );

    final grossProfit = await transactions.sumForRange(
      table: 'sales',
      column: 'profit',
      start: window.start,
      end: window.end,
    );

    final dueAmount = await transactions.sumForRange(
      table: 'invoices',
      column: 'due_amount',
      start: window.start,
      end: window.end,
    );

    final inventoryLoss = await transactions.sumForRange(
      table: 'inventory_adjustments',
      column: 'loss_value',
      start: window.start,
      end: window.end,
    );

    final bkashIn = await transactions.sumForRange(
      table: 'bkash_transactions',
      column: 'net_amount',
      start: window.start,
      end: window.end,
      extraWhere: 'type = ?',
      extraArgs: [BkashType.cashIn.name],
    );

    final bkashOut = await transactions.sumForRange(
      table: 'bkash_transactions',
      column: 'amount + charge',
      start: window.start,
      end: window.end,
      extraWhere: 'type = ?',
      extraArgs: [BkashType.cashOut.name],
    );

    final bkashCommission = await transactions.sumForRange(
      table: 'bkash_transactions',
      column: 'amount',
      start: window.start,
      end: window.end,
      extraWhere: 'type = ?',
      extraArgs: [BkashType.commission.name],
    );

    final stockValue = await products.getStockValue();

    final netProfit = grossProfit - dueAmount - inventoryLoss + bkashCommission;

    return DashboardReport(
      salesBilling: salesBilling,
      purchaseBilling: purchaseBilling,
      grossProfit: grossProfit,
      dueAmount: dueAmount,
      inventoryLoss: inventoryLoss,
      netProfit: netProfit,
      bkashIn: bkashIn,
      bkashOut: bkashOut,
      bkashCommission: bkashCommission,
      stockValue: stockValue,
    );
  }
}
