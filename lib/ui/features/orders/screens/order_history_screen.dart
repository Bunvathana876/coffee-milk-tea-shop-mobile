import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../data/models/cart_item_model.dart';
import '../../../../data/models/order_model.dart';
import '../../../../data/models/product_model.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/order_provider.dart';
import '../../../../providers/shop_provider.dart';
import '../../../../providers/user_provider.dart';
import '../widgets/order_card.dart';
import 'order_tracking_screen.dart';

/// Screen displaying customer's order history and fast phone/reference lookup.
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key, this.onExploreMenu});

  final VoidCallback? onExploreMenu;

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final TextEditingController _lookupController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<UserProvider>();
      if (user.customerPhone.isNotEmpty) {
        context.read<OrderProvider>().lookupOrdersByPhone(user.customerPhone);
      }
    });
  }

  @override
  void dispose() {
    _lookupController.dispose();
    super.dispose();
  }

  void _performLookup() {
    final query = _lookupController.text.trim();
    if (query.isEmpty) return;

    final orderProvider = context.read<OrderProvider>();
    if (query.toUpperCase().startsWith('CAF-')) {
      orderProvider.lookupOrderByReference(query);
    } else {
      orderProvider.lookupOrdersByPhone(query);
    }
  }

  void _handleReorder(OrderModel order) {
    final shop = context.read<ShopProvider>();
    final cart = context.read<CartProvider>();

    final reorderedItems = <CartItemModel>[];
    for (final item in order.items) {
      ProductModel product;
      final found = shop.products.where((p) => p.id == item.productId).firstOrNull;
      if (found != null) {
        product = found;
      } else {
        product = ProductModel(
          id: item.productId ?? 0,
          name: item.productName,
          categoryId: 1,
          basePriceUsd: item.unitPriceUsd,
          isAvailable: true,
        );
      }

      final toppingsList = item.toppings
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      reorderedItems.add(
        CartItemModel(
          product: product,
          size: item.size,
          sugarLevel: item.sugarLevel,
          iceLevel: item.iceLevel,
          toppings: toppingsList,
          quantity: item.quantity,
        ),
      );
    }

    cart.addItems(reorderedItems);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${reorderedItems.length} items from ${order.orderNumber} to bag!'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Orders'),
      ),
      body: Column(
        children: [
          // Search / Lookup Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lookupController,
                    decoration: InputDecoration(
                      hintText: 'Enter phone or order ref (CAF-...)',
                      prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                      suffixIcon: _lookupController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _lookupController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _performLookup(),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: _performLookup,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.all(14),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),

          // Orders List
          Expanded(
            child: orderProvider.isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : orderProvider.recentOrders.isEmpty
                    ? EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No orders found',
                        description: 'You haven\'t placed any orders yet, or no orders match your phone lookup.',
                        actionLabel: 'Order Drinks Now',
                        onAction: widget.onExploreMenu,
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          if (_lookupController.text.isNotEmpty) {
                            _performLookup();
                          }
                        },
                        color: AppColors.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          itemCount: orderProvider.recentOrders.length,
                          itemBuilder: (context, index) {
                            final order = orderProvider.recentOrders[index];
                            return OrderCard(
                              order: order,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => OrderTrackingScreen(order: order),
                                  ),
                                );
                              },
                              onReorder: () => _handleReorder(order),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
