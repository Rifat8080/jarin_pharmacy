enum ProductCategory { medicine, stationery }

enum BkashType { cashIn, cashOut, commission }

enum ReportPeriod { day, month, year }

enum InvoicePaymentStatus { paid, partial, due }

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.buyPrice,
    required this.sellPrice,
    required this.stockQty,
    required this.unitsPerPack,
    required this.trackInPieces,
    required this.createdAt,
  });

  final String? id;
  final String name;
  final ProductCategory category;
  final double buyPrice;
  final double sellPrice;
  final int stockQty;
  final int unitsPerPack;
  final bool trackInPieces;
  final DateTime createdAt;

  Product copyWith({
    String? id,
    String? name,
    ProductCategory? category,
    double? buyPrice,
    double? sellPrice,
    int? stockQty,
    int? unitsPerPack,
    bool? trackInPieces,
    DateTime? createdAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      buyPrice: buyPrice ?? this.buyPrice,
      sellPrice: sellPrice ?? this.sellPrice,
      stockQty: stockQty ?? this.stockQty,
      unitsPerPack: unitsPerPack ?? this.unitsPerPack,
      trackInPieces: trackInPieces ?? this.trackInPieces,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category.name,
      'buy_price': buyPrice,
      'sell_price': sellPrice,
      'stock_qty': stockQty,
      'units_per_pack': unitsPerPack,
      'track_in_pieces': trackInPieces ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, Object?> map) {
    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      category: ProductCategory.values.byName(map['category'] as String),
      buyPrice: (map['buy_price'] as num).toDouble(),
      sellPrice: (map['sell_price'] as num).toDouble(),
      stockQty: map['stock_qty'] as int,
      unitsPerPack: (map['units_per_pack'] as num?)?.toInt() ?? 1,
      trackInPieces: ((map['track_in_pieces'] as num?)?.toInt() ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class Purchase {
  const Purchase({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    required this.createdAt,
    required this.note,
  });

  final String? id;
  final String productId;
  final int quantity;
  final double unitPrice;
  final double total;
  final DateTime createdAt;
  final String? note;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total': total,
      'created_at': createdAt.toIso8601String(),
      'note': note,
    };
  }

  factory Purchase.fromMap(Map<String, Object?> map) {
    return Purchase(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      quantity: map['quantity'] as int,
      unitPrice: (map['unit_price'] as num).toDouble(),
      total: (map['total'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      note: map['note'] as String?,
    );
  }
}

class Sale {
  const Sale({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    required this.costTotal,
    required this.profit,
    required this.createdAt,
    required this.note,
  });

  final String? id;
  final String productId;
  final int quantity;
  final double unitPrice;
  final double total;
  final double costTotal;
  final double profit;
  final DateTime createdAt;
  final String? note;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total': total,
      'cost_total': costTotal,
      'profit': profit,
      'created_at': createdAt.toIso8601String(),
      'note': note,
    };
  }

  factory Sale.fromMap(Map<String, Object?> map) {
    return Sale(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      quantity: map['quantity'] as int,
      unitPrice: (map['unit_price'] as num).toDouble(),
      total: (map['total'] as num).toDouble(),
      costTotal: (map['cost_total'] as num).toDouble(),
      profit: (map['profit'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      note: map['note'] as String?,
    );
  }
}

class Invoice {
  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.note,
    required this.total,
    required this.costTotal,
    required this.profit,
    required this.cashReceived,
    required this.changeReturned,
    required this.amountPaid,
    required this.dueAmount,
    required this.paymentStatus,
    required this.createdAt,
  });

  final String? id;
  final String invoiceNumber;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? note;
  final double total;
  final double costTotal;
  final double profit;
  final double cashReceived;
  final double changeReturned;
  final double amountPaid;
  final double dueAmount;
  final InvoicePaymentStatus paymentStatus;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'invoice_number': invoiceNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'note': note,
      'total': total,
      'cost_total': costTotal,
      'profit': profit,
      'cash_received': cashReceived,
      'change_returned': changeReturned,
      'amount_paid': amountPaid,
      'due_amount': dueAmount,
      'payment_status': paymentStatus.name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Invoice.fromMap(Map<String, Object?> map) {
    return Invoice(
      id: map['id'] as String,
      invoiceNumber: map['invoice_number'] as String,
      customerId: map['customer_id'] as String?,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
      note: map['note'] as String?,
      total: (map['total'] as num).toDouble(),
      costTotal: (map['cost_total'] as num).toDouble(),
      profit: (map['profit'] as num).toDouble(),
      cashReceived: (map['cash_received'] as num?)?.toDouble() ?? 0,
      changeReturned: (map['change_returned'] as num?)?.toDouble() ?? 0,
      amountPaid: (map['amount_paid'] as num?)?.toDouble() ?? 0,
      dueAmount: (map['due_amount'] as num?)?.toDouble() ?? 0,
      paymentStatus: InvoicePaymentStatus.values.byName(
        (map['payment_status'] as String?) ?? InvoicePaymentStatus.paid.name,
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.createdAt,
  });

  final String? id;
  final String name;
  final String? phone;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Customer.fromMap(Map<String, Object?> map) {
    return Customer(
      id: map['id'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class InvoicePayment {
  const InvoicePayment({
    required this.id,
    required this.invoiceId,
    required this.customerId,
    required this.amount,
    required this.createdAt,
    required this.note,
  });

  final String? id;
  final String invoiceId;
  final String? customerId;
  final double amount;
  final DateTime createdAt;
  final String? note;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'customer_id': customerId,
      'amount': amount,
      'created_at': createdAt.toIso8601String(),
      'note': note,
    };
  }

  factory InvoicePayment.fromMap(Map<String, Object?> map) {
    return InvoicePayment(
      id: map['id'] as String,
      invoiceId: map['invoice_id'] as String,
      customerId: map['customer_id'] as String?,
      amount: (map['amount'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      note: map['note'] as String?,
    );
  }
}

class InvoiceItem {
  const InvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    required this.costTotal,
    required this.profit,
  });

  final String? id;
  final String invoiceId;
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double total;
  final double costTotal;
  final double profit;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total': total,
      'cost_total': costTotal,
      'profit': profit,
    };
  }

  factory InvoiceItem.fromMap(Map<String, Object?> map) {
    return InvoiceItem(
      id: map['id'] as String,
      invoiceId: map['invoice_id'] as String,
      productId: map['product_id'] as String,
      productName: map['product_name'] as String,
      quantity: map['quantity'] as int,
      unitPrice: (map['unit_price'] as num).toDouble(),
      total: (map['total'] as num).toDouble(),
      costTotal: (map['cost_total'] as num).toDouble(),
      profit: (map['profit'] as num).toDouble(),
    );
  }
}

class InvoiceDetails {
  const InvoiceDetails({
    required this.invoice,
    required this.items,
    required this.payments,
    required this.customer,
  });

  final Invoice invoice;
  final List<InvoiceItem> items;
  final List<InvoicePayment> payments;
  final Customer? customer;
}

class InvoiceLineInput {
  const InvoiceLineInput({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
  });

  final String productId;
  final int quantity;
  final double unitPrice;
}

class CustomerProfile {
  const CustomerProfile({
    required this.customer,
    required this.invoices,
    required this.payments,
    required this.totalDue,
    required this.totalPaid,
  });

  final Customer customer;
  final List<Invoice> invoices;
  final List<InvoicePayment> payments;
  final double totalDue;
  final double totalPaid;
}

class CustomerDueSummary {
  const CustomerDueSummary({
    required this.customerId,
    required this.invoiceCount,
    required this.totalDue,
    required this.totalPaid,
  });

  final String customerId;
  final int invoiceCount;
  final double totalDue;
  final double totalPaid;
}

class BkashTransaction {
  const BkashTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.charge,
    required this.netAmount,
    required this.createdAt,
    required this.note,
  });

  final String? id;
  final BkashType type;
  final double amount;
  final double charge;
  final double netAmount;
  final DateTime createdAt;
  final String? note;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'type': type.name,
      'amount': amount,
      'charge': charge,
      'net_amount': netAmount,
      'created_at': createdAt.toIso8601String(),
      'note': note,
    };
  }

  factory BkashTransaction.fromMap(Map<String, Object?> map) {
    return BkashTransaction(
      id: map['id'] as String,
      type: BkashType.values.byName(map['type'] as String),
      amount: (map['amount'] as num).toDouble(),
      charge: (map['charge'] as num).toDouble(),
      netAmount: (map['net_amount'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      note: map['note'] as String?,
    );
  }
}

class InventoryAdjustment {
  const InventoryAdjustment({
    required this.id,
    required this.productId,
    required this.deltaQty,
    required this.reason,
    required this.lossValue,
    required this.createdAt,
    required this.note,
  });

  final String? id;
  final String productId;
  final int deltaQty;
  final String reason;
  final double lossValue;
  final DateTime createdAt;
  final String? note;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'delta_qty': deltaQty,
      'reason': reason,
      'loss_value': lossValue,
      'created_at': createdAt.toIso8601String(),
      'note': note,
    };
  }

  factory InventoryAdjustment.fromMap(Map<String, Object?> map) {
    return InventoryAdjustment(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      deltaQty: map['delta_qty'] as int,
      reason: map['reason'] as String,
      lossValue: (map['loss_value'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      note: map['note'] as String?,
    );
  }
}

class ReportWindow {
  const ReportWindow({
    required this.start,
    required this.end,
    required this.label,
  });

  final DateTime start;
  final DateTime end;
  final String label;
}

class DashboardReport {
  const DashboardReport({
    required this.salesBilling,
    required this.purchaseBilling,
    required this.grossProfit,
    required this.dueAmount,
    required this.inventoryLoss,
    required this.netProfit,
    required this.bkashIn,
    required this.bkashOut,
    required this.bkashCommission,
    required this.stockValue,
  });

  final double salesBilling;
  final double purchaseBilling;
  final double grossProfit;
  final double dueAmount;
  final double inventoryLoss;
  final double netProfit;
  final double bkashIn;
  final double bkashOut;
  final double bkashCommission;
  final double stockValue;
}
