import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';
import '../models/category_model.dart';
import '../models/product_model.dart';
import '../models/order_model.dart';
import '../models/cart_item_model.dart';

/// Clean HTTP Service for interacting with the FastAPI Backend.
/// Includes connection timeout, friendly exception handling, and JSON parsing.
class ApiService {
  String _baseUrl;
  final http.Client _client;

  ApiService({
    String? baseUrl,
    http.Client? client,
  })  : _baseUrl = baseUrl ?? AppConfig.defaultApiBaseUrl,
        _client = client ?? http.Client();

  String get baseUrl => _baseUrl;

  void updateBaseUrl(String newUrl) {
    _baseUrl = newUrl.endsWith('/') ? newUrl.substring(0, newUrl.length - 1) : newUrl;
  }

  static const Duration timeoutDuration = Duration(seconds: 8);

  // -------------------------------------------------------------
  // Health Check
  // -------------------------------------------------------------
  Future<bool> checkHealth() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/health');
      final res = await _client.get(uri).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------
  // Categories
  // -------------------------------------------------------------
  Future<List<CategoryModel>> getCategories({bool activeOnly = true}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/categories').replace(
        queryParameters: {'active_only': activeOnly.toString()},
      );
      final response = await _client.get(uri).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(utf8.decode(response.bodyBytes));
        return jsonList
            .map((item) => CategoryModel.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        throw HttpException('Failed to load categories: ${response.statusCode}');
      }
    } on SocketException {
      throw const SocketException('Unable to reach café server. Please check your network.');
    } on TimeoutException {
      throw TimeoutException('Request timed out while connecting to café server.');
    }
  }

  // -------------------------------------------------------------
  // Products
  // -------------------------------------------------------------
  Future<List<ProductModel>> getProducts({
    int? categoryId,
    String? search,
    bool isAvailable = true,
  }) async {
    try {
      final params = <String, String>{
        'is_available': isAvailable.toString(),
      };
      if (categoryId != null) {
        params['category_id'] = categoryId.toString();
      }
      if (search != null && search.trim().isNotEmpty) {
        params['search'] = search.trim();
      }

      final uri = Uri.parse('$_baseUrl/api/products').replace(queryParameters: params);
      final response = await _client.get(uri).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(utf8.decode(response.bodyBytes));
        return jsonList
            .map((item) => ProductModel.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        throw HttpException('Failed to load products: ${response.statusCode}');
      }
    } on SocketException {
      throw const SocketException('Unable to reach café server. Please check your network.');
    } on TimeoutException {
      throw TimeoutException('Request timed out while connecting to café server.');
    }
  }

  // -------------------------------------------------------------
  // Orders: Create New Order
  // -------------------------------------------------------------
  Future<OrderModel> createOrder({
    required String customerName,
    required String customerPhone,
    required List<CartItemModel> items,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/orders');
      final body = jsonEncode({
        'customer_name': customerName.trim(),
        'customer_phone': customerPhone.trim(),
        'items': items.map((item) => item.toOrderItemPayload()).toList(),
      });

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final Map<String, dynamic> jsonData = jsonDecode(utf8.decode(response.bodyBytes));
        return OrderModel.fromJson(jsonData);
      } else {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        final detail = errorBody['detail'] ?? 'Order failed';
        throw HttpException(detail.toString());
      }
    } on SocketException {
      throw const SocketException('Unable to reach café server to place order.');
    } on TimeoutException {
      throw TimeoutException('Order request timed out.');
    }
  }

  // -------------------------------------------------------------
  // Orders: Lookup by Customer Phone
  // -------------------------------------------------------------
  Future<List<OrderModel>> getOrdersByPhone(String phone) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/orders/lookup/phone').replace(
        queryParameters: {'phone': phone.trim()},
      );
      final response = await _client.get(uri).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(utf8.decode(response.bodyBytes));
        return jsonList
            .map((item) => OrderModel.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        throw HttpException('Failed to lookup orders: ${response.statusCode}');
      }
    } on SocketException {
      throw const SocketException('Unable to connect to café server.');
    } on TimeoutException {
      throw TimeoutException('Lookup request timed out.');
    }
  }

  // -------------------------------------------------------------
  // Orders: Lookup by Order Number (Reference)
  // -------------------------------------------------------------
  Future<OrderModel> getOrderByReference(String orderNumber) async {
    try {
      final cleanRef = Uri.encodeComponent(orderNumber.trim());
      final uri = Uri.parse('$_baseUrl/api/orders/ref/$cleanRef');
      final response = await _client.get(uri).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonData = jsonDecode(utf8.decode(response.bodyBytes));
        return OrderModel.fromJson(jsonData);
      } else if (response.statusCode == 404) {
        throw const HttpException('Order not found. Please verify your reference number.');
      } else {
        throw HttpException('Failed to fetch order: ${response.statusCode}');
      }
    } on SocketException {
      throw const SocketException('Unable to reach café server.');
    } on TimeoutException {
      throw TimeoutException('Order lookup timed out.');
    }
  }

  // -------------------------------------------------------------
  // Customer Authentication: Register & Login
  // -------------------------------------------------------------
  Future<Map<String, dynamic>> registerCustomer({
    required String fullName,
    required String phone,
    String? email,
    required String password,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/auth/register');
      final payload = <String, dynamic>{
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'password': password,
      };
      if (email != null && email.trim().isNotEmpty) {
        payload['email'] = email.trim();
      }

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(timeoutDuration);

      final Map<String, dynamic> jsonData = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonData;
      } else {
        final detail = jsonData['detail'] ?? 'Registration failed.';
        throw HttpException(detail.toString());
      }
    } on SocketException {
      throw const SocketException('Unable to reach café server.');
    } on TimeoutException {
      throw TimeoutException('Registration request timed out.');
    }
  }

  Future<Map<String, dynamic>> loginCustomer({
    required String identifier,
    required String password,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/auth/login');
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'identifier': identifier.trim(),
              'password': password,
            }),
          )
          .timeout(timeoutDuration);

      final Map<String, dynamic> jsonData = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200) {
        return jsonData;
      } else {
        final detail = jsonData['detail'] ?? 'Invalid credentials.';
        throw HttpException(detail.toString());
      }
    } on SocketException {
      throw const SocketException('Unable to reach café server.');
    } on TimeoutException {
      throw TimeoutException('Login request timed out.');
    }
  }

  Future<Map<String, dynamic>> getCustomerMe(String token) async {
    final uri = Uri.parse('$_baseUrl/api/auth/me');
    final response = await _client
        .get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(timeoutDuration);

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    }
    throw HttpException('Failed to fetch customer profile (${response.statusCode})');
  }
}
