import '../core/db/app_database.dart';
import 'models.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class ProductRepository {
  ProductRepository(this._database);

  final AppDatabase _database;
  final Uuid _uuid = const Uuid();

  Future<List<Product>> getAllProducts() async {
    final db = await _database.database;
    final rows = await db.query('products', orderBy: 'name COLLATE NOCASE');
    return rows.map(Product.fromMap).toList();
  }

  Future<Product> createProduct(Product product) async {
    final db = await _database.database;
    final id = product.id ?? _uuid.v4();
    await db.insert('products', product.copyWith(id: id).toMap());
    return product.copyWith(id: id);
  }

  Future<void> updateProduct(Product product) async {
    final db = await _database.database;
    await db.update(
      'products',
      product.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<Product?> getById(String id) async {
    final db = await _database.database;
    final rows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Product.fromMap(rows.first);
  }

  Future<void> deleteProduct(String id) async {
    final db = await _database.database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> adjustStock({
    required String productId,
    required int deltaQty,
  }) async {
    final db = await _database.database;
    await db.rawUpdate(
      'UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?',
      [deltaQty, productId],
    );
  }

  Future<double> getStockValue() async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT SUM(stock_qty * buy_price) AS stock_value FROM products',
    );
    return (rows.first['stock_value'] as num?)?.toDouble() ?? 0;
  }
}

class TransactionRepository {
  TransactionRepository(this._database);

  final AppDatabase _database;
  final Uuid _uuid = const Uuid();
  static const String _walkInCustomerId = AppDatabase.walkInCustomerId;
  static const String _walkInCustomerName = AppDatabase.walkInCustomerName;

  Future<Purchase> createPurchase({
    required String productId,
    required int quantity,
    required double unitPrice,
    required DateTime date,
    String? note,
  }) async {
    final db = await _database.database;
    final id = _uuid.v4();
    final total = quantity * unitPrice;

    await db.transaction((txn) async {
      final product = await _getProduct(txn, productId);
      if (product == null) {
        throw StateError('Product not found.');
      }

      await txn.insert('purchases', {
        'id': id,
        'product_id': product.id,
        'quantity': quantity,
        'unit_price': unitPrice,
        'total': total,
        'created_at': date.toIso8601String(),
        'note': note,
      });

      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty + ?, buy_price = ? WHERE id = ?',
        [quantity, unitPrice, product.id],
      );
    });

