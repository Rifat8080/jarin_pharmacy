import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../app.dart';
import '../domain/models.dart';
import 'app_routes.dart';

String _invoiceMoney(num value) {
  return NumberFormat.currency(symbol: '৳', decimalDigits: 2).format(value);
}

String _invoiceMoneyPrint(num value) {
  return 'BDT ${value.toStringAsFixed(2)}';
}

String _invoiceDate(DateTime value) {
  return DateFormat('dd MMM yyyy, hh:mm a').format(value);
}

String _invoiceStatusLabel(InvoicePaymentStatus status) {
  switch (status) {
    case InvoicePaymentStatus.paid:
      return 'Paid';
    case InvoicePaymentStatus.partial:
      return 'Partial';
    case InvoicePaymentStatus.due:
      return 'Due';
  }
}

Color _invoiceStatusColor(BuildContext context, InvoicePaymentStatus status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case InvoicePaymentStatus.paid:
      return scheme.primary;
    case InvoicePaymentStatus.partial:
      return scheme.tertiary;
    case InvoicePaymentStatus.due:
      return scheme.error;
  }
}

String _invoiceQty(Product? product, int quantity) {
  if (product != null && product.trackInPieces && product.unitsPerPack > 1) {
    final packs = quantity ~/ product.unitsPerPack;
    final pieces = quantity % product.unitsPerPack;
    return '$packs pack, $pieces pcs';
  }
  return '$quantity units';
}

String _formatInvoiceDgdaFieldLabel(String rawKey) {
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

String _cleanInvoiceDgdaFieldValue(String value) {
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

class InvoiceListPage extends ConsumerWidget {
  const InvoiceListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        actions: [
          IconButton(
            tooltip: 'Customers',
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.customers),
            icon: const Icon(Icons.people_alt_outlined),
          ),
        ],
      ),
      body: controller.invoices.isEmpty
          ? const Center(child: Text('No invoices yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: controller.invoices.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final invoice = controller.invoices[index];
                final statusColor = _invoiceStatusColor(
                  context,
                  invoice.paymentStatus,
                );
                return InkWell(
                  onTap: () {
                    Navigator.of(context).pushNamed(
                      AppRoutes.invoiceShow,
                      arguments: invoice.id,
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).colorScheme.shadow.withValues(alpha: 0.04),
                          blurRadius: 6,
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
                            Container(width: 4, color: statusColor),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            invoice.invoiceNumber,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            invoice.customerName ??
                                                'Walk-in customer',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _invoiceDate(invoice.createdAt),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          _invoiceMoney(invoice.total),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            _invoiceStatusLabel(
                                              invoice.paymentStatus,
                                            ),
                                            style: TextStyle(
                                              color: statusColor,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        if (invoice.dueAmount > 0) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            'Due ${_invoiceMoney(invoice.dueAmount)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error,
                                                ),
                                          ),
                                        ],
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
              },
            ),
    );
  }
}

