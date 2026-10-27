import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/models/order_model.dart';
import '../data/models/cart_item_model.dart';
import '../data/repositories/order_repository.dart';

/// Provider for order placement, order lookup, and real-time order status tracking.
class OrderProvider extends ChangeNotifier {
  final OrderRepository _orderRepository;

  OrderProvider({required OrderRepository orderRepository})
      : _orderRepository = orderRepository;

  OrderModel? _activeOrder;
  List<OrderModel> _recentOrders = [];
  bool _isPlacingOrder = false;
  bool _isLoading = false;
  String? _errorMessage;

  Timer? _pollingTimer;

  // Getters
  OrderModel? get activeOrder => _activeOrder;
  List<OrderModel> get recentOrders => List.unmodifiable(_recentOrders);
  bool get isPlacingOrder => _isPlacingOrder;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Places a new order and sets it as the active tracked order
  Future<OrderModel?> placeOrder({
    required String customerName,
    required String customerPhone,
    required List<CartItemModel> items,
  }) async {
    _isPlacingOrder = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final order = await _orderRepository.placeOrder(
        customerName: customerName,
        customerPhone: customerPhone,
        items: items,
      );
      _activeOrder = order;

      // Add to local recent orders if not present
      final existingIndex = _recentOrders.indexWhere((o) => o.orderNumber == order.orderNumber);
      if (existingIndex >= 0) {
        _recentOrders[existingIndex] = order;
      } else {
        _recentOrders.insert(0, order);
      }

      _startStatusPolling();
      return order;
    } catch (e) {
      _errorMessage = 'Failed to place order: $e';
      return null;
    } finally {
      _isPlacingOrder = false;
      notifyListeners();
    }
  }

  /// Selects an order for real-time tracking
  void setActiveOrder(OrderModel order) {
    _activeOrder = order;
    _startStatusPolling();
    notifyListeners();
  }

  /// Looks up customer orders by phone number
  Future<void> lookupOrdersByPhone(String phone) async {
    if (phone.trim().isEmpty) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final list = await _orderRepository.getOrdersByPhone(phone.trim());
      _recentOrders = list;
      if (list.isNotEmpty && _activeOrder == null) {
        _activeOrder = list.first;
        _startStatusPolling();
      }
    } catch (e) {
      _errorMessage = 'Lookup failed: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Looks up a specific order by reference number (e.g. CAF-20261017-0042)
  Future<OrderModel?> lookupOrderByReference(String orderNumber) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final order = await _orderRepository.getOrderByReference(orderNumber.trim());
      if (order != null) {
        _activeOrder = order;
        final existingIndex = _recentOrders.indexWhere((o) => o.orderNumber == order.orderNumber);
        if (existingIndex >= 0) {
          _recentOrders[existingIndex] = order;
        } else {
          _recentOrders.insert(0, order);
        }
        _startStatusPolling();
      }
      return order;
    } catch (e) {
      _errorMessage = 'Could not find order: $e';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Polls the server for live status updates if the active order is currently pending or preparing
  Future<void> refreshActiveOrder() async {
    if (_activeOrder == null) return;

    try {
      final updated = await _orderRepository.getOrderByReference(_activeOrder!.orderNumber);
      if (updated != null && updated.orderStatus != _activeOrder!.orderStatus) {
        _activeOrder = updated;
        final index = _recentOrders.indexWhere((o) => o.orderNumber == updated.orderNumber);
        if (index >= 0) {
          _recentOrders[index] = updated;
        }
        notifyListeners();
      }
    } catch (_) {
      // Ignore background poll errors
    }
  }

  void _startStatusPolling() {
    _pollingTimer?.cancel();
    if (_activeOrder == null) return;

    final status = _activeOrder!.orderStatus.toLowerCase();
    if (status == 'pending' || status == 'preparing') {
      _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        refreshActiveOrder();
      });
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}
