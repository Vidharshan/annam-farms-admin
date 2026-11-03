import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../data/orders_repository.dart';
import '../../../shared/domain/order_model.dart';
import '../../../shared/services/excel_export_service.dart';
import '../../../shared/services/excel_import_service.dart';
import '../../../main.dart';

class PackingScreen extends ConsumerStatefulWidget {
  const PackingScreen({super.key});

  @override
  ConsumerState<PackingScreen> createState() => _PackingScreenState();
}

class _PackingScreenState extends ConsumerState<PackingScreen> {
  int currentCustomerIndex = 0;
  Map<String, Map<String, double>> packedQuantities = {};
  Map<String, Set<String>> completedItems = {}; // Track completed items per order
  bool _isUploading = false;
  final Map<String, Timer> _debounceTimers = {};

  @override
  void dispose() {
    for (var timer in _debounceTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _debouncedSaveQty(Order order, String productId, double qty) {
    final key = '${order.id}_$productId';
    if (_debounceTimers[key]?.isActive ?? false) {
      _debounceTimers[key]!.cancel();
    }
    _debounceTimers[key] = Timer(const Duration(milliseconds: 600), () {
      ref.read(ordersRepositoryProvider).updateOrderItem(
        orderId: order.id,
        productId: productId,
        packedQty: qty,
      ).catchError((e) {
        debugPrint('Auto-save error: $e');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(allOrdersProvider);

    return ordersAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => adminScaffoldKey.currentState?.openDrawer(),
          ),
          title: const Text('Packing Mode'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => adminScaffoldKey.currentState?.openDrawer(),
          ),
          title: const Text('Packing Mode'),
        ),
        body: Center(child: Text('Error: $err')),
      ),
      data: (allOrders) {
        // Get only processing orders
        final processingOrders = allOrders
            .where((o) => o.status == 'processing')
            .toList();

        if (processingOrders.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => adminScaffoldKey.currentState?.openDrawer(),
              ),
              title: const Text('Packing Mode'),
              actions: [
                IconButton(
                  icon: _isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.file_upload_outlined),
                  tooltip: 'Upload Packed Sheet',
                  onPressed: _isUploading ? null : () => _uploadSheet(context),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(allOrdersProvider),
                ),
                const SizedBox(width: 16),
              ],
            ),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No orders to pack', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('Move orders to "Processing" status first', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          );
        }

        final customers = processingOrders;

        if (currentCustomerIndex >= customers.length) {
          currentCustomerIndex = 0;
        }

        final currentOrder = customers[currentCustomerIndex];

        // Initialize packed quantities for this order
        if (!packedQuantities.containsKey(currentOrder.id)) {
          packedQuantities[currentOrder.id] = {
            for (var item in currentOrder.items)
              item.productId: item.deliveredQuantity?.toDouble() ?? item.orderedQuantity.toDouble()
          };
        }

        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
              if (currentCustomerIndex > 0) {
                setState(() => currentCustomerIndex--);
              }
            },
            const SingleActivator(LogicalKeyboardKey.arrowRight): () {
              if (currentCustomerIndex < customers.length - 1) {
                setState(() => currentCustomerIndex++);
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => adminScaffoldKey.currentState?.openDrawer(),
                ),
                title: const Text('Packing Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                actions: [
                  // Reset Button
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        packedQuantities[currentOrder.id] = {
                          for (var item in currentOrder.items)
                            item.productId: item.orderedQuantity.toDouble()
                        };
                        completedItems[currentOrder.id]?.clear();
                      });
                    },
                    icon: const Icon(Icons.refresh, size: 15),
                    label: const Text('Reset'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[300],
                      side: BorderSide(color: Colors.grey[700]!),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Mark as Packed Button
                  ElevatedButton.icon(
                    onPressed: () => _markAsPacked(context, currentOrder),
                    icon: const Icon(Icons.check_circle, size: 16),
                    label: const Text('Mark Packed', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      visualDensity: VisualDensity.compact,
                      elevation: 1,
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Download Packing Sheet
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined),
                    tooltip: 'Download Packing Sheet',
                    onPressed: () => _downloadSheet(context, processingOrders),
                  ),

                  // Upload Packing Sheet
                  IconButton(
                    icon: _isUploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.file_upload_outlined),
                    tooltip: 'Upload Packed Sheet',
                    onPressed: _isUploading ? null : () => _uploadSheet(context),
                  ),