class InvoiceDetailsPage extends ConsumerStatefulWidget {
  const InvoiceDetailsPage({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  ConsumerState<InvoiceDetailsPage> createState() => _InvoiceDetailsPageState();
}

class _InvoiceDetailsPageState extends ConsumerState<InvoiceDetailsPage> {
  late Future<InvoiceDetails?> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = ref
        .read(appControllerProvider)
        .getInvoiceDetails(widget.invoiceId);
  }

  Future<void> _refresh() async {
    setState(() {
      _detailsFuture = ref
          .read(appControllerProvider)
          .getInvoiceDetails(widget.invoiceId);
    });
    await _detailsFuture;
  }

  Future<void> _showDgdaDataDialog({
    required String title,
    required Map<String, String> data,
  }) async {
    final entries =
        data.entries
            .map(
              (entry) => MapEntry(
                _formatInvoiceDgdaFieldLabel(entry.key),
                _cleanInvoiceDgdaFieldValue(entry.value),
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

  Future<void> _showPaymentDialog(InvoiceDetails details) async {
    final amountController = TextEditingController(
      text: details.invoice.dueAmount.toStringAsFixed(2),
    );
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Record Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Invoice due: ${_invoiceMoney(details.invoice.dueAmount)}'),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Payment Amount',
                  prefixText: '৳ ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Payment Note (optional)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save Payment'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final amount = double.tryParse(amountController.text.trim());
    if (amount == null) {
      return;
    }

    try {
      await ref
          .read(appControllerProvider)
          .recordInvoicePayment(
            invoiceId: details.invoice.id!,
            amount: amount,
            note: noteController.text.trim().isEmpty
                ? null
                : noteController.text.trim(),
          );
      await _refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded successfully.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to record payment: $error')),
      );
    }
  }

  Future<void> _printInvoice(InvoiceDetails details) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Text(
              'Jarin Pharmacy',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Invoice: ${details.invoice.invoiceNumber}'),
            pw.Text('Date: ${_invoiceDate(details.invoice.createdAt)}'),
            pw.Text(
              'Customer: ${details.invoice.customerName ?? 'Walk-in customer'}',
            ),
            if ((details.invoice.customerPhone ?? '').trim().isNotEmpty)
              pw.Text('Phone: ${details.invoice.customerPhone}'),
            pw.Text(
              'Status: ${_invoiceStatusLabel(details.invoice.paymentStatus)}',
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: ['Item', 'Qty', 'Unit Price', 'Total'],
              data: details.items
                  .map(
                    (item) => [
                      item.productName,
                      item.quantity.toString(),
                      _invoiceMoneyPrint(item.unitPrice),
                      _invoiceMoneyPrint(item.total),
                    ],
                  )
                  .toList(),
            ),
            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Total: ${_invoiceMoneyPrint(details.invoice.total)}',
                  ),
                  pw.Text(
                    'Paid: ${_invoiceMoneyPrint(details.invoice.amountPaid)}',
                  ),
                  pw.Text(
                    'Due: ${_invoiceMoneyPrint(details.invoice.dueAmount)}',
                  ),
                  pw.Text(
                    'Cash Received: ${_invoiceMoneyPrint(details.invoice.cashReceived)}',
                  ),
                  pw.Text(
                    'Change Returned: ${_invoiceMoneyPrint(details.invoice.changeReturned)}',
                  ),
                ],
              ),
            ),
            if (details.payments.isNotEmpty) ...[
              pw.SizedBox(height: 18),
              pw.Text(
                'Payment History',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              ...details.payments.map(
                (payment) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                    '${_invoiceDate(payment.createdAt)}  ${_invoiceMoneyPrint(payment.amount)}${payment.note == null ? '' : '  ${payment.note}'}',
                  ),
                ),
              ),
            ],
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InvoiceDetails?>(
      future: _detailsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final details = snapshot.data;
        if (details == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Invoice')),
            body: const Center(child: Text('Invoice not found.')),
          );
        }

        final productsById = {
          for (final product in ref.watch(appControllerProvider).products)
            product.id!: product,
        };

        return Scaffold(
          appBar: AppBar(
            title: Text(details.invoice.invoiceNumber),
            actions: [
              IconButton(
                tooltip: 'Print invoice',
                onPressed: () => _printInvoice(details),
                icon: const Icon(Icons.print_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        details.invoice.invoiceNumber,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Customer: ${details.invoice.customerName ?? 'Walk-in customer'}',
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _invoiceStatusColor(
                                context,
                                details.invoice.paymentStatus,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _invoiceStatusLabel(
                                details.invoice.paymentStatus,
                              ),
                              style: TextStyle(
                                color: _invoiceStatusColor(
                                  context,
                                  details.invoice.paymentStatus,
                                ),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if ((details.invoice.customerPhone ?? '')
                          .trim()
                          .isNotEmpty)
                        Text('Phone: ${details.invoice.customerPhone}'),
                      Text('Date: ${_invoiceDate(details.invoice.createdAt)}'),
                      Text(
                        'Amount Paid: ${_invoiceMoney(details.invoice.amountPaid)}',
                      ),
                      Text('Due: ${_invoiceMoney(details.invoice.dueAmount)}'),
                      Text(
                        'Cash Received: ${_invoiceMoney(details.invoice.cashReceived)}',
                      ),
                      Text(
                        'Change Returned: ${_invoiceMoney(details.invoice.changeReturned)}',
                      ),
                      if ((details.invoice.note ?? '').trim().isNotEmpty)
                        Text('Note: ${details.invoice.note}'),
                      if (details.customer != null) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushNamed(
                              AppRoutes.customerShow,
                              arguments: details.customer!.id,
                            );
                          },
                          icon: const Icon(Icons.person_outline),
                          label: const Text('Open Customer Profile'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => _printInvoice(details),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print Invoice'),
                  ),
                  if (details.invoice.dueAmount > 0)
                    OutlinedButton.icon(
                      onPressed: () => _showPaymentDialog(details),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Record Payment'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Invoice Items',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...details.items.map((item) {
                final product = productsById[item.productId];
                final hasDgdaData = product?.hasDgdaData ?? false;
                final dgdaSummary = <String>[
                  if ((product?.dgdaGenericName ?? '').trim().isNotEmpty)
                    'Generic: ${product?.dgdaGenericName}',
                  if ((product?.dgdaDosageForm ?? '').trim().isNotEmpty)
                    'Form: ${product?.dgdaDosageForm}',
                  if ((product?.dgdaStrength ?? '').trim().isNotEmpty)
                    'Strength: ${product?.dgdaStrength}',
                  if ((product?.dgdaManufacturer ?? '').trim().isNotEmpty)
                    'Manufacturer: ${product?.dgdaManufacturer}',
                ];

                final subtitleBuffer = StringBuffer(
                  '${_invoiceQty(product, item.quantity)} • ${_invoiceMoney(item.unitPrice)} each',
                );
                if (dgdaSummary.isNotEmpty) {
                  subtitleBuffer.write('\n${dgdaSummary.join(' • ')}');
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: Text(item.productName),
                          subtitle: Text(subtitleBuffer.toString()),
                          isThreeLine: dgdaSummary.isNotEmpty,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _invoiceMoney(item.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Profit ${_invoiceMoney(item.profit)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (hasDgdaData)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => _showDgdaDataDialog(
                                  title: item.productName,
                                  data: product!.dgdaData,
                                ),
                                icon: const Icon(Icons.medication_outlined),
                                label: const Text('View full DGDA details'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _InvoiceSummaryRow(
                        label: 'Total',
                        value: _invoiceMoney(details.invoice.total),
                      ),
                      const SizedBox(height: 8),
                      _InvoiceSummaryRow(
                        label: 'Amount Paid',
                        value: _invoiceMoney(details.invoice.amountPaid),
                      ),
                      const SizedBox(height: 8),
                      _InvoiceSummaryRow(
                        label: 'Due Amount',
                        value: _invoiceMoney(details.invoice.dueAmount),
                      ),
                      const SizedBox(height: 8),
                      _InvoiceSummaryRow(
                        label: 'Cash Received',
                        value: _invoiceMoney(details.invoice.cashReceived),
                      ),
                      const SizedBox(height: 8),
                      _InvoiceSummaryRow(
                        label: 'Change Returned',
                        value: _invoiceMoney(details.invoice.changeReturned),
                      ),
                      const SizedBox(height: 8),
                      _InvoiceSummaryRow(
                        label: 'Cost',
                        value: _invoiceMoney(details.invoice.costTotal),
                      ),
                      const SizedBox(height: 8),
                      _InvoiceSummaryRow(
                        label: 'Profit',
                        value: _invoiceMoney(details.invoice.profit),
                        emphasize: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Payment History',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (details.payments.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No additional payments recorded yet.'),
                  ),
                )
              else
                ...details.payments.map(
                  (payment) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.payments_outlined),
                        title: Text(_invoiceMoney(payment.amount)),
                        subtitle: Text(
                          '${_invoiceDate(payment.createdAt)}${payment.note == null ? '' : ' • ${payment.note}'}',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class CustomerListPage extends ConsumerStatefulWidget {
  const CustomerListPage({super.key, this.showScaffold = true});

  final bool showScaffold;

  @override
  ConsumerState<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends ConsumerState<CustomerListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final filteredCustomers = controller.customers.where((customer) {
      if (_query.trim().isEmpty) {
        return true;
      }

      final normalizedQuery = _query.trim().toLowerCase();
      return customer.name.toLowerCase().contains(normalizedQuery) ||
          (customer.phone ?? '').toLowerCase().contains(normalizedQuery);
    }).toList();

    final content = controller.customers.isEmpty
        ? const Center(child: Text('No customer profiles yet.'))
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _query = value;
                    });
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: 'Search customer by name or phone',
                    suffixIcon: _query.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _query = '';
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: filteredCustomers.isEmpty
                    ? const Center(child: Text('No matching customer found.'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: filteredCustomers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final customer = filteredCustomers[index];
                          final summary = controller
                              .customerDueSummaries[customer.id ?? ''];
                          final invoiceCount = summary?.invoiceCount ?? 0;
                          final totalDue = summary?.totalDue ?? 0;
                          final totalPaid = summary?.totalPaid ?? 0;
                          final avatarLabel = customer.name.isEmpty
                              ? '?'
                              : customer.name.substring(0, 1).toUpperCase();
                          final hasDue = totalDue > 0;
                          final scheme = Theme.of(context).colorScheme;

                          return InkWell(
                            onTap: () {
                              Navigator.of(context).pushNamed(
                                AppRoutes.customerShow,
                                arguments: customer.id,
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: scheme.shadow.withValues(alpha: 0.04),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          scheme.primary,
                                          scheme.secondary,
                                        ],
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        avatarLabel,
                                        style: TextStyle(
                                          color: scheme.onPrimary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          customer.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${customer.phone ?? 'No phone'} · $invoiceCount invoice${invoiceCount == 1 ? '' : 's'}',
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
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Due ${_invoiceMoney(totalDue)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: hasDue
                                              ? scheme.error
                                              : scheme.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Paid ${_invoiceMoney(totalPaid)}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
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
            ],
          );

    if (!widget.showScaffold) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      body: content,
    );
  }
}

class CustomerProfilePage extends ConsumerWidget {
  const CustomerProfilePage({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appControllerProvider);

    return FutureBuilder<CustomerProfile?>(
      future: controller.getCustomerProfile(customerId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final profile = snapshot.data;
        if (profile == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Customer Profile')),
            body: const Center(child: Text('Customer not found.')),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text(profile.customer.name)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Customer header card ──
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primaryContainer,
                      Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.5),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.7),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          profile.customer.name.isNotEmpty
                              ? profile.customer.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 26,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.customer.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if ((profile.customer.phone ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                profile.customer.phone!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                    ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _StatChip(
                                label: 'Paid',
                                value: _invoiceMoney(profile.totalPaid),
                                color: const Color(0xFF16A34A),
                              ),
                              _StatChip(
                                label: 'Due',
                                value: _invoiceMoney(profile.totalDue),
                                color: Theme.of(context).colorScheme.error,
                              ),
                              _StatChip(
                                label: 'Invoices',
                                value: '${profile.invoices.length}',
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // ── Invoices section ──
              Text(
                'Invoices',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (profile.invoices.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'No invoices for this customer yet.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                )
              else
                ...profile.invoices.map((invoice) {
                  final scheme = Theme.of(context).colorScheme;
                  final statusColor =
                      _invoiceStatusColor(context, invoice.paymentStatus);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        Navigator.of(context).pushNamed(
                          AppRoutes.invoiceShow,
                          arguments: invoice.id,
                        );
                      },
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
                                Container(width: 4, color: statusColor),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 11,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                invoice.invoiceNumber,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                _invoiceDate(
                                                  invoice.createdAt,
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
                                        ),
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 9,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(
                                                  alpha: 0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                _invoiceStatusLabel(
                                                  invoice.paymentStatus,
                                                ),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: statusColor,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                            if (invoice.dueAmount > 0)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Text(
                                                  'Due ${_invoiceMoney(invoice.dueAmount)}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: scheme.error,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
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
                    ),
                  );
                }),
              const SizedBox(height: 12),
              // ── Payments section ──
              Text(
                'Payments',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (profile.payments.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'No follow-up payments recorded for this customer.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                )
              else
                ...profile.payments.map((payment) {
                  final scheme = Theme.of(context).colorScheme;
                  const stripColor = Color(0xFF16A34A);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
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
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: stripColor.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.payment_outlined,
                                        size: 18,
                                        color: stripColor,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          _invoiceMoney(payment.amount),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: stripColor,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_invoiceDate(payment.createdAt)}${payment.note == null ? '' : ' · ${payment.note}'}',
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

class _InvoiceSummaryRow extends StatelessWidget {
  const _InvoiceSummaryRow({
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

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
