import 'package:flutter/foundation.dart';

import '../core/db/app_database.dart';
import '../domain/models.dart';
import '../domain/reporting.dart';
import '../domain/repositories.dart';

class PharmacyAppController extends ChangeNotifier {
  PharmacyAppController({
    ProductRepository? productRepository,
    TransactionRepository? transactionRepository,
    ReportingService? reportingService,
  }) : _products = productRepository ?? ProductRepository(AppDatabase.instance),
       _transactions =
           transactionRepository ?? TransactionRepository(AppDatabase.instance),
       _reporting =
           reportingService ??
           ReportingService(
             transactions:
                 transactionRepository ??
                 TransactionRepository(AppDatabase.instance),
             products:
                 productRepository ?? ProductRepository(AppDatabase.instance),
           );

  final ProductRepository _products;
  final TransactionRepository _transactions;
  final ReportingService _reporting;

  bool isLoading = false;
  String? errorMessage;

  List<Product> products = const [];
  List<Purchase> purchases = const [];
  List<Sale> sales = const [];
  List<Invoice> invoices = const [];
  List<Customer> customers = const [];
  Map<String, CustomerDueSummary> customerDueSummaries = const {};
  List<BkashTransaction> bkashTransactions = const [];
  List<InventoryAdjustment> adjustments = const [];

  ReportPeriod reportPeriod = ReportPeriod.day;
  DateTime reportAnchorDate = DateTime.now();
  ReportWindow? reportWindow;
  DashboardReport? dashboardReport;

  Future<void> initialize() async {
    await refreshAll();
  }

  Future<void> refreshAll() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      products = await _products.getAllProducts();
      invoices = await _transactions.getInvoices();
      customers = await _transactions.getCustomers();
      customerDueSummaries = await _transactions.getCustomerDueSummaries();
      reportWindow = _reporting.buildWindow(
        period: reportPeriod,
        anchor: reportAnchorDate,
      );

      if (reportWindow != null) {
        purchases = await _transactions.getPurchasesInRange(
          reportWindow!.start,
          reportWindow!.end,
        );
        sales = await _transactions.getSalesInRange(
          reportWindow!.start,
          reportWindow!.end,
        );
        bkashTransactions = await _transactions.getBkashInRange(
          reportWindow!.start,
          reportWindow!.end,
        );
        adjustments = await _transactions.getInventoryAdjustmentsInRange(
          reportWindow!.start,
          reportWindow!.end,
        );
      }

      dashboardReport = await _reporting.buildReport(
        period: reportPeriod,
        anchor: reportAnchorDate,
      );
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setReportPeriod(ReportPeriod period) async {
    reportPeriod = period;
    await refreshAll();
  }

  Future<void> setReportAnchorDate(DateTime date) async {
    reportAnchorDate = date;
    await refreshAll();
  }

  Future<void> addProduct({
    required String name,
    required ProductCategory category,
    required double buyPrice,
    required double sellPrice,
    required int openingStock,
    int unitsPerPack = 1,
    bool trackInPieces = false,
  }) async {
    final isMedicine = category == ProductCategory.medicine;
    await _products.createProduct(
      Product(
        id: null,
        name: name.trim(),
        category: category,
        buyPrice: buyPrice,
        sellPrice: sellPrice,
        stockQty: openingStock,
        unitsPerPack: isMedicine ? unitsPerPack : 1,
        trackInPieces: isMedicine ? true : false,
        createdAt: DateTime.now(),
      ),
    );
    await refreshAll();
  }

  Future<void> updateProduct({
    required String productId,
    required String name,
    required ProductCategory category,
    required double buyPrice,
    required double sellPrice,
    required int stockQty,
    int unitsPerPack = 1,
    bool trackInPieces = false,
  }) async {
    final isMedicine = category == ProductCategory.medicine;
    final existing = products.firstWhere((item) => item.id == productId);
    await _products.updateProduct(
      existing.copyWith(
        name: name.trim(),
        category: category,
        buyPrice: buyPrice,
        sellPrice: sellPrice,
        stockQty: stockQty,
        unitsPerPack: isMedicine ? unitsPerPack : 1,
        trackInPieces: isMedicine ? true : false,
      ),
    );
    await refreshAll();
  }

  Future<void> deleteProduct(String productId) async {
    await _products.deleteProduct(productId);
    await refreshAll();
  }