                  // Refresh
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh Orders',
                    onPressed: () => ref.invalidate(allOrdersProvider),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: Column(
                children: [
                  // Centered Minimal Customer & Stepper Block
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 780),
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(
                          children: [
                            // Left / Previous Customer Button
                            IconButton.filledTonal(
                              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                              tooltip: 'Previous Customer (←)',
                              onPressed: currentCustomerIndex > 0
                                  ? () => setState(() => currentCustomerIndex--)
                                  : null,
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.08),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.white.withValues(alpha: 0.02),
                                disabledForegroundColor: Colors.white24,
                                minimumSize: const Size(42, 42),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Centered Customer Details
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Stepper count & Order ID
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Order ${currentCustomerIndex + 1} of ${customers.length}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '#${currentOrder.id.length > 8 ? currentOrder.id.substring(0, 8) : currentOrder.id}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),

                                  // Customer Name (Bold Green)
                                  Text(
                                    currentOrder.customerName ?? 'Unknown Customer',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.greenAccent,
                                      letterSpacing: 0.2,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),

                                  // Details Badges: Area, Phone, Items count, Comments
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 10,
                                    runSpacing: 4,
                                    children: [
                                      if (currentOrder.customerArea != null && currentOrder.customerArea!.isNotEmpty)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.location_on, size: 14, color: Colors.amber[400]),
                                            const SizedBox(width: 3),
                                            Text(
                                              currentOrder.customerArea!,
                                              style: TextStyle(fontSize: 12.5, color: Colors.grey[300], fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                      if (currentOrder.customerPhone != null && currentOrder.customerPhone!.isNotEmpty)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.phone, size: 13, color: Colors.blue[300]),
                                            const SizedBox(width: 3),
                                            Text(
                                              currentOrder.customerPhone!,
                                              style: TextStyle(fontSize: 12.5, color: Colors.grey[300]),
                                            ),
                                          ],
                                        ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${currentOrder.items.length} items',
                                          style: TextStyle(fontSize: 11.5, color: Colors.grey[300], fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      if (currentOrder.comments != null && currentOrder.comments!.isNotEmpty)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.sticky_note_2_outlined, size: 13, color: Colors.orange[300]),
                                            const SizedBox(width: 3),
                                            ConstrainedBox(
                                              constraints: const BoxConstraints(maxWidth: 220),
                                              child: Text(
                                                currentOrder.comments!,
                                                style: TextStyle(fontSize: 12, color: Colors.orange[200], fontStyle: FontStyle.italic),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Right / Next Customer Button
                            IconButton.filledTonal(
                              icon: const Icon(Icons.arrow_forward_ios, size: 18),
                              tooltip: 'Next Customer (→)',
                              onPressed: currentCustomerIndex < customers.length - 1
                                  ? () => setState(() => currentCustomerIndex++)
                                  : null,
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.08),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.white.withValues(alpha: 0.02),
                                disabledForegroundColor: Colors.white24,
                                minimumSize: const Size(42, 42),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Items List / Grid (Centered, conditional 2-column)
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Calculate available vertical height
                        final availableHeight = constraints.maxHeight - 16;
                        const rowHeight = 42.0;
                        const rowSpacing = 6.0;
                        const effectiveItemHeight = rowHeight + rowSpacing;
                        final maxItemsInSingleColumn = (availableHeight / effectiveItemHeight).floor();

                        // Only use 2 columns if the items DO NOT fit vertically in a single column
                        // AND screen width is wide enough (>= 750px)
                        final useTwoColumns = constraints.maxWidth >= 750 &&
                            currentOrder.items.length > maxItemsInSingleColumn;

                        return Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: useTwoColumns ? 1300 : 780,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: useTwoColumns
                                  ? GridView.builder(
                                      itemCount: currentOrder.items.length,
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        mainAxisExtent: rowHeight,
                                        crossAxisSpacing: 14,
                                        mainAxisSpacing: rowSpacing,
                                      ),
                                      itemBuilder: (context, index) {
                                        final item = currentOrder.items[index];
                                        final orderedQty = item.orderedQuantity;
                                        final packedQty = packedQuantities[currentOrder.id]?[item.productId] ?? orderedQty.toDouble();
                                        final isCompleted = completedItems[currentOrder.id]?.contains(item.productId) ?? false;

                                        return PackingItemRow(
                                          item: item,
                                          orderedQty: orderedQty,
                                          packedQty: packedQty,
                                          isCompleted: isCompleted,
                                          onToggleComplete: (val) {
                                            setState(() {
                                              completedItems.putIfAbsent(currentOrder.id, () => {});
                                              if (val == true) {
                                                completedItems[currentOrder.id]!.add(item.productId);
                                              } else {
                                                completedItems[currentOrder.id]!.remove(item.productId);
                                              }
                                            });
                                          },
                                          onQtyChanged: (val) {
                                            setState(() {
                                              packedQuantities[currentOrder.id]![item.productId] = val;
                                            });
                                            _debouncedSaveQty(currentOrder, item.productId, val);
                                          },
                                        );
                                      },
                                    )
                                  : ListView.separated(
                                      itemCount: currentOrder.items.length,
                                      separatorBuilder: (context, index) => const SizedBox(height: rowSpacing),
                                      itemBuilder: (context, index) {
                                        final item = currentOrder.items[index];
                                        final orderedQty = item.orderedQuantity;
                                        final packedQty = packedQuantities[currentOrder.id]?[item.productId] ?? orderedQty.toDouble();
                                        final isCompleted = completedItems[currentOrder.id]?.contains(item.productId) ?? false;

                                        return PackingItemRow(
                                          item: item,
                                          orderedQty: orderedQty,
                                          packedQty: packedQty,
                                          isCompleted: isCompleted,
                                          onToggleComplete: (val) {
                                            setState(() {
                                              completedItems.putIfAbsent(currentOrder.id, () => {});
                                              if (val == true) {
                                                completedItems[currentOrder.id]!.add(item.productId);
                                              } else {
                                                completedItems[currentOrder.id]!.remove(item.productId);
                                              }
                                            });
                                          },
                                          onQtyChanged: (val) {
                                            setState(() {
                                              packedQuantities[currentOrder.id]![item.productId] = val;
                                            });
                                            _debouncedSaveQty(currentOrder, item.productId, val);
                                          },
                                        );
                                      },
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Download Packing Sheet ───────────────────────────────────────────
  Future<void> _downloadSheet(BuildContext context, List<Order> orders) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating packing sheet...')),
    );
    try {
      await ExcelExportService.exportPackingSheet(orders);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting: $e')),
        );
      }
    }
  }

  // ─── Upload Packed Sheet ──────────────────────────────────────────────
  Future<void> _uploadSheet(BuildContext context) async {
    try {
      // 1. Pick file
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        allowMultiple: false,
        withData: true, // Required on web to populate .bytes
      );

      if (result == null || result.files.isEmpty) return;

      // Use bytes directly — works on both Web and Android
      final fileBytes = result.files.single.bytes;
      if (fileBytes == null) return;

      setState(() => _isUploading = true);

      // 2. Parse Excel from bytes
      final importResult = await ExcelImportService.parsePackingSheet(fileBytes);

      // 3. Generate summary of actual changes
      final currentOrders = ref.read(allOrdersProvider).value ?? [];
      final diffs = await ref.read(ordersRepositoryProvider).generateImportDiff(importResult, currentOrders);

      if (!context.mounted) return;

      // 4. Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm Upload'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📦 ${importResult.totalOrders} orders found'),
              Text('📝 ${diffs.length} actual quantity changes'),
              if (diffs.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Actual Changes:', style: TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copy all changes',
                      onPressed: () {
                        final textToCopy = diffs.map((d) => '• $d').join('\n');
                        Clipboard.setData(ClipboardData(text: textToCopy));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard!')),
                        );
                      },
                    ),
                  ],
                ),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: diffs.length,
                    itemBuilder: (context, index) => SelectableText(
                      '• ${diffs[index]}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
              if (importResult.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('⚠️ Warnings:', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                ...importResult.warnings.take(3).map((w) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(w, style: const TextStyle(fontSize: 12, color: Colors.orange)),
                )),
                if (importResult.warnings.length > 3)
                  Text('...and ${importResult.warnings.length - 3} more', style: const TextStyle(fontSize: 12, color: Colors.orange)),
              ],
              const SizedBox(height: 16),
              const Text(
                'This will update packed quantities for all orders and mark them as packed.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.upload),
              label: const Text('Update All'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        setState(() => _isUploading = false);
        return;
      }

      // 4. Batch update
      final updateResult = await ref
          .read(ordersRepositoryProvider)
          .batchUpdatePackedQuantities(importResult);

      // 5. Refresh orders
      ref.invalidate(allOrdersProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Updated ${updateResult.updatedItems} items across ${updateResult.affectedOrders} orders'
              '${updateResult.skippedItems > 0 ? ' (${updateResult.skippedItems} skipped)' : ''}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _markAsPacked(BuildContext context, Order order) async {
    try {
      // Update packed quantities per item in parallel
      await Future.wait(order.items.map((item) {
        return ref.read(ordersRepositoryProvider).updateOrderItem(
          orderId: order.id,
          productId: item.productId,
          packedQty: packedQuantities[order.id]![item.productId]!,
          skipFinalAmountCalc: true,
        );
      }));
      
      // Calculate items total based on packed quantities
      double itemsTotal = 0;
      for (var item in order.items) {
        itemsTotal += packedQuantities[order.id]![item.productId]! * item.pricePerUnit;
      }

      // Auto-fetch user's delivery cost from their profile
      final deliveryCost = await ref.read(ordersRepositoryProvider).getUserDeliveryCost(order.id);
      final finalAmount = itemsTotal + deliveryCost;

      await ref.read(ordersRepositoryProvider).updateFinalAmount(order.id, finalAmount, deliveryCost);
      await ref.read(ordersRepositoryProvider).updateOrderStatus(order.id, 'packed');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Packed! ₹${itemsTotal.toStringAsFixed(0)} + ₹${deliveryCost.toStringAsFixed(0)} delivery = ₹${finalAmount.toStringAsFixed(0)} ✓',
            ),
            backgroundColor: Colors.green,
          ),
        );
        
        // Move to next customer
        setState(() {
          packedQuantities.remove(order.id);
          if (currentCustomerIndex > 0) {
            currentCustomerIndex--;
          }
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

class PackingItemRow extends StatefulWidget {
  final OrderItem item;
  final double orderedQty;
  final double packedQty;
  final bool isCompleted;
  final ValueChanged<bool?> onToggleComplete;
  final ValueChanged<double> onQtyChanged;

  const PackingItemRow({
    super.key,
    required this.item,
    required this.orderedQty,
    required this.packedQty,
    required this.isCompleted,
    required this.onToggleComplete,
    required this.onQtyChanged,
  });

  @override
  State<PackingItemRow> createState() => _PackingItemRowState();
}

class _PackingItemRowState extends State<PackingItemRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatQty(widget.packedQty));
  }

  @override
  void didUpdateWidget(covariant PackingItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.packedQty != oldWidget.packedQty) {
      final currentVal = double.tryParse(_controller.text);
      if (currentVal != widget.packedQty) {
        _controller.text = _formatQty(widget.packedQty);
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatQty(double qty) {
    return qty.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final isModified = widget.packedQty != widget.orderedQty;
    final isCompleted = widget.isCompleted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => widget.onToggleComplete(!isCompleted),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isCompleted
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isCompleted
                  ? Colors.transparent
                  : (isModified ? Colors.blue.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Checkbox
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: isCompleted,
                  onChanged: widget.onToggleComplete,
                  activeColor: Colors.green,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 10),

              // Product Name
              Expanded(
                child: Text(
                  widget.item.productName,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                    color: isCompleted ? Colors.grey[500] : Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),

              // Ordered Tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Ord: ${_formatQty(widget.orderedQty)} ${widget.item.unit}',
                  style: TextStyle(
                    color: isCompleted ? Colors.grey[500] : Colors.orange[300],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Packed Input Field
              Container(
                width: 72,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.black38,
                  border: Border.all(
                    color: isModified ? Colors.blueAccent : Colors.grey[700]!,
                    width: isModified ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: TextField(
                  controller: _controller,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: isCompleted ? Colors.grey[500] : (isModified ? Colors.blue[300] : Colors.white),
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    suffixText: widget.item.unit,
                    suffixStyle: TextStyle(fontSize: 10.5, color: Colors.grey[500]),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    if (value.isEmpty || value == '.') return;
                    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(value)) return;
                    final qty = double.tryParse(value);
                    if (qty != null && qty >= 0) {
                      widget.onQtyChanged(qty);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

