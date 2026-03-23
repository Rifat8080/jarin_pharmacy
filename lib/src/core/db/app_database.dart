import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  static const Uuid _uuid = Uuid();
  static const String walkInCustomerId = 'customer-walkin-default';
  static const String walkInCustomerName = 'Walk-in customer';
  static const String _databaseName = 'jarin_pharmacy.db';
  static const int _databaseVersion = 10;

  Database? _database;
  Future<Database>? _openingDatabase;

  Future<void> initialize() async {
    await database;
  }

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    if (_openingDatabase != null) {
      return _openingDatabase!;
    }

    _openingDatabase = _openDatabase();
    _database = await _openingDatabase!;
    _openingDatabase = null;

    return _database!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createSchema(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _migrateLegacyIntegerKeysToUuid(db);
    }
    if (oldVersion < 3) {
      await _migrateProductPackPieceColumns(db);
    }
    if (oldVersion < 4) {
      await _migrateMedicineToPieceBasedSelling(db);
    }
    if (oldVersion < 5) {
      await _migrateInvoiceTables(db);
    }
    if (oldVersion < 6) {
      await _migrateInvoicePaymentColumns(db);
    }
    if (oldVersion < 7) {
      await _migrateCustomerDueTracking(db);
    }
    if (oldVersion < 8) {
      await _migrateRepairV7Schema(db);
    }
    if (oldVersion < 9) {
      await _migrateCustomerInvoiceProfiles(db);
    }
    if (oldVersion < 10) {
      await _migrateProductDgdaColumns(db);
    }
  }

  Future<void> _migrateProductDgdaColumns(Database db) async {
    await db
        .execute('ALTER TABLE products ADD COLUMN dgda_brand_id TEXT')
        .catchError((_) {});
    await db.execute('ALTER TABLE products ADD COLUMN dgda_type TEXT').catchError(
      (_) {},
    );
    await db.execute('ALTER TABLE products ADD COLUMN dgda_slug TEXT').catchError(
      (_) {},
    );
    await db
        .execute('ALTER TABLE products ADD COLUMN dgda_generic_name TEXT')
        .catchError((_) {});
    await db
        .execute('ALTER TABLE products ADD COLUMN dgda_strength TEXT')
        .catchError((_) {});
    await db
        .execute('ALTER TABLE products ADD COLUMN dgda_dosage_form TEXT')
        .catchError((_) {});
    await db
        .execute('ALTER TABLE products ADD COLUMN dgda_manufacturer TEXT')
        .catchError((_) {});
    await db
        .execute('ALTER TABLE products ADD COLUMN dgda_package_container TEXT')
        .catchError((_) {});
    await db
        .execute('ALTER TABLE products ADD COLUMN dgda_package_size TEXT')
        .catchError((_) {});
    await db
        .execute('ALTER TABLE products ADD COLUMN dgda_data_json TEXT')
        .catchError((_) {});
  }

  Future<void> _migrateCustomerInvoiceProfiles(Database db) async {
    await _migrateRepairV7Schema(db);

    await db.transaction((txn) async {
      await txn.insert('customers', {
        'id': walkInCustomerId,
        'name': walkInCustomerName,
        'phone': null,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      final invoiceRows = await txn.query(
        'invoices',
        columns: ['id', 'customer_id', 'customer_name', 'customer_phone'],
        where: 'customer_id IS NULL OR customer_id = ?',
        whereArgs: [''],
      );

      for (final row in invoiceRows) {
        final invoiceId = row['id'] as String;
        final customerName = (row['customer_name'] as String?)?.trim();
        final customerPhone = (row['customer_phone'] as String?)?.trim();
        final hasName = customerName != null && customerName.isNotEmpty;
        final hasPhone = customerPhone != null && customerPhone.isNotEmpty;

        String customerId = walkInCustomerId;

        if (hasName || hasPhone) {
          List<Map<String, Object?>> customerRows = const [];
          if (hasPhone) {
            customerRows = await txn.query(
              'customers',
              where: 'phone = ?',
              whereArgs: [customerPhone],
              limit: 1,
            );
          }

          if (customerRows.isEmpty && hasName) {
            customerRows = await txn.query(
              'customers',
              where: 'LOWER(name) = LOWER(?)',
              whereArgs: [customerName],
              limit: 1,
            );
          }

          if (customerRows.isNotEmpty) {
            customerId = customerRows.first['id'] as String;
            if (hasPhone) {
              await txn.update(
                'customers',
                {'phone': customerPhone},
                where: 'id = ?',
                whereArgs: [customerId],
              );
            }
          } else {
            customerId = _uuid.v4();
            await txn.insert('customers', {
              'id': customerId,
              'name': hasName ? customerName : customerPhone,
              'phone': hasPhone ? customerPhone : null,
              'created_at': DateTime.now().toIso8601String(),
            });
          }
        }

        await txn.update(
          'invoices',
          {'customer_id': customerId},
          where: 'id = ?',
          whereArgs: [invoiceId],
        );
      }
    });

    await _createIndexes(db);
  }

  Future<void> _migrateRepairV7Schema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_payments(
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        customer_id TEXT,
        amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        note TEXT,
        FOREIGN KEY(invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
        FOREIGN KEY(customer_id) REFERENCES customers(id) ON DELETE SET NULL
      )
    ''');

    await db
        .execute(
          'ALTER TABLE invoices ADD COLUMN customer_id TEXT REFERENCES customers(id)',
        )
        .catchError((_) {});
    await db
        .execute('ALTER TABLE invoices ADD COLUMN customer_phone TEXT')
        .catchError((_) {});
    await db
        .execute(
          'ALTER TABLE invoices ADD COLUMN amount_paid REAL NOT NULL DEFAULT 0',
        )
        .catchError((_) {});
    await db
        .execute(
          'ALTER TABLE invoices ADD COLUMN due_amount REAL NOT NULL DEFAULT 0',
        )
        .catchError((_) {});
    await db
        .execute(
          "ALTER TABLE invoices ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'paid'",
        )
        .catchError((_) {});

    await _createIndexes(db);
  }

  Future<void> _migrateCustomerDueTracking(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_payments(
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        customer_id TEXT,
        amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        note TEXT,
        FOREIGN KEY(invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
        FOREIGN KEY(customer_id) REFERENCES customers(id) ON DELETE SET NULL
      )
    ''');

    await db
        .execute(
          'ALTER TABLE invoices ADD COLUMN customer_id TEXT REFERENCES customers(id)',
        )
        .catchError((_) {});
    await db
        .execute('ALTER TABLE invoices ADD COLUMN customer_phone TEXT')
        .catchError((_) {});
    await db
        .execute(
          'ALTER TABLE invoices ADD COLUMN amount_paid REAL NOT NULL DEFAULT 0',
        )
        .catchError((_) {});
    await db
        .execute(
          'ALTER TABLE invoices ADD COLUMN due_amount REAL NOT NULL DEFAULT 0',
        )
        .catchError((_) {});
    await db
        .execute(
          "ALTER TABLE invoices ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'paid'",
        )
        .catchError((_) {});

    await db
        .execute('''
      UPDATE invoices
      SET amount_paid = MAX(cash_received - change_returned, 0),
          due_amount = MAX(total - MAX(cash_received - change_returned, 0), 0),
          payment_status = CASE
            WHEN MAX(total - MAX(cash_received - change_returned, 0), 0) <= 0 THEN 'paid'
            WHEN MAX(cash_received - change_returned, 0) <= 0 THEN 'due'
            ELSE 'partial'
          END
    ''')
        .catchError((_) {});

    await _createIndexes(db);
  }

  Future<void> _migrateInvoicePaymentColumns(Database db) async {
    await db
        .execute(
          'ALTER TABLE invoices ADD COLUMN cash_received REAL NOT NULL DEFAULT 0',
        )
        .catchError((_) {});
    await db
        .execute(
          'ALTER TABLE invoices ADD COLUMN change_returned REAL NOT NULL DEFAULT 0',
        )
        .catchError((_) {});
  }

  Future<void> _migrateInvoiceTables(Database db) async {
    await db
        .execute(
          'ALTER TABLE sales ADD COLUMN invoice_id TEXT REFERENCES invoices(id)',
        )
        .catchError((_) {});

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices(
        id TEXT PRIMARY KEY,
        invoice_number TEXT NOT NULL UNIQUE,
        customer_id TEXT,
        customer_name TEXT,
        customer_phone TEXT,
        note TEXT,
        total REAL NOT NULL,
        cost_total REAL NOT NULL,
        profit REAL NOT NULL,
        cash_received REAL NOT NULL DEFAULT 0,
        change_returned REAL NOT NULL DEFAULT 0,
        amount_paid REAL NOT NULL DEFAULT 0,
        due_amount REAL NOT NULL DEFAULT 0,
        payment_status TEXT NOT NULL DEFAULT 'paid',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_items(
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        total REAL NOT NULL,
        cost_total REAL NOT NULL,
        profit REAL NOT NULL,
        FOREIGN KEY(invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_payments(
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        customer_id TEXT,
        amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        note TEXT,
        FOREIGN KEY(invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
        FOREIGN KEY(customer_id) REFERENCES customers(id) ON DELETE SET NULL
      )
    ''');

    await _createIndexes(db);
  }

  Future<void> _migrateMedicineToPieceBasedSelling(Database db) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'products',
        where: 'category = ? AND track_in_pieces = 0',
        whereArgs: ['medicine'],
      );

      for (final row in rows) {
        final id = row['id'] as String;
        final unitsPerPack = (row['units_per_pack'] as num?)?.toInt() ?? 1;
        final buyPrice = (row['buy_price'] as num).toDouble();
        final sellPrice = (row['sell_price'] as num).toDouble();
        final stockQty = (row['stock_qty'] as num).toInt();

        if (unitsPerPack > 1) {
          await txn.update(
            'products',
            {
              'buy_price': buyPrice / unitsPerPack,
              'sell_price': sellPrice / unitsPerPack,
              'stock_qty': stockQty * unitsPerPack,
              'track_in_pieces': 1,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          await txn.update(
            'products',
            {'track_in_pieces': 1},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    });
  }

  Future<void> _migrateProductPackPieceColumns(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(products)');
    final existing = columns.map((row) => row['name'] as String).toSet();

    if (!existing.contains('units_per_pack')) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN units_per_pack INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (!existing.contains('track_in_pieces')) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN track_in_pieces INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> _migrateLegacyIntegerKeysToUuid(Database db) async {
    final tableNames = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final existingTables = tableNames
        .map((row) => row['name'] as String)
        .toSet();

    final hasLegacyProducts = existingTables.contains('products');
    if (!hasLegacyProducts) {
      await _createSchema(db);
      return;
    }

    final productColumns = await db.rawQuery('PRAGMA table_info(products)');
    final idColumn = productColumns.firstWhere(
      (column) => column['name'] == 'id',
      orElse: () => const {'type': 'TEXT'},
    );
    final idType = (idColumn['type'] as String? ?? '').toUpperCase();

    if (idType == 'TEXT') {
      return;
    }

    await db.transaction((txn) async {
      await txn.execute('ALTER TABLE products RENAME TO products_legacy');
      await txn.execute('ALTER TABLE purchases RENAME TO purchases_legacy');
      await txn.execute('ALTER TABLE sales RENAME TO sales_legacy');
      await txn.execute(
        'ALTER TABLE bkash_transactions RENAME TO bkash_transactions_legacy',
      );
      await txn.execute(
        'ALTER TABLE inventory_adjustments RENAME TO inventory_adjustments_legacy',
      );

      await _createSchema(txn);

      final legacyProducts = await txn.query('products_legacy');
      final productIdMap = <int, String>{};

      for (final row in legacyProducts) {
        final legacyId = row['id'] as int;
        final uuid = _uuid.v4();
        productIdMap[legacyId] = uuid;

        await txn.insert('products', {
          'id': uuid,
          'name': row['name'],
          'category': row['category'],
          'buy_price': row['buy_price'],
          'sell_price': row['sell_price'],
          'stock_qty': row['stock_qty'],
          'created_at': row['created_at'],
        });
      }

      final legacyPurchases = await txn.query('purchases_legacy');
      for (final row in legacyPurchases) {
        final mappedProductId = productIdMap[row['product_id'] as int];
        if (mappedProductId == null) {
          continue;
        }

        await txn.insert('purchases', {
          'id': _uuid.v4(),
          'product_id': mappedProductId,
          'quantity': row['quantity'],
          'unit_price': row['unit_price'],
          'total': row['total'],
          'created_at': row['created_at'],
          'note': row['note'],
        });
      }

      final legacySales = await txn.query('sales_legacy');
      for (final row in legacySales) {
        final mappedProductId = productIdMap[row['product_id'] as int];
        if (mappedProductId == null) {
          continue;
        }

        await txn.insert('sales', {
          'id': _uuid.v4(),
          'product_id': mappedProductId,
          'quantity': row['quantity'],
          'unit_price': row['unit_price'],
          'total': row['total'],
          'cost_total': row['cost_total'],
          'profit': row['profit'],
          'created_at': row['created_at'],
          'note': row['note'],
        });
      }

      final legacyBkashTransactions = await txn.query(
        'bkash_transactions_legacy',
      );
      for (final row in legacyBkashTransactions) {
        await txn.insert('bkash_transactions', {
          'id': _uuid.v4(),
          'type': row['type'],
          'amount': row['amount'],
          'charge': row['charge'],
          'net_amount': row['net_amount'],
          'created_at': row['created_at'],
          'note': row['note'],
        });
      }

      final legacyAdjustments = await txn.query('inventory_adjustments_legacy');
      for (final row in legacyAdjustments) {
        final mappedProductId = productIdMap[row['product_id'] as int];
        if (mappedProductId == null) {
          continue;
        }

        await txn.insert('inventory_adjustments', {
          'id': _uuid.v4(),
          'product_id': mappedProductId,
          'delta_qty': row['delta_qty'],
          'reason': row['reason'],
          'loss_value': row['loss_value'],
          'created_at': row['created_at'],
          'note': row['note'],
        });
      }

      await txn.execute('DROP TABLE products_legacy');
      await txn.execute('DROP TABLE purchases_legacy');
      await txn.execute('DROP TABLE sales_legacy');
      await txn.execute('DROP TABLE bkash_transactions_legacy');
      await txn.execute('DROP TABLE inventory_adjustments_legacy');
    });
  }

  Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        buy_price REAL NOT NULL,
        sell_price REAL NOT NULL,
        stock_qty INTEGER NOT NULL DEFAULT 0,
        units_per_pack INTEGER NOT NULL DEFAULT 1,
        track_in_pieces INTEGER NOT NULL DEFAULT 0,
        dgda_brand_id TEXT,
        dgda_type TEXT,
        dgda_slug TEXT,
        dgda_generic_name TEXT,
        dgda_strength TEXT,
        dgda_dosage_form TEXT,
        dgda_manufacturer TEXT,
        dgda_package_container TEXT,
        dgda_package_size TEXT,
        dgda_data_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases(
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        total REAL NOT NULL,
        created_at TEXT NOT NULL,
        note TEXT,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales(
        id TEXT PRIMARY KEY,
        invoice_id TEXT,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        total REAL NOT NULL,
        cost_total REAL NOT NULL,
        profit REAL NOT NULL,
        created_at TEXT NOT NULL,
        note TEXT,
        FOREIGN KEY(invoice_id) REFERENCES invoices(id),
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices(
        id TEXT PRIMARY KEY,
        invoice_number TEXT NOT NULL UNIQUE,
        customer_id TEXT,
        customer_name TEXT,
        customer_phone TEXT,
        note TEXT,
        total REAL NOT NULL,
        cost_total REAL NOT NULL,
        profit REAL NOT NULL,
        cash_received REAL NOT NULL DEFAULT 0,
        change_returned REAL NOT NULL DEFAULT 0,
        amount_paid REAL NOT NULL DEFAULT 0,
        due_amount REAL NOT NULL DEFAULT 0,
        payment_status TEXT NOT NULL DEFAULT 'paid',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_items(
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        total REAL NOT NULL,
        cost_total REAL NOT NULL,
        profit REAL NOT NULL,
        FOREIGN KEY(invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bkash_transactions(
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        charge REAL NOT NULL,
        net_amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        note TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_payments(
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        customer_id TEXT,
        amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        note TEXT,
        FOREIGN KEY(invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
        FOREIGN KEY(customer_id) REFERENCES customers(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_adjustments(
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        delta_qty INTEGER NOT NULL,
        reason TEXT NOT NULL,
        loss_value REAL NOT NULL,
        created_at TEXT NOT NULL,
        note TEXT,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    await _createIndexes(db);
  }

  Future<void> _createIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchases_product_created_at ON purchases(product_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_product_created_at ON sales(product_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_invoice_id ON sales(invoice_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bkash_created_at ON bkash_transactions(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_adjustments_product_created_at ON inventory_adjustments(product_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_created_at ON invoices(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice_id ON invoice_items(invoice_id)',
    );
    await db
        .execute(
          'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
        )
        .catchError((_) {});
    await db
        .execute(
          'CREATE INDEX IF NOT EXISTS idx_invoices_customer_id ON invoices(customer_id)',
        )
        .catchError((_) {});
    await db
        .execute(
          'CREATE INDEX IF NOT EXISTS idx_invoice_payments_invoice_id ON invoice_payments(invoice_id)',
        )
        .catchError((_) {});
    await db
        .execute(
          'CREATE INDEX IF NOT EXISTS idx_invoice_payments_customer_id ON invoice_payments(customer_id)',
        )
        .catchError((_) {});
  }
}
