import 'dart:typed_data';
import 'package:excel/excel.dart';

/// Represents a single packed quantity update parsed from the uploaded Excel.
class PackedUpdate {
  final String orderId;
  final String productName;
  final double packedQty;

  PackedUpdate({
    required this.orderId,
    required this.productName,
    required this.packedQty,
  });

  @override
  String toString() => 'PackedUpdate(order: ${orderId.substring(0, 8)}, product: $productName, qty: $packedQty)';
}

/// Result of parsing the uploaded Excel file.
class ImportResult {
  final List<PackedUpdate> updates;
  final int totalOrders;
  final int totalProducts;
  final List<String> warnings;

  ImportResult({
    required this.updates,
    required this.totalOrders,
    required this.totalProducts,
    this.warnings = const [],
  });
}

class ExcelImportService {
  /// Parses an uploaded Excel file and extracts packed quantity updates.
  ///
  /// Expected format (matches export):
  ///   Row 0 (header): Order ID | Customer Name | Product A | Product B | ...
  ///   Row 1+:         uuid     | name          | qty       | qty       | ...
  ///
  /// Returns an [ImportResult] with all parsed updates.
  static Future<ImportResult> parsePackingSheet(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);

    // Use the first sheet (regardless of name)
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;

    if (sheet.maxRows < 2) {
      throw Exception('Excel sheet is empty or has no data rows.');
    }

    // 1. Parse header row to get product names
    final headerRow = sheet.row(0);

    // Validate first two columns
    final col0 = _cellToString(headerRow[0]);
    final col1 = _cellToString(headerRow[1]);

    if (!col0.toLowerCase().contains('order') || !col1.toLowerCase().contains('customer')) {
      throw Exception(
        'Invalid sheet format. Expected "Order ID" in column A and "Customer Name" in column B.\n'
        'Got: "$col0" and "$col1".\n'
        'Please use the exported packing sheet format.'
      );
    }

    // Product names start from column index 2
    final productNames = <int, String>{};
    final ignoreColumns = {'order date', 'area', 'landmark', 'total amount', '#veg count', 'total weight (kg)'};
    
    for (var i = 2; i < headerRow.length; i++) {
      final name = _cellToString(headerRow[i]);
      if (name.isNotEmpty && !ignoreColumns.contains(name.toLowerCase())) {
        productNames[i] = name;
      }
    }

    if (productNames.isEmpty) {
      throw Exception('No product columns found in the header row.');
    }

    // 2. Parse data rows
    final updates = <PackedUpdate>[];
    final orderIds = <String>{};
    final warnings = <String>[];

    for (var rowIdx = 1; rowIdx < sheet.maxRows; rowIdx++) {
      final row = sheet.row(rowIdx);
      if (row.isEmpty) continue;

      // Column 0 = Order ID
      final orderId = _cellToString(row[0]).trim();
      if (orderId.isEmpty) {
        warnings.add('Row ${rowIdx + 1}: Skipped — no Order ID.');
        continue;
      }

      orderIds.add(orderId);

      // Columns 2+ = Product quantities (packed)
      for (final entry in productNames.entries) {
        final colIdx = entry.key;
        final productName = entry.value;

        if (colIdx >= row.length || row[colIdx] == null) continue;

        final qty = _cellToDouble(row[colIdx]);
        if (qty == null) {
          warnings.add('Row ${rowIdx + 1}, "$productName": Could not parse quantity, skipping.');
          continue;
        }

        // Only include non-zero quantities (0 means product not in this order)
        // Actually, include ALL values — 0 could mean admin intentionally set to 0
        updates.add(PackedUpdate(
          orderId: orderId,
          productName: productName,
          packedQty: qty,
        ));
      }
    }

    return ImportResult(
      updates: updates,
      totalOrders: orderIds.length,
      totalProducts: productNames.length,
      warnings: warnings,
    );
  }

  static String _cellToString(Data? cell) {
    if (cell == null || cell.value == null) return '';
    final value = cell.value;
    if (value is TextCellValue) return value.value.text ?? '';
    return value.toString();
  }

  static double? _cellToDouble(Data? cell) {
    if (cell == null || cell.value == null) return null;

    final value = cell.value;
    if (value is DoubleCellValue) return value.value;
    if (value is IntCellValue) return value.value.toDouble();
    if (value is TextCellValue) return double.tryParse(value.value.text ?? '');

    // Fallback: try parsing the string representation
    return double.tryParse(value.toString());
  }
}
