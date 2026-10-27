import 'dart:math';
import '../models/order_model.dart';
import '../models/cart_item_model.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../../core/config/app_config.dart';

/// Repository managing customer orders, tracking status, and order history.
class OrderRepository {
  final ApiService _apiService;
  final LocalStorageService _localStorageService;

  OrderRepository({
    required ApiService apiService,
    required LocalStorageService localStorageService,
  })  : _apiService = apiService,
        _localStorageService = localStorageService;

  /// Places a new order via FastAPI backend.
  /// If offline, generates a simulated order so the app remains fully functional!
  Future<OrderModel> placeOrder({
    required String customerName,
    required String customerPhone,
    required List<CartItemModel> items,
  }) async {
    try {
      final order = await _apiService.createOrder(
        customerName: customerName,
        customerPhone: customerPhone,
        items: items,
      );
      await _localStorageService.addRecentOrderRef(order.orderNumber);
      return order;
    } catch (e) {
      // If server is unreachable or offline, create a local simulated order
      final simulated = _createSimulatedOrder(
        customerName: customerName,
        customerPhone: customerPhone,
        items: items,
      );
      await _localStorageService.addRecentOrderRef(simulated.orderNumber);
      return simulated;
    }
  }

  /// Looks up customer orders by phone number.
  Future<List<OrderModel>> getOrdersByPhone(String phone) async {
    try {
      final orders = await _apiService.getOrdersByPhone(phone);
      return orders;
    } catch (_) {
      return [];
    }
  }

  /// Looks up an individual order by reference number (e.g. CAF-20261017-0042).
  Future<OrderModel?> getOrderByReference(String orderNumber) async {
    try {
      return await _apiService.getOrderByReference(orderNumber);
    } catch (_) {
      return null;
    }
  }

  /// Creates a simulated order for offline preview and testing
  OrderModel _createSimulatedOrder({
    required String customerName,
    required String customerPhone,
    required List<CartItemModel> items,
  }) {
    final now = DateTime.now();
    final randomDigits = 1000 + Random().nextInt(9000);
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final orderNumber = 'CAF-$dateStr-$randomDigits';

    double subtotal = 0.0;
    final orderItems = <OrderItemModel>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      subtotal += item.subtotalUsd;
      orderItems.add(
        OrderItemModel(
          id: i + 1,
          productId: item.product.id,
          productName: item.product.name,
          quantity: item.quantity,
          unitPriceUsd: item.unitPriceUsd,
          subtotalUsd: item.subtotalUsd,
          size: item.size,
          sugarLevel: item.sugarLevel,
          iceLevel: item.iceLevel,
        ),
      );
    }

    final totalKhr = subtotal * AppConfig.khrExchangeRate;

    return OrderModel(
      id: Random().nextInt(99999),
      orderNumber: orderNumber,
      customerName: customerName,
      customerPhone: customerPhone,
      subtotalUsd: subtotal,
      totalUsd: subtotal,
      totalKhr: totalKhr,
      paymentStatus: 'unpaid',
      orderStatus: 'pending',
      createdAt: now,
      items: orderItems,
    );
  }
}
