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
                return Card(
                  child: ListTile(
                    title: Text(invoice.invoiceNumber),
                    subtitle: Text(
                      '${invoice.customerName ?? 'Walk-in customer'}${invoice.customerPhone == null ? '' : ' • ${invoice.customerPhone}'}\n${_invoiceDate(invoice.createdAt)} • Due ${_invoiceMoney(invoice.dueAmount)}',
                    ),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _invoiceMoney(invoice.total),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _invoiceStatusLabel(invoice.paymentStatus),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _invoiceStatusColor(
                                  context,
                                  invoice.paymentStatus,
                                ),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.invoiceShow, arguments: invoice.id);
                    },
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
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      title: Text(item.productName),
                      subtitle: Text(
                        '${_invoiceQty(product, item.quantity)} • ${_invoiceMoney(item.unitPrice)} each',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _invoiceMoney(item.total),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Profit ${_invoiceMoney(item.profit)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
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
  const CustomerListPage({super.key});

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

    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      body: controller.customers.isEmpty
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

                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(child: Text(avatarLabel)),
                                title: Text(customer.name),
                                subtitle: Text(
                                  '${customer.phone ?? 'No phone'} • $invoiceCount invoice${invoiceCount == 1 ? '' : 's'}',
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Due ${_invoiceMoney(totalDue)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: totalDue > 0
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.error
                                            : Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                      ),
                                    ),
                                    Text(
                                      'Paid ${_invoiceMoney(totalPaid)}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.of(context).pushNamed(
                                    AppRoutes.customerShow,
                                    arguments: customer.id,
                                  );
                                },
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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.customer.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Phone: ${profile.customer.phone ?? 'Not provided'}',
                      ),
                      Text('Total Paid: ${_invoiceMoney(profile.totalPaid)}'),
                      Text('Total Due: ${_invoiceMoney(profile.totalDue)}'),
                      Text('Invoices: ${profile.invoices.length}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Invoices',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (profile.invoices.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No invoices for this customer yet.'),
                  ),
                )
              else
                ...profile.invoices.map(
                  (invoice) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        title: Text(invoice.invoiceNumber),
                        subtitle: Text(_invoiceDate(invoice.createdAt)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _invoiceStatusLabel(invoice.paymentStatus),
                              style: TextStyle(
                                color: _invoiceStatusColor(
                                  context,
                                  invoice.paymentStatus,
                                ),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Due ${_invoiceMoney(invoice.dueAmount)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).pushNamed(
                            AppRoutes.invoiceShow,
                            arguments: invoice.id,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Payments',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (profile.payments.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No follow-up payments recorded for this customer.',
                    ),
                  ),
                )
              else
                ...profile.payments.map(
                  (payment) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
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