  Future<void> recordPurchase({
    required String productId,
    required int quantity,
    required double unitPrice,
    String? note,
  }) async {
    await _transactions.createPurchase(
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      date: DateTime.now(),
      note: note,
    );
    await refreshAll();
  }

  Future<void> updatePurchase({
    required String purchaseId,
    required String productId,
    required int quantity,
    required double unitPrice,
    String? note,
  }) async {
    await _transactions.updatePurchase(
      purchaseId: purchaseId,
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      note: note,
    );
    await refreshAll();
  }

  Future<void> deletePurchase(String purchaseId) async {
    await _transactions.deletePurchase(purchaseId);
    await refreshAll();
  }

  Future<List<Purchase>> getPurchasesInRange(
    DateTime start,
    DateTime end,
  ) async {
    return _transactions.getPurchasesInRange(start, end);
  }

  Future<void> recordSale({
    required String productId,
    required int quantity,
    required double unitPrice,
    String? note,
  }) async {
    await _transactions.createSale(
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      date: DateTime.now(),
      note: note,
    );
    await refreshAll();
  }

  Future<InvoiceDetails> createInvoice({
    required List<InvoiceLineInput> lines,
    String? selectedCustomerId,
    String? customerName,
    String? customerPhone,
    String? note,
    double? cashReceived,
    double? changeReturned,
  }) async {
    final result = await _transactions.createInvoice(
      lines: lines,
      date: DateTime.now(),
      customerId: selectedCustomerId,
      customerName: customerName,
      customerPhone: customerPhone,
      note: note,
      cashReceived: cashReceived,
      changeReturned: changeReturned,
    );
    await refreshAll();
    return result;
  }

  Future<InvoiceDetails?> getInvoiceDetails(String invoiceId) async {
    return _transactions.getInvoiceDetails(invoiceId);
  }

  Future<CustomerProfile?> getCustomerProfile(String customerId) async {
    return _transactions.getCustomerProfile(customerId);
  }

  Future<InvoiceDetails> recordInvoicePayment({
    required String invoiceId,
    required double amount,
    String? note,
  }) async {
    final result = await _transactions.recordInvoicePayment(
      invoiceId: invoiceId,
      amount: amount,
      note: note,
    );
    await refreshAll();
    return result;
  }

  Future<void> updateSale({
    required String saleId,
    required String productId,
    required int quantity,
    required double unitPrice,
    String? note,
  }) async {
    await _transactions.updateSale(
      saleId: saleId,
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      note: note,
    );
    await refreshAll();
  }

  Future<void> deleteSale(String saleId) async {
    await _transactions.deleteSale(saleId);
    await refreshAll();
  }

  Future<void> recordInventoryAdjustment({
    required String productId,
    required int deltaQty,
    required String reason,
    String? note,
  }) async {
    await _transactions.createInventoryAdjustment(
      productId: productId,
      deltaQty: deltaQty,
      reason: reason,
      date: DateTime.now(),
      note: note,
    );
    await refreshAll();
  }

  Future<void> updateInventoryAdjustment({
    required String adjustmentId,
    required String productId,
    required int deltaQty,
    required String reason,
    String? note,
  }) async {
    await _transactions.updateInventoryAdjustment(
      adjustmentId: adjustmentId,
      productId: productId,
      deltaQty: deltaQty,
      reason: reason,
      note: note,
    );
    await refreshAll();
  }

  Future<void> deleteInventoryAdjustment(String adjustmentId) async {
    await _transactions.deleteInventoryAdjustment(adjustmentId);
    await refreshAll();
  }

  Future<List<InventoryAdjustment>> getInventoryAdjustmentsInRange(
    DateTime start,
    DateTime end,
  ) async {
    return _transactions.getInventoryAdjustmentsInRange(start, end);
  }

  Future<void> recordBkash({
    required BkashType type,
    required double amount,
    required double charge,
    String? note,
  }) async {
    await _transactions.createBkash(
      type: type,
      amount: amount,
      charge: charge,
      date: DateTime.now(),
      note: note,
    );
    await refreshAll();
  }

  Future<void> updateBkash({
    required String bkashId,
    required BkashType type,
    required double amount,
    required double charge,
    String? note,
  }) async {
    await _transactions.updateBkash(
      bkashId: bkashId,
      type: type,
      amount: amount,
      charge: charge,
      note: note,
    );
    await refreshAll();
  }

  Future<void> deleteBkash(String bkashId) async {
    await _transactions.deleteBkash(bkashId);
    await refreshAll();
  }
}
