import 'package:csv/csv.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class DgdaDatasetRepository {
  static const String medicineAssetPath = 'assets/data/medicine.csv';
  static const String genericAssetPath = 'assets/data/generic.csv';
  static const String manufacturerAssetPath = 'assets/data/manufacturer.csv';
  static const String dosageFormAssetPath = 'assets/data/dosage form.csv';
  static const String drugClassAssetPath = 'assets/data/drug class.csv';
  static const String indicationAssetPath = 'assets/data/indication.csv';
  static const String fallbackSingleAssetPath =
      'assets/data/dgda_medicines.csv';

  String _normalizeKey(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _normalizedValue(Map<String, String> row, List<String> aliases) {
    for (final alias in aliases) {
      final key = _normalizeKey(alias);
      final direct = row[key];
      if (direct != null && direct.trim().isNotEmpty) {
        return direct.trim();
      }
    }
    return '';
  }

  void _mergePrefixed(
    Map<String, String> target,
    String prefix,
    Map<String, String>? source,
  ) {
    if (source == null) {
      return;
    }

    source.forEach((key, value) {
      final normalizedKey = '${prefix}_${_normalizeKey(key)}';
      if (value.trim().isEmpty) {
        return;
      }
      target[normalizedKey] = value.trim();
    });
  }

  Future<List<Map<String, String>>> _parseCsvAsset(String assetPath) async {
    try {
      final csvText = await rootBundle.loadString(assetPath);
      final rows = const CsvToListConverter(
        shouldParseNumbers: false,
      ).convert(csvText);

      if (rows.isEmpty) {
        return const [];
      }

      final headers = rows.first
          .map((value) => _normalizeKey(value.toString()))
          .toList();
      final parsedRows = <Map<String, String>>[];

      for (final row in rows.skip(1)) {
        final map = <String, String>{};
        final totalColumns = row.length > headers.length
            ? row.length
            : headers.length;

        for (var index = 0; index < totalColumns; index++) {
          final header = index < headers.length
              ? headers[index]
              : 'extra_column_${index - headers.length + 1}';
          final value = index < row.length ? row[index].toString().trim() : '';
          map[header] = value;
        }

        parsedRows.add(map);
      }

      return parsedRows;
    } catch (_) {
      return const [];
    }
  }

  Map<String, Map<String, String>> _indexByName(
    List<Map<String, String>> rows,
    List<String> nameAliases,
  ) {
    final index = <String, Map<String, String>>{};
    for (final row in rows) {
      final name = _normalizedValue(row, nameAliases).toLowerCase();
      if (name.isEmpty) {
        continue;
      }
      index[name] = row;
    }
    return index;
  }

  Future<List<DgdaMedicine>> loadMedicines({String? assetPath}) async {
    final medicineRows = assetPath == null
        ? await _parseCsvAsset(medicineAssetPath)
        : await _parseCsvAsset(assetPath);

    if (medicineRows.isEmpty && assetPath == null) {
      final fallbackRows = await _parseCsvAsset(fallbackSingleAssetPath);
      return _buildFromSingleFile(fallbackRows);
    }

    final genericRows = await _parseCsvAsset(genericAssetPath);
    final manufacturerRows = await _parseCsvAsset(manufacturerAssetPath);
    final dosageRows = await _parseCsvAsset(dosageFormAssetPath);
    final drugClassRows = await _parseCsvAsset(drugClassAssetPath);
    final indicationRows = await _parseCsvAsset(indicationAssetPath);

    final genericByName = _indexByName(genericRows, [
      'generic_name',
      'generic',
      'name',
    ]);
    final manufacturerByName = _indexByName(manufacturerRows, [
      'manufacturer_name',
      'manufacturer',
      'name',
    ]);
    final dosageByName = _indexByName(dosageRows, [
      'dosage_form_name',
      'dosage_form',
      'dosage',
      'name',
    ]);
    final drugClassByName = _indexByName(drugClassRows, [
      'drug_class_name',
      'drug_class',
      'name',
    ]);
    final indicationByName = _indexByName(indicationRows, [
      'indication_name',
      'indication',
      'name',
    ]);

    final medicines = <DgdaMedicine>[];
    for (final medicineRow in medicineRows) {
      final brandName = _normalizedValue(medicineRow, [
        'brand_name',
        'brand',
        'trade_name',
        'name',
        'product_name',
      ]);
      if (brandName.isEmpty) {
        continue;
      }

      final genericName = _normalizedValue(medicineRow, [
        'generic_name',
        'generic',
      ]);
      final manufacturerName = _normalizedValue(medicineRow, [
        'manufacturer_name',
        'manufacturer',
      ]);
      final dosageFormName = _normalizedValue(medicineRow, [
        'dosage_form_name',
        'dosage_form',
        'dosage_forms',
        'dosage_form_name_',
        'dosage_form_',
        'dosage_forms_',
        'dosage_form',
        'dosage form',
      ]);

      final genericRow = genericByName[genericName.toLowerCase()];
      final manufacturerRow =
          manufacturerByName[manufacturerName.toLowerCase()];
      final dosageRow = dosageByName[dosageFormName.toLowerCase()];

      final drugClassName = _normalizedValue(genericRow ?? const {}, [
        'drug_class_name',
        'drug_class',
      ]);
      final indicationName = _normalizedValue(genericRow ?? const {}, [
        'indication_name',
        'indication',
      ]);

      final drugClassRow = drugClassByName[drugClassName.toLowerCase()];
      final indicationRow = indicationByName[indicationName.toLowerCase()];

      final allData = <String, String>{};
      _mergePrefixed(allData, 'medicine', medicineRow);
      _mergePrefixed(allData, 'generic', genericRow);
      _mergePrefixed(allData, 'manufacturer', manufacturerRow);
      _mergePrefixed(allData, 'dosage_form', dosageRow);
      _mergePrefixed(allData, 'drug_class', drugClassRow);
      _mergePrefixed(allData, 'indication', indicationRow);

      medicines.add(
        DgdaMedicine(
          brandId: _normalizedValue(medicineRow, ['brand_id', 'id']),
          brandName: brandName,
          type: _normalizedValue(medicineRow, ['type']),
          slug: _normalizedValue(medicineRow, ['slug']),
          genericName: genericName,
          strength: _normalizedValue(medicineRow, ['strength']),
          dosageForm: dosageFormName,
          manufacturer: manufacturerName,
          darNumber: _normalizedValue(medicineRow, [
            'dar',
            'dar_no',
            'dar_number',
          ]),
          packageContainer: _normalizedValue(medicineRow, [
            'package_container',
            'package',
            'pack',
          ]),
          packageSize: _normalizedValue(medicineRow, [
            'package_size',
            'pack_size',
          ]),
          drugClass: drugClassName,
          indication: indicationName,
          monographLink: _normalizedValue(genericRow ?? const {}, [
            'monograph_link',
            'link',
          ]),
          allData: allData,
        ),
      );
    }

    return medicines;
  }

  List<DgdaMedicine> _buildFromSingleFile(List<Map<String, String>> rows) {
    final medicines = <DgdaMedicine>[];
    for (final row in rows) {
      final brandName = _normalizedValue(row, [
        'brand_name',
        'brand',
        'trade_name',
        'name',
        'product_name',
      ]);

      if (brandName.isEmpty) {
        continue;
      }

      final allData = <String, String>{};
      _mergePrefixed(allData, 'medicine', row);

      medicines.add(
        DgdaMedicine(
          brandId: _normalizedValue(row, ['brand_id', 'id']),
          brandName: brandName,
          type: _normalizedValue(row, ['type']),
          slug: _normalizedValue(row, ['slug']),
          genericName: _normalizedValue(row, ['generic_name', 'generic']),
          strength: _normalizedValue(row, ['strength']),
          dosageForm: _normalizedValue(row, ['dosage_form', 'dosage', 'form']),
          manufacturer: _normalizedValue(row, [
            'manufacturer',
            'company',
            'company_name',
          ]),
          darNumber: _normalizedValue(row, ['dar', 'dar_no', 'dar_number']),
          packageContainer: _normalizedValue(row, [
            'package_container',
            'package',
            'pack',
          ]),
          packageSize: _normalizedValue(row, ['package_size', 'pack_size']),
          drugClass: _normalizedValue(row, ['drug_class', 'drug_class_name']),
          indication: _normalizedValue(row, ['indication', 'indication_name']),
          monographLink: _normalizedValue(row, ['monograph_link', 'link']),
          allData: allData,
        ),
      );
    }
    return medicines;
  }
}
