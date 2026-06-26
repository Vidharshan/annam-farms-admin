import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../data/orders_repository.dart';
import '../../../shared/domain/order_model.dart';
import '../../../shared/domain/order_item.dart';
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => adminScaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Packing Mode'),
        actions: [
          // Download Packing Sheet
          ordersAsync.whenOrNull(
            data: (allOrders) {
              final processingOrders = allOrders
                  .where((o) => o.status == 'processing')
                  .toList();
              return IconButton(
                icon: const Icon(Icons.file_download_outlined),
                tooltip: 'Download Packing Sheet',
                onPressed: processingOrders.isEmpty
                    ? null
                    : () => _downloadSheet(context, processingOrders),
              );
            },
          ) ?? const SizedBox.shrink(),

          // Upload Packing Sheet
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
      body: ordersAsync.when(
        data: (allOrders) {
          // Get only processing orders
          final processingOrders = allOrders
              .where((o) => o.status == 'processing')
              .toList();

          if (processingOrders.isEmpty) {
            return const Center(
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
            );
          }

          // Group orders by customer (user_id would be better, but using order ID for now)
          // In a real app, you'd group by user_id
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

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                children: [
                  // Navigation Header
                  Container(
                    color: Colors.grey[900],
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: currentCustomerIndex > 0
                              ? () => setState(() => currentCustomerIndex--)
                              : null,
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'Order ${currentCustomerIndex + 1} of ${customers.length}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Order #${currentOrder.id.substring(0, 8)}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: currentCustomerIndex < customers.length - 1
                              ? () => setState(() => currentCustomerIndex++)
                              : null,
                        ),
                      ],
                    ),
                  ),

                  // Order Info & Customer Details
                  Container(
                    color: Colors.grey[850],
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentOrder.customerName ?? 'Unknown Customer',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                                  ),
                                  if (currentOrder.customerArea != null)
                                    Text(
                                      currentOrder.customerArea!,
                                      style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '₹${currentOrder.totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Created: ${DateFormat('MMM dd, hh:mm a').format(currentOrder.createdAt)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Items: ${currentOrder.items.length}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            if (currentOrder.customerPhone != null)
                              TextButton.icon(
                                onPressed: () {}, // Could implement calling logic
                                icon: const Icon(Icons.phone, size: 16),
                                label: Text(currentOrder.customerPhone!),
                                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Items List
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: currentOrder.items.length,
                      itemBuilder: (context, index) {
                        final item = currentOrder.items[index];
                        final orderedQty = item.orderedQuantity;
                        final packedQty = packedQuantities[currentOrder.id]![item.productId]!;
                        
                        // Initialize completed items set for this order
                        if (!completedItems.containsKey(currentOrder.id)) {
                          completedItems[currentOrder.id] = {};
                        }
                        final isCompleted = completedItems[currentOrder.id]!.contains(item.productId);

                        return PackingItemCard(
                          item: item,
                          orderedQty: orderedQty,
                          packedQty: packedQty,
                          isCompleted: isCompleted,
                          onToggleComplete: (val) {
                            setState(() {
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

                  // Action Buttons
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              // Reset to ordered quantities
                              setState(() {
                                packedQuantities[currentOrder.id] = {
                                  for (var item in currentOrder.items)
                                    item.productId: item.orderedQuantity.toDouble()
                                };
                              });
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reset'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () => _markAsPacked(context, currentOrder),
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Mark as Packed'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
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

      if (!context.mounted) return;

      // 3. Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm Upload'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📦 ${importResult.totalOrders} orders found'),
              Text('🥬 ${importResult.totalProducts} products'),
              Text('📝 ${importResult.updates.length} quantity updates'),
              if (importResult.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('⚠️ Warnings:', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                ...importResult.warnings.take(5).map((w) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(w, style: const TextStyle(fontSize: 12, color: Colors.orange)),
                )),
                if (importResult.warnings.length > 5)
                  Text('...and ${importResult.warnings.length - 5} more', style: const TextStyle(fontSize: 12, color: Colors.orange)),
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
      // Update packed quantities per item
      for (var item in order.items) {
        await ref.read(ordersRepositoryProvider).updateOrderItem(
          orderId: order.id,
          productId: item.productId,
          packedQty: packedQuantities[order.id]![item.productId]!,
        );
      }
      
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

class PackingItemCard extends StatefulWidget {
  final OrderItem item;
  final double orderedQty;
  final double packedQty;
  final bool isCompleted;
  final ValueChanged<bool?> onToggleComplete;
  final ValueChanged<double> onQtyChanged;

  const PackingItemCard({
    super.key,
    required this.item,
    required this.orderedQty,
    required this.packedQty,
    required this.isCompleted,
    required this.onToggleComplete,
    required this.onQtyChanged,
  });

  @override
  State<PackingItemCard> createState() => _PackingItemCardState();
}

class _PackingItemCardState extends State<PackingItemCard> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatQty(widget.packedQty));
  }

  @override
  void didUpdateWidget(covariant PackingItemCard oldWidget) {
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Checkbox
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: widget.isCompleted,
                    onChanged: widget.onToggleComplete,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 12),
                
                // 2. Main content area (Product Name, Price, and Ordered Qty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product Name (full width)
                      Text(
                        widget.item.productName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          decoration: widget.isCompleted ? TextDecoration.lineThrough : null,
                          color: widget.isCompleted ? Colors.grey : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // Price and Ordered Pill on second line
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Text(
                            '₹${widget.item.pricePerUnit} / ${widget.item.unit}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[400],
                              decoration: widget.isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Ordered: ${widget.orderedQty} ${widget.item.unit}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 16),
            
            // 3. Packed Qty Input Area
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Packed Qty:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    border: Border.all(color: Colors.grey[700]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SizedBox(
                    width: 100,
                    height: 40,
                    child: TextField(
                      controller: _controller,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        suffixText: widget.item.unit,
                        suffixStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (value) {
                         // Allow empty or just decimal point
                        if (value.isEmpty) return;
                        if (value == '.') return;

                        // Regex to validate max 2 decimal places
                        if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(value)) {
                           return;
                        }

                        final qty = double.tryParse(value);
                        if (qty != null && qty >= 0) {
                          widget.onQtyChanged(qty);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            if (widget.packedQty != widget.orderedQty)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Modified (Ordered: ${widget.orderedQty.toStringAsFixed(0)} ${widget.item.unit})',
                        style: TextStyle(color: Colors.blue[300], fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