    return Purchase(
      id: id,
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      total: total,
      createdAt: date,
      note: note,
    );
  }

  Future<void> updatePurchase({
    required String purchaseId,
    required String productId,
    required int quantity,
    required double unitPrice,
    DateTime? date,
    String? note,
  }) async {
    final db = await _database.database;

    await db.transaction((txn) async {
      final existing = await _getPurchase(txn, purchaseId);
      if (existing == null) {
        throw StateError('Purchase not found.');
      }

      final oldProduct = await _getProduct(txn, existing.productId);
      final newProduct = await _getProduct(txn, productId);
      if (oldProduct == null || newProduct == null) {
        throw StateError('Product not found.');
      }

      if (oldProduct.stockQty < existing.quantity) {
        throw StateError('Cannot update purchase; stock already consumed.');
      }

      final oldStockBase = oldProduct.stockQty - existing.quantity;
      if (productId == existing.productId) {
        final newStock = oldStockBase + quantity;
        if (newStock < 0) {
          throw StateError('Stock cannot go below zero.');
        }
      }

      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?',
        [existing.quantity, existing.productId],
      );

      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty + ?, buy_price = ? WHERE id = ?',
        [quantity, unitPrice, productId],
      );

      await txn.update(
        'purchases',
        {
          'product_id': productId,
          'quantity': quantity,
          'unit_price': unitPrice,
          'total': quantity * unitPrice,
          'created_at': (date ?? existing.createdAt).toIso8601String(),
          'note': note,
        },
        where: 'id = ?',
        whereArgs: [purchaseId],
      );
    });
  }

  Future<void> deletePurchase(String purchaseId) async {
    final db = await _database.database;

    await db.transaction((txn) async {
      final existing = await _getPurchase(txn, purchaseId);
      if (existing == null) {
        return;
      }

      final product = await _getProduct(txn, existing.productId);
      if (product == null) {
        return;
      }

      if (product.stockQty < existing.quantity) {
        throw StateError('Cannot delete purchase; stock already consumed.');
      }

      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?',
        [existing.quantity, existing.productId],
      );

      await txn.delete('purchases', where: 'id = ?', whereArgs: [purchaseId]);
    });
  }

  Future<Sale> createSale({
    required String productId,
    required int quantity,
    required double unitPrice,
    required DateTime date,
    String? note,
  }) async {
    final db = await _database.database;
    final id = _uuid.v4();
    final total = quantity * unitPrice;
    late double costTotal;
    late double profit;

    await db.transaction((txn) async {
      final product = await _getProduct(txn, productId);
      if (product == null) {
        throw StateError('Product not found.');
      }

      if (quantity > product.stockQty) {
        throw StateError('Not enough stock for ${product.name}.');
      }

      costTotal = quantity * product.buyPrice;
      profit = total - costTotal;

      await txn.insert('sales', {
        'id': id,
        'invoice_id': null,
        'product_id': product.id,
        'quantity': quantity,
        'unit_price': unitPrice,
        'total': total,
        'cost_total': costTotal,
        'profit': profit,
        'created_at': date.toIso8601String(),
        'note': note,
      });

      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?',
        [quantity, product.id],
      );
    });

    return Sale(
      id: id,
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      total: total,
      costTotal: costTotal,
      profit: profit,
      createdAt: date,
      note: note,
    );
  }

  Future<InvoiceDetails> createInvoice({
    required List<InvoiceLineInput> lines,
    required DateTime date,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? note,
    double? cashReceived,
    double? changeReturned,
  }) async {
    if (lines.isEmpty) {
      throw StateError('Invoice needs at least one item.');
    }

    final db = await _database.database;
    final invoiceId = _uuid.v4();
    late String invoiceNumber;
    late Invoice invoice;
    final items = <InvoiceItem>[];
    Customer? customer;

    await db.transaction((txn) async {
      invoiceNumber = await _nextInvoiceNumber(txn, date);
      var total = 0.0;
      var costTotal = 0.0;
      var profit = 0.0;
      final normalizedName = customerName?.trim();
      final normalizedPhone = customerPhone?.trim();
      final selectedCustomerId = customerId?.trim();
      String resolvedCustomerId;

      if (selectedCustomerId != null && selectedCustomerId.isNotEmpty) {
        final selected = await _getCustomer(txn, selectedCustomerId);
        if (selected == null) {
          throw StateError('Selected customer not found.');
        }
        customer = selected;
        resolvedCustomerId = selectedCustomerId;
      } else {
        resolvedCustomerId =
            await _upsertCustomer(
              txn,
              name: normalizedName,
              phone: normalizedPhone,
              createdAt: date,
            ) ??
            await _getOrCreateWalkInCustomer(txn, createdAt: date);
        customer = await _getCustomer(txn, resolvedCustomerId);
      }

      final invoiceCustomerName =
          (normalizedName != null && normalizedName.isNotEmpty)
          ? normalizedName
          : customer?.name;
      final invoiceCustomerPhone =
          (normalizedPhone != null && normalizedPhone.isNotEmpty)
          ? normalizedPhone
          : customer?.phone;

      await txn.insert('invoices', {
        'id': invoiceId,
        'invoice_number': invoiceNumber,
        'customer_id': resolvedCustomerId,
        'customer_name': invoiceCustomerName,
        'customer_phone': invoiceCustomerPhone,
        'note': note,
        'total': 0,
        'cost_total': 0,
        'profit': 0,
        'cash_received': 0,
        'change_returned': 0,
        'amount_paid': 0,
        'due_amount': 0,
        'payment_status': InvoicePaymentStatus.due.name,
        'created_at': date.toIso8601String(),
      });

      for (final line in lines) {
        final product = await _getProduct(txn, line.productId);
        if (product == null) {
          throw StateError('Product not found.');
        }
        if (line.quantity <= 0) {
          throw StateError('Invoice quantity must be positive.');
        }
        if (line.quantity > product.stockQty) {
          throw StateError('Not enough stock for ${product.name}.');
        }

        final lineTotal = line.quantity * line.unitPrice;
        final lineCostTotal = line.quantity * product.buyPrice;
        final lineProfit = lineTotal - lineCostTotal;
        final itemId = _uuid.v4();

        total += lineTotal;
        costTotal += lineCostTotal;
        profit += lineProfit;

        await txn.insert('invoice_items', {
          'id': itemId,
          'invoice_id': invoiceId,
          'product_id': product.id,
          'product_name': product.name,
          'quantity': line.quantity,
          'unit_price': line.unitPrice,
          'total': lineTotal,
          'cost_total': lineCostTotal,
          'profit': lineProfit,
        });

        final saleId = _uuid.v4();
        await txn.insert('sales', {
          'id': saleId,
          'invoice_id': invoiceId,
          'product_id': product.id,
          'quantity': line.quantity,
          'unit_price': line.unitPrice,
          'total': lineTotal,
          'cost_total': lineCostTotal,
          'profit': lineProfit,
          'created_at': date.toIso8601String(),
          'note': note,
        });

        await txn.rawUpdate(
          'UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?',
          [line.quantity, product.id],
        );

        items.add(
          InvoiceItem(
            id: itemId,
            invoiceId: invoiceId,
            productId: product.id!,
            productName: product.name,
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            total: lineTotal,
            costTotal: lineCostTotal,
            profit: lineProfit,
          ),
        );
      }

      final resolvedCashReceived = cashReceived ?? total;
      final resolvedChangeReturned =
          changeReturned ??
          (resolvedCashReceived > total ? resolvedCashReceived - total : 0);
      if (resolvedChangeReturned < 0) {
        throw StateError('Change returned cannot be negative.');
      }
      if (resolvedChangeReturned > resolvedCashReceived) {
        throw StateError('Change returned cannot exceed cash received.');
      }

      final amountPaid = resolvedCashReceived - resolvedChangeReturned;
      final dueAmount = total > amountPaid ? total - amountPaid : 0.0;
      final paymentStatus = _resolveInvoicePaymentStatus(
        total: total,
        amountPaid: amountPaid,
      );

      await txn.update(
        'invoices',
        {
          'total': total,
          'cost_total': costTotal,
          'profit': profit,
          'cash_received': resolvedCashReceived,
          'change_returned': resolvedChangeReturned,
          'amount_paid': amountPaid,
          'due_amount': dueAmount,
          'payment_status': paymentStatus.name,
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      invoice = Invoice(
        id: invoiceId,
        invoiceNumber: invoiceNumber,
        customerId: resolvedCustomerId,
        customerName: invoiceCustomerName,
        customerPhone: invoiceCustomerPhone,
        note: note,
        total: total,
        costTotal: costTotal,
        profit: profit,
        cashReceived: resolvedCashReceived,
        changeReturned: resolvedChangeReturned,
        amountPaid: amountPaid,
        dueAmount: dueAmount,
        paymentStatus: paymentStatus,
        createdAt: date,
      );
    });

    return InvoiceDetails(
      invoice: invoice,
      items: items,
      payments: const [],
      customer: customer,
    );
  }

  Future<List<Customer>> getCustomers({int limit = 100}) async {
    final db = await _database.database;
    final rows = await db.query(
      'customers',
      orderBy: 'name COLLATE NOCASE',
      limit: limit,
    );
    return rows.map(Customer.fromMap).toList();
  }

  Future<Map<String, CustomerDueSummary>> getCustomerDueSummaries() async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT
        customer_id,
        COUNT(*) AS invoice_count,
        COALESCE(SUM(due_amount), 0) AS total_due,
        COALESCE(SUM(amount_paid), 0) AS total_paid
      FROM invoices
      WHERE customer_id IS NOT NULL AND customer_id != ''
      GROUP BY customer_id
    ''');

    final summaries = <String, CustomerDueSummary>{};
    for (final row in rows) {
      final customerId = row['customer_id'] as String;
      summaries[customerId] = CustomerDueSummary(
        customerId: customerId,
        invoiceCount: (row['invoice_count'] as num?)?.toInt() ?? 0,
        totalDue: (row['total_due'] as num?)?.toDouble() ?? 0,
        totalPaid: (row['total_paid'] as num?)?.toDouble() ?? 0,
      );
    }

    return summaries;
  }

  Future<CustomerProfile?> getCustomerProfile(String customerId) async {
    final db = await _database.database;
    final customerRows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (customerRows.isEmpty) {
      return null;
    }

    final invoiceRows = await db.query(
      'invoices',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
    final paymentRows = await db.query(
      'invoice_payments',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );

    final invoices = invoiceRows.map(Invoice.fromMap).toList();
    final payments = paymentRows.map(InvoicePayment.fromMap).toList();

    return CustomerProfile(
      customer: Customer.fromMap(customerRows.first),
      invoices: invoices,
      payments: payments,
      totalDue: invoices.fold(0, (sum, invoice) => sum + invoice.dueAmount),
      totalPaid: invoices.fold(0, (sum, invoice) => sum + invoice.amountPaid),
    );
  }

  Future<InvoiceDetails> recordInvoicePayment({
    required String invoiceId,
    required double amount,
    String? note,
    DateTime? date,
  }) async {
    if (amount <= 0) {
      throw StateError('Payment amount must be greater than zero.');
    }

    final db = await _database.database;
    final paymentDate = date ?? DateTime.now();

    await db.transaction((txn) async {
      final invoice = await _getInvoice(txn, invoiceId);
      if (invoice == null) {
        throw StateError('Invoice not found.');
      }
      if (amount > invoice.dueAmount) {
        throw StateError('Payment cannot be greater than invoice due amount.');
      }

      await txn.insert('invoice_payments', {
        'id': _uuid.v4(),
        'invoice_id': invoiceId,
        'customer_id': invoice.customerId,
        'amount': amount,
        'created_at': paymentDate.toIso8601String(),
        'note': note,
      });

      final updatedAmountPaid = invoice.amountPaid + amount;
      final updatedDue = invoice.total > updatedAmountPaid
          ? invoice.total - updatedAmountPaid
          : 0.0;
      final status = _resolveInvoicePaymentStatus(
        total: invoice.total,
        amountPaid: updatedAmountPaid,
      );

      await txn.update(
        'invoices',
        {
          'amount_paid': updatedAmountPaid,
          'due_amount': updatedDue,
          'payment_status': status.name,
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
    });

    final details = await getInvoiceDetails(invoiceId);
    if (details == null) {
      throw StateError('Invoice not found after payment update.');
    }
    return details;
  }

  Future<void> updateSale({
    required String saleId,
    required String productId,
    required int quantity,
    required double unitPrice,
    DateTime? date,
    String? note,
  }) async {
    final db = await _database.database;

    await db.transaction((txn) async {
      final existing = await _getSale(txn, saleId);
      if (existing == null) {
        throw StateError('Sale not found.');
      }

      final oldProduct = await _getProduct(txn, existing.productId);
      final newProduct = await _getProduct(txn, productId);
      if (oldProduct == null || newProduct == null) {
        throw StateError('Product not found.');
      }

      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?',
        [existing.quantity, existing.productId],
      );

      final productAfterRevert = await _getProduct(txn, productId);
      if (productAfterRevert == null ||
          quantity > productAfterRevert.stockQty) {
        throw StateError('Not enough stock for updated sale.');
      }

      final total = quantity * unitPrice;
      final costTotal = quantity * productAfterRevert.buyPrice;
      final profit = total - costTotal;

      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?',
        [quantity, productId],
      );

      await txn.update(
        'sales',
        {
          'product_id': productId,
          'quantity': quantity,
          'unit_price': unitPrice,
          'total': total,
          'cost_total': costTotal,
          'profit': profit,
          'created_at': (date ?? existing.createdAt).toIso8601String(),
          'note': note,
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );
    });
  }

  Future<void> deleteSale(String saleId) async {
    final db = await _database.database;

    await db.transaction((txn) async {
      final existing = await _getSale(txn, saleId);
      if (existing == null) {
        return;
      }

      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?',
        [existing.quantity, existing.productId],
      );

      await txn.delete('sales', where: 'id = ?', whereArgs: [saleId]);
    });
  }

  Future<InventoryAdjustment> createInventoryAdjustment({
    required String productId,
    required int deltaQty,
    required String reason,
    required DateTime date,
    String? note,
  }) async {
    final db = await _database.database;
    final id = _uuid.v4();
    late double lossValue;

    await db.transaction((txn) async {
      final product = await _getProduct(txn, productId);
      if (product == null) {
        throw StateError('Product not found.');
      }

      if (product.stockQty + deltaQty < 0) {
        throw StateError('Stock cannot go below zero.');
      }

      lossValue = deltaQty < 0 ? deltaQty.abs() * product.buyPrice : 0.0;

      await txn.insert('inventory_adjustments', {
        'id': id,
        'product_id': product.id,
        'delta_qty': deltaQty,
        'reason': reason,
        'loss_value': lossValue,
        'created_at': date.toIso8601String(),
        'note': note,
      });

      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?',
        [deltaQty, product.id],
      );
    });

    return InventoryAdjustment(
      id: id,
      productId: productId,
      deltaQty: deltaQty,
      reason: reason,
      lossValue: lossValue,
      createdAt: date,
      note: note,
    );
  }

  Future<void> updateInventoryAdjustment({
    required String adjustmentId,
    required String productId,
    required int deltaQty,
    required String reason,
    DateTime? date,
    String? note,
  }) async {
    final db = await _database.database;

    await db.transaction((txn) async {
      final existing = await _getInventoryAdjustment(txn, adjustmentId);
      if (existing == null) {
        throw StateError('Adjustment not found.');
      }

      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?',
        [existing.deltaQty, existing.productId],
      );

      final targetProduct = await _getProduct(txn, productId);
      if (targetProduct == null) {
        throw StateError('Product not found.');
      }

      if (targetProduct.stockQty + deltaQty < 0) {
        throw StateError('Stock cannot go below zero.');
      }

      final lossValue = deltaQty < 0
          ? deltaQty.abs() * targetProduct.buyPrice
          : 0.0;

      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?',
        [deltaQty, productId],
      );

      await txn.update(
        'inventory_adjustments',
        {
          'product_id': productId,
          'delta_qty': deltaQty,
          'reason': reason,
          'loss_value': lossValue,
          'created_at': (date ?? existing.createdAt).toIso8601String(),
          'note': note,
        },
        where: 'id = ?',
        whereArgs: [adjustmentId],
      );
    });
  }

  Future<void> deleteInventoryAdjustment(String adjustmentId) async {
    final db = await _database.database;

    await db.transaction((txn) async {
      final existing = await _getInventoryAdjustment(txn, adjustmentId);
      if (existing == null) {
        return;
      }

      final product = await _getProduct(txn, existing.productId);
      if (product == null) {
        return;
      }

      if (product.stockQty - existing.deltaQty < 0) {
        throw StateError(
          'Cannot delete adjustment; stock would go below zero.',
        );
      }

      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?',
        [existing.deltaQty, existing.productId],
      );

      await txn.delete(
        'inventory_adjustments',
        where: 'id = ?',
        whereArgs: [adjustmentId],
      );
    });
  }

  Future<BkashTransaction> createBkash({
    required String accountId,
    required BkashType type,
    required double amount,
    required double charge,
    required DateTime date,
    String? note,
    String? toAccountId,
  }) async {
    final db = await _database.database;
    final id = _uuid.v4();

    final netAmount = switch (type) {
      BkashType.cashIn => amount,
      BkashType.cashOut => -amount,
      BkashType.sendMoney => -amount,
      BkashType.billPayment => -amount,
      BkashType.commission => 0.0,
      BkashType.transfer => -(amount + charge),
    };

    await db.transaction((txn) async {
      await _applyBkashAccountImpact(
        txn: txn,
        accountId: accountId,
        type: type,
        amount: amount,
        charge: charge,
        reverse: false,
      );

      // For transfers: credit the destination account.
      if (type == BkashType.transfer && toAccountId != null) {
        await txn.rawUpdate(
          'UPDATE bkash_accounts SET bkash_balance = bkash_balance + ? WHERE id = ?',
          [amount, toAccountId],
        );
      }

      await txn.insert('bkash_transactions', {
        'id': id,
        'account_id': accountId,
        'type': type.name,
        'amount': amount,
        'charge': charge,
        'net_amount': netAmount,
        'created_at': date.toIso8601String(),
        'note': note,
        'to_account_id': toAccountId,
      });
    });

    return BkashTransaction(
      id: id,
      accountId: accountId,
      type: type,
      amount: amount,
      charge: charge,
      netAmount: netAmount,
      createdAt: date,
      note: note,
      toAccountId: toAccountId,
    );
  }

  Future<void> updateBkash({
    required String bkashId,
    required String accountId,
    required BkashType type,
    required double amount,
    required double charge,
    DateTime? date,
    String? note,
    String? toAccountId,
  }) async {
    final db = await _database.database;
    final existing = await getBkashById(bkashId);
    if (existing == null) {
      throw StateError('bKash transaction not found.');
    }

    final netAmount = switch (type) {
      BkashType.cashIn => amount,
      BkashType.cashOut => -amount,
      BkashType.sendMoney => -amount,
      BkashType.billPayment => -amount,
      BkashType.commission => 0.0,
      BkashType.transfer => -(amount + charge),
    };

    await db.transaction((txn) async {
      // Reverse old impacts.
      await _applyBkashAccountImpact(
        txn: txn,
        accountId: existing.accountId,
        type: existing.type,
        amount: existing.amount,
        charge: existing.charge,
        reverse: true,
      );
      if (existing.type == BkashType.transfer &&
          existing.toAccountId != null) {
        await txn.rawUpdate(
          'UPDATE bkash_accounts SET bkash_balance = bkash_balance - ? WHERE id = ?',
          [existing.amount, existing.toAccountId],
        );
      }

      // Apply new impacts.
      await _applyBkashAccountImpact(
        txn: txn,
        accountId: accountId,
        type: type,
        amount: amount,
        charge: charge,
        reverse: false,
      );
      if (type == BkashType.transfer && toAccountId != null) {
        await txn.rawUpdate(
          'UPDATE bkash_accounts SET bkash_balance = bkash_balance + ? WHERE id = ?',
          [amount, toAccountId],
        );
      }

      await txn.update(
        'bkash_transactions',
        {
          'account_id': accountId,
          'type': type.name,
          'amount': amount,
          'charge': charge,
          'net_amount': netAmount,
          'created_at': (date ?? existing.createdAt).toIso8601String(),
          'note': note,
          'to_account_id': toAccountId,
        },
        where: 'id = ?',
        whereArgs: [bkashId],
      );
    });
  }

  Future<void> deleteBkash(String bkashId) async {
    final db = await _database.database;
    final existing = await getBkashById(bkashId);
    if (existing == null) {
      return;
    }

    await db.transaction((txn) async {
      await _applyBkashAccountImpact(
        txn: txn,
        accountId: existing.accountId,
        type: existing.type,
        amount: existing.amount,
        charge: existing.charge,
        reverse: true,
      );

      // For transfers: also reverse the destination credit.
      if (existing.type == BkashType.transfer &&
          existing.toAccountId != null) {
        await txn.rawUpdate(
          'UPDATE bkash_accounts SET bkash_balance = bkash_balance - ? WHERE id = ?',
          [existing.amount, existing.toAccountId],
        );
      }

      await txn.delete(
        'bkash_transactions',
        where: 'id = ?',
        whereArgs: [bkashId],
      );
    });
  }

  Future<BkashAccount> createBkashAccount({
    required String name,
    required double openingBkashBalance,
    required double openingCashBalance,
  }) async {
    final db = await _database.database;
    final id = _uuid.v4();
    final createdAt = DateTime.now();

    await db.insert('bkash_accounts', {
      'id': id,
      'name': name.trim(),
      'bkash_balance': openingBkashBalance,
      'cash_balance': openingCashBalance,
      'created_at': createdAt.toIso8601String(),
    });

    return BkashAccount(
      id: id,
      name: name.trim(),
      bkashBalance: openingBkashBalance,
      cashBalance: openingCashBalance,
      createdAt: createdAt,
    );
  }

  Future<List<BkashAccount>> getBkashAccounts() async {
    final db = await _database.database;
    final rows = await db.query(
      'bkash_accounts',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(BkashAccount.fromMap).toList();
  }

  Future<void> updateBkashAccount({
    required String accountId,
    required String name,
    required double bkashBalance,
    required double cashBalance,
  }) async {
    final db = await _database.database;
    await db.update(
      'bkash_accounts',
      {
        'name': name.trim(),
        'bkash_balance': bkashBalance,
        'cash_balance': cashBalance,
      },
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  Future<void> deleteBkashAccount(String accountId) async {
    final db = await _database.database;

    // Check if account has any transactions
    final transactions = await db.query(
      'bkash_transactions',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );

    if (transactions.isNotEmpty) {
      throw StateError(
        'Cannot delete account: it has ${transactions.length} transaction(s). Delete transactions first.',
      );
    }

    await db.delete('bkash_accounts', where: 'id = ?', whereArgs: [accountId]);
  }

  Future<Purchase?> getPurchaseById(String id) async {
    final db = await _database.database;
    final rows = await db.query(
      'purchases',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Purchase.fromMap(rows.first);
  }

  Future<Sale?> getSaleById(String id) async {
    final db = await _database.database;
    final rows = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Sale.fromMap(rows.first);
  }

  Future<InventoryAdjustment?> getInventoryAdjustmentById(String id) async {
    final db = await _database.database;
    final rows = await db.query(
      'inventory_adjustments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return InventoryAdjustment.fromMap(rows.first);
  }

  Future<BkashTransaction?> getBkashById(String id) async {
    final db = await _database.database;
    final rows = await db.query(
      'bkash_transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return BkashTransaction.fromMap(rows.first);
  }

  Future<void> _applyBkashAccountImpact({
    required Transaction txn,
    required String accountId,
    required BkashType type,
    required double amount,
    required double charge,
    required bool reverse,
  }) async {
    final multiplier = reverse ? -1.0 : 1.0;
    double deltaBkash = 0;
    double deltaCash = 0;

    switch (type) {
      case BkashType.cashIn:
        // Cash In: physical cash is deposited into the bKash wallet.
        // bKash balance increases; cash on hand decreases.
        deltaBkash = amount;
        deltaCash = -(amount + charge);
        break;
      case BkashType.sendMoney:
      case BkashType.billPayment:
        deltaBkash = -amount;
        deltaCash = amount + charge;
        break;
      case BkashType.cashOut:
        deltaBkash = -amount;
        deltaCash = amount + charge;
        break;
      case BkashType.commission:
        deltaBkash = 0;
        deltaCash = amount;
        break;
      case BkashType.transfer:
        // Source account: bKash decreases (amount + charge).
        // Destination account balance is updated separately.
        deltaBkash = -(amount + charge);
        deltaCash = 0;
        break;
    }

    await txn.rawUpdate(
      'UPDATE bkash_accounts SET bkash_balance = bkash_balance + ?, cash_balance = cash_balance + ? WHERE id = ?',
      [deltaBkash * multiplier, deltaCash * multiplier, accountId],
    );
  }

  Future<List<Purchase>> getPurchasesInRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await _database.database;
    final rows = await db.query(
      'purchases',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'created_at DESC',
    );
    return rows.map(Purchase.fromMap).toList();
  }

  Future<List<Sale>> getSalesInRange(DateTime start, DateTime end) async {
    final db = await _database.database;
    final rows = await db.query(
      'sales',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'created_at DESC',
    );
    return rows.map(Sale.fromMap).toList();
  }

  Future<List<Invoice>> getInvoices({int limit = 50}) async {
    final db = await _database.database;
    final rows = await db.query(
      'invoices',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Invoice.fromMap).toList();
  }

  Future<InvoiceDetails?> getInvoiceDetails(String invoiceId) async {
    final db = await _database.database;
    final invoiceRows = await db.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (invoiceRows.isEmpty) {
      return null;
    }

    final itemRows = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'rowid ASC',
    );
    final paymentRows = await db.query(
      'invoice_payments',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'created_at DESC',
    );

    final invoice = Invoice.fromMap(invoiceRows.first);
    Customer? customer;
    if (invoice.customerId != null) {
      customer = await getCustomerById(invoice.customerId!);
    }

    return InvoiceDetails(
      invoice: invoice,
      items: itemRows.map(InvoiceItem.fromMap).toList(),
      payments: paymentRows.map(InvoicePayment.fromMap).toList(),
      customer: customer,
    );
  }

  Future<Customer?> getCustomerById(String customerId) async {
    final db = await _database.database;
    final rows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Customer.fromMap(rows.first);
  }

  Future<List<BkashTransaction>> getBkashInRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await _database.database;
    final rows = await db.query(
      'bkash_transactions',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'created_at DESC',
    );
    return rows.map(BkashTransaction.fromMap).toList();
  }

  Future<BkashReportSummary?> getBkashDailyReport({
    required String accountId,
    required DateTime date,
  }) async {
    return _getBkashReportSummary(
      accountId: accountId,
      startDate: DateTime(date.year, date.month, date.day),
      endDate: DateTime(date.year, date.month, date.day + 1),
      period: 'Daily',
    );
  }

  Future<BkashReportSummary?> getBkashWeeklyReport({
    required String accountId,
    required DateTime date,
  }) async {
    final startOfWeek = date.subtract(Duration(days: date.weekday - 1));
    final startDate = DateTime(
      startOfWeek.year,
      startOfWeek.month,
      startOfWeek.day,
    );
    final endDate = startDate.add(const Duration(days: 7));

    return _getBkashReportSummary(
      accountId: accountId,
      startDate: startDate,
      endDate: endDate,
      period: 'Weekly',
    );
  }

  Future<BkashReportSummary?> getBkashMonthlyReport({
    required String accountId,
    required int year,
    required int month,
  }) async {
    final startDate = DateTime(year, month, 1);
    final endDate = month == 12
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);

    return _getBkashReportSummary(
      accountId: accountId,
      startDate: startDate,
      endDate: endDate,
      period: 'Monthly',
    );
  }

  Future<BkashReportSummary?> getBkashYearlyReport({
    required String accountId,
    required int year,
  }) async {
    final startDate = DateTime(year, 1, 1);
    final endDate = DateTime(year + 1, 1, 1);

    return _getBkashReportSummary(
      accountId: accountId,
      startDate: startDate,
      endDate: endDate,
      period: 'Yearly',
    );
  }

  Future<BkashReportSummary?> _getBkashReportSummary({
    required String accountId,
    required DateTime startDate,
    required DateTime endDate,
    required String period,
  }) async {
    final db = await _database.database;

    // Get account details
    final accountRows = await db.query(
      'bkash_accounts',
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );

    if (accountRows.isEmpty) {
      return null;
    }

    final account = BkashAccount.fromMap(accountRows.first);

    // Get opening balance (balance before the period starts)
    final beforePeriodTransactions = await db.query(
      'bkash_transactions',
      where: 'account_id = ? AND created_at < ?',
      whereArgs: [accountId, startDate.toIso8601String()],
    );

    double openingBkashBalance = account.bkashBalance;
    double openingCashBalance = account.cashBalance;

    // Also reverse any incoming transfers (where this is the destination).
    final incomingBeforePeriod = await db.query(
      'bkash_transactions',
      where: "to_account_id = ? AND created_at < ? AND type = 'transfer'",
      whereArgs: [accountId, startDate.toIso8601String()],
    );

    // Calculate opening balances by reversing all transactions before this period.
    for (final row in beforePeriodTransactions) {
      final txn = BkashTransaction.fromMap(row);
      switch (txn.type) {
        case BkashType.cashIn:
          openingBkashBalance -= txn.amount;
          openingCashBalance += (txn.amount + txn.charge); // reverse cash deduction
          break;
        case BkashType.cashOut:
        case BkashType.sendMoney:
        case BkashType.billPayment:
          openingBkashBalance += txn.amount;
          openingCashBalance -= (txn.amount + txn.charge);
          break;
        case BkashType.commission:
          openingCashBalance -= txn.amount;
          break;
        case BkashType.transfer:
          openingBkashBalance += (txn.amount + txn.charge);
          break;
      }
    }
    // Reverse incoming transfers credited to this account.
    for (final row in incomingBeforePeriod) {
      final txn = BkashTransaction.fromMap(row);
      openingBkashBalance -= txn.amount;
    }

    // Get transactions in the period
    final periodTransactions = await getBkashInRange(startDate, endDate);
    final accountTransactions = periodTransactions
        .where((txn) => txn.accountId == accountId)
        .toList();
    // Incoming transfers received in the period.
    final incomingInPeriod = periodTransactions
        .where(
          (txn) =>
              txn.toAccountId == accountId && txn.type == BkashType.transfer,
        )
        .toList();

    // Sum up transactions by type
    double totalCashIn = 0;
    double totalCashOut = 0;
    double totalSendMoney = 0;
    double totalBillPayment = 0;
    double totalCommission = 0;

    for (final txn in accountTransactions) {
      switch (txn.type) {
        case BkashType.cashIn:
          totalCashIn += txn.amount;
          break;
        case BkashType.cashOut:
          totalCashOut += txn.amount;
          break;
        case BkashType.sendMoney:
          totalSendMoney += txn.amount;
          break;
        case BkashType.billPayment:
          totalBillPayment += txn.amount;
          break;
        case BkashType.commission:
          totalCommission += txn.amount;
          break;
        case BkashType.transfer:
          break; // transfer is a bKash outflow; shown separately
      }
    }

    // Calculate closing balance
    double closingBkashBalance = openingBkashBalance;
    double closingCashBalance = openingCashBalance;

    for (final txn in accountTransactions) {
      switch (txn.type) {
        case BkashType.cashIn:
          closingBkashBalance += txn.amount;
          closingCashBalance -= (txn.amount + txn.charge);
          break;
        case BkashType.cashOut:
        case BkashType.sendMoney:
        case BkashType.billPayment:
          closingBkashBalance -= txn.amount;
          closingCashBalance += (txn.amount + txn.charge);
          break;
        case BkashType.commission:
          closingCashBalance += txn.amount;
          break;
        case BkashType.transfer:
          closingBkashBalance -= (txn.amount + txn.charge);
          break;
      }
    }
    // Apply incoming transfers received during this period.
    for (final txn in incomingInPeriod) {
      closingBkashBalance += txn.amount;
    }

    final netChange =
        (closingBkashBalance - openingBkashBalance) +
        (closingCashBalance - openingCashBalance);

    return BkashReportSummary(
      period: period,
      startDate: startDate,
      endDate: endDate,
      accountName: account.name,
      accountId: accountId,
      openingBkashBalance: openingBkashBalance,
      openingCashBalance: openingCashBalance,
      closingBkashBalance: closingBkashBalance,
      closingCashBalance: closingCashBalance,
      totalCashIn: totalCashIn,
      totalCashOut: totalCashOut,
      totalSendMoney: totalSendMoney,
      totalBillPayment: totalBillPayment,
      totalCommission: totalCommission,
      netChange: netChange,
    );
  }

  Future<List<BkashReportSummary>> getAllAccountsDailyReport({
    required DateTime date,
  }) async {
    final accounts = await getBkashAccounts();
    final reports = <BkashReportSummary>[];

    for (final account in accounts) {
      final report = await getBkashDailyReport(
        accountId: account.id,
        date: date,
      );
      if (report != null) {
        reports.add(report);
      }
    }

    return reports;
  }

  Future<List<BkashReportSummary>> getAllAccountsWeeklyReport({
    required DateTime date,
  }) async {
    final accounts = await getBkashAccounts();
    final reports = <BkashReportSummary>[];

    for (final account in accounts) {
      final report = await getBkashWeeklyReport(
        accountId: account.id,
        date: date,
      );
      if (report != null) {
        reports.add(report);
      }
    }

    return reports;
  }

  Future<List<BkashReportSummary>> getAllAccountsMonthlyReport({
    required int year,
    required int month,
  }) async {
    final accounts = await getBkashAccounts();
    final reports = <BkashReportSummary>[];

    for (final account in accounts) {
      final report = await getBkashMonthlyReport(
        accountId: account.id,
        year: year,
        month: month,
      );
      if (report != null) {
        reports.add(report);
      }
    }

    return reports;
  }

  Future<List<BkashReportSummary>> getAllAccountsYearlyReport({
    required int year,
  }) async {
    final accounts = await getBkashAccounts();
    final reports = <BkashReportSummary>[];

    for (final account in accounts) {
      final report = await getBkashYearlyReport(
        accountId: account.id,
        year: year,
      );
      if (report != null) {
        reports.add(report);
      }
    }

    return reports;
  }

  Future<List<BkashReportSummary>> getBkashDailyReportRange({
    required String accountId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final reports = <BkashReportSummary>[];
    var currentDate = DateTime(startDate.year, startDate.month, startDate.day);
    final lastDate = DateTime(endDate.year, endDate.month, endDate.day);

    while (currentDate.isBefore(lastDate) ||
        currentDate.isAtSameMomentAs(lastDate)) {
      final report = await getBkashDailyReport(
        accountId: accountId,
        date: currentDate,
      );
      if (report != null) {
        reports.add(report);
      }
      currentDate = currentDate.add(const Duration(days: 1));
    }

    return reports;
  }

  Future<List<BkashReportSummary>> getBkashMonthlyReportRange({
    required String accountId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final reports = <BkashReportSummary>[];
    var year = startDate.year;
    var month = startDate.month;

    while (year < endDate.year ||
        (year == endDate.year && month <= endDate.month)) {
      final report = await getBkashMonthlyReport(
        accountId: accountId,
        year: year,
        month: month,
      );
      if (report != null) {
        reports.add(report);
      }

      if (month == 12) {
        year++;
        month = 1;
      } else {
        month++;
      }
    }

    return reports;
  }

  Future<List<BkashReportSummary>> getBkashYearlyReportRange({
    required String accountId,
    required int startYear,
    required int endYear,
  }) async {
    final reports = <BkashReportSummary>[];

    for (var year = startYear; year <= endYear; year++) {
      final report = await getBkashYearlyReport(
        accountId: accountId,
        year: year,
      );
      if (report != null) {
        reports.add(report);
      }
    }

    return reports;
  }

  Future<List<BkashReportSummary>> getBkashWeeklyReportRange({
    required String accountId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final reports = <BkashReportSummary>[];
    var currentDate = startDate;

    while (currentDate.isBefore(endDate)) {
      final report = await getBkashWeeklyReport(
        accountId: accountId,
        date: currentDate,
      );
      if (report != null) {
        reports.add(report);
      }
      currentDate = currentDate.add(const Duration(days: 7));
    }

    return reports;
  }

  Future<List<BkashReportSummary>> getAllBkashDailyReportRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final reports = <BkashReportSummary>[];
    var currentDate = DateTime(startDate.year, startDate.month, startDate.day);
    final lastDate = DateTime(endDate.year, endDate.month, endDate.day);

    while (currentDate.isBefore(lastDate) ||
        currentDate.isAtSameMomentAs(lastDate)) {
      final dailyReports = await getAllAccountsDailyReport(date: currentDate);
      reports.addAll(dailyReports);
      currentDate = currentDate.add(const Duration(days: 1));
    }

    return reports;
  }

  Future<List<BkashReportSummary>> getAllBkashMonthlyReportRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final reports = <BkashReportSummary>[];
    var year = startDate.year;
    var month = startDate.month;

    while (year < endDate.year ||
        (year == endDate.year && month <= endDate.month)) {
      final monthlyReports = await getAllAccountsMonthlyReport(
        year: year,
        month: month,
      );
      reports.addAll(monthlyReports);

      if (month == 12) {
        year++;
        month = 1;
      } else {
        month++;
      }
    }

    return reports;
  }

  Future<List<InventoryAdjustment>> getInventoryAdjustmentsInRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await _database.database;
    final rows = await db.query(
      'inventory_adjustments',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'created_at DESC',
    );
    return rows.map(InventoryAdjustment.fromMap).toList();
  }

  Future<double> sumForRange({
    required String table,
    required String column,
    required DateTime start,
    required DateTime end,
    String? extraWhere,
    List<Object?>? extraArgs,
  }) async {
    final db = await _database.database;
    final where = StringBuffer('created_at >= ? AND created_at < ?');
    final args = <Object?>[start.toIso8601String(), end.toIso8601String()];

    if (extraWhere != null && extraWhere.isNotEmpty) {
      where.write(' AND $extraWhere');
      if (extraArgs != null) {
        args.addAll(extraArgs);
      }
    }

    final rows = await db.query(
      table,
      columns: ['SUM($column) as total'],
      where: where.toString(),
      whereArgs: args,
      limit: 1,
    );

    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<Product?> _getProduct(Transaction txn, String id) async {
    final rows = await txn.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Product.fromMap(rows.first);
  }

  Future<Invoice?> _getInvoice(Transaction txn, String id) async {
    final rows = await txn.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Invoice.fromMap(rows.first);
  }

  Future<Customer?> _getCustomer(Transaction txn, String id) async {
    final rows = await txn.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Customer.fromMap(rows.first);
  }

  Future<String?> _upsertCustomer(
    Transaction txn, {
    required String? name,
    required String? phone,
    required DateTime createdAt,
  }) async {
    final resolvedName = name?.trim();
    final resolvedPhone = phone?.trim();
    if ((resolvedName == null || resolvedName.isEmpty) &&
        (resolvedPhone == null || resolvedPhone.isEmpty)) {
      return null;
    }

    final byPhone = resolvedPhone == null || resolvedPhone.isEmpty
        ? const <Map<String, Object?>>[]
        : await txn.query(
            'customers',
            where: 'phone = ?',
            whereArgs: [resolvedPhone],
            limit: 1,
          );
    if (byPhone.isNotEmpty) {
      final existing = Customer.fromMap(byPhone.first);
      final updatedName = (resolvedName == null || resolvedName.isEmpty)
          ? existing.name
          : resolvedName;
      await txn.update(
        'customers',
        {'name': updatedName, 'phone': resolvedPhone},
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      return existing.id;
    }

    if (resolvedName != null && resolvedName.isNotEmpty) {
      final byName = await txn.query(
        'customers',
        where: 'LOWER(name) = LOWER(?)',
        whereArgs: [resolvedName],
        limit: 1,
      );
      if (byName.isNotEmpty) {
        final existing = Customer.fromMap(byName.first);
        if (resolvedPhone != null && resolvedPhone.isNotEmpty) {
          await txn.update(
            'customers',
            {'phone': resolvedPhone},
            where: 'id = ?',
            whereArgs: [existing.id],
          );
        }
        return existing.id;
      }
    }

    final customerId = _uuid.v4();
    await txn.insert('customers', {
      'id': customerId,
      'name': (resolvedName == null || resolvedName.isEmpty)
          ? resolvedPhone
          : resolvedName,
      'phone': resolvedPhone,
      'created_at': createdAt.toIso8601String(),
    });
    return customerId;
  }

  Future<String> _getOrCreateWalkInCustomer(
    Transaction txn, {
    required DateTime createdAt,
  }) async {
    final existing = await txn.query(
      'customers',
      where: 'id = ?',
      whereArgs: [_walkInCustomerId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return _walkInCustomerId;
    }

    await txn.insert('customers', {
      'id': _walkInCustomerId,
      'name': _walkInCustomerName,
      'phone': null,
      'created_at': createdAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return _walkInCustomerId;
  }

  InvoicePaymentStatus _resolveInvoicePaymentStatus({
    required double total,
    required double amountPaid,
  }) {
    if (amountPaid >= total) {
      return InvoicePaymentStatus.paid;
    }
    if (amountPaid <= 0) {
      return InvoicePaymentStatus.due;
    }
    return InvoicePaymentStatus.partial;
  }

  Future<Purchase?> _getPurchase(Transaction txn, String id) async {
    final rows = await txn.query(
      'purchases',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Purchase.fromMap(rows.first);
  }

  Future<Sale?> _getSale(Transaction txn, String id) async {
    final rows = await txn.query(
      'sales',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Sale.fromMap(rows.first);
  }

  Future<InventoryAdjustment?> _getInventoryAdjustment(
    Transaction txn,
    String id,
  ) async {
    final rows = await txn.query(
      'inventory_adjustments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return InventoryAdjustment.fromMap(rows.first);
  }

  Future<String> _nextInvoiceNumber(Transaction txn, DateTime date) async {
    final prefix = DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String().substring(0, 10).replaceAll('-', '');
    final rows = await txn.query(
      'invoices',
      columns: ['invoice_number'],
      where: 'invoice_number LIKE ?',
      whereArgs: ['INV-$prefix-%'],
      orderBy: 'invoice_number DESC',
      limit: 1,
    );
    final lastSequence = rows.isEmpty
        ? 0
        : int.tryParse(
                (rows.first['invoice_number'] as String).split('-').last,
              ) ??
              0;
    final nextSequence = (lastSequence + 1).toString().padLeft(3, '0');
    return 'INV-$prefix-$nextSequence';
  }
}
