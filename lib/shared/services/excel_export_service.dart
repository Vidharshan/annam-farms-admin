import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../shared/domain/order_model.dart';

class ExcelExportService {
  /// Exports a delivery summary sheet for all given orders.
  /// Format: Area | User Name | #Veg Count | Total Weight (kg)
  /// Only veggies whose unit is 'kg' are included in the weight sum.
  /// Unit-based veggies (pieces, bunches, etc.) are skipped for weight.
  static Future<void> exportPackingSheet(List<Order> orders) async {
    final excel = Excel.createExcel();
    final sheet = excel['Delivery Summary'];

    // Remove the default 'Sheet1'
    excel.delete('Sheet1');

    // Collect all unique product names across all orders
    final allProductsSet = <String>{};
    for (final o in orders) {
      for (final item in o.items) {
        allProductsSet.add(item.productName);
      }
    }
    final allProducts = allProductsSet.toList()..sort();

    // 1. Build Header Row
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#4CAF50'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
    );

    final metadataHeaders = [
      'Order ID',
      'Customer Name',
      'Order Date',
      'Area',
      'Landmark',
      'Total Amount',
      '#Veg Count',
      'Total Weight (kg)'
    ];

    final headers = [...metadataHeaders, ...allProducts];
    for (var i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        ..value = TextCellValue(headers[i])
        ..cellStyle = headerStyle;
    }

    // 2. Sort orders by area (alphabetically), then by customer name
    final sortedOrders = List<Order>.from(orders);
    sortedOrders.sort((a, b) {
      final areaCompare = (a.customerArea ?? 'ZZZ').compareTo(b.customerArea ?? 'ZZZ');
      if (areaCompare != 0) return areaCompare;
      return (a.customerName ?? '').compareTo(b.customerName ?? '');
    });

    // 3. Populate data rows
    final dataStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Center,
    );

    final nameStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Left,
    );

    for (var i = 0; i < sortedOrders.length; i++) {
      final order = sortedOrders[i];
      final rowIndex = i + 1;

      // Metadata
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
        ..value = TextCellValue(order.id)
        ..cellStyle = nameStyle;
      
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
        ..value = TextCellValue(order.customerName ?? 'Unknown (${order.id.substring(0, 4)})')
        ..cellStyle = nameStyle;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex))
        ..value = TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(order.createdAt))
        ..cellStyle = dataStyle;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex))
        ..value = TextCellValue(order.customerArea ?? 'N/A')
        ..cellStyle = nameStyle;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex))
        ..value = TextCellValue(order.customerLandmark ?? 'N/A')
        ..cellStyle = nameStyle;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex))
        ..value = DoubleCellValue(order.totalAmount)
        ..cellStyle = dataStyle;

      // #Veg Count
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex))
        ..value = IntCellValue(order.items.length)
        ..cellStyle = dataStyle;

      // Sum of weight — only for items whose unit is 'kg'
      double totalWeight = 0;
      const kgUnits = {'kg', 'kgs', 'kilogram', 'kilograms'};
      for (var item in order.items) {
        if (kgUnits.contains(item.unit.toLowerCase().trim())) {
          totalWeight += item.orderedQuantity;
        }
      }
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex))
        ..value = DoubleCellValue(totalWeight)
        ..cellStyle = dataStyle;

      // Products
      final orderItemsMap = {for (var item in order.items) item.productName: item.orderedQuantity};

      for (var p = 0; p < allProducts.length; p++) {
        final productName = allProducts[p];
        final colIndex = metadataHeaders.length + p;
        final qty = orderItemsMap[productName];
        
        if (qty != null) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: rowIndex))
            ..value = DoubleCellValue(qty)
            ..cellStyle = dataStyle;
        } else {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: rowIndex))
            ..value = const IntCellValue(0)
            ..cellStyle = dataStyle;
        }
      }
    }

    // 4. Set column widths
    sheet.setColumnWidth(0, 36); // Order ID
    sheet.setColumnWidth(1, 25); // Customer Name
    sheet.setColumnWidth(2, 20); // Date
    sheet.setColumnWidth(3, 20); // Area
    sheet.setColumnWidth(4, 25); // Landmark
    sheet.setColumnWidth(5, 18); // Amount
    sheet.setColumnWidth(6, 14); // #Veg Count
    sheet.setColumnWidth(7, 18); // Total Weight (kg)
    
    for (var p = 0; p < allProducts.length; p++) {
      sheet.setColumnWidth(metadataHeaders.length + p, 15);
    }

    // 5. Save and Share
    final bytes = excel.save();
    if (bytes != null) {
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final fileName = 'Annam_Delivery_Summary_$date.xlsx';

      if (kIsWeb) {
        // Web Download
        final base64Data = base64Encode(bytes);
        final anchor = html.AnchorElement(
            href: 'data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$base64Data')
          ..target = 'blank'
          ..download = fileName;
        html.document.body?.append(anchor);
        anchor.click();
        anchor.remove();
      } else {
        // Mobile / Desktop Download
        final directory = await getTemporaryDirectory();
        final filePath = "${directory.path}/$fileName";
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        await Share.shareXFiles([XFile(filePath)], text: 'Annam Delivery Summary $date');
      }
    }
  }
}
