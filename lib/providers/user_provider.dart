import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/config/app_config.dart';
import '../data/services/local_storage_service.dart';
import '../data/services/api_service.dart';

/// Provider for customer authentication, profile settings, loyalty stamps, and server connection.
class UserProvider extends ChangeNotifier {
  final LocalStorageService _localStorageService;
  final ApiService _apiService;

  UserProvider({
    required LocalStorageService localStorageService,
    required ApiService apiService,
  })  : _localStorageService = localStorageService,
        _apiService = apiService {
    _loadProfile();
  }

  String _customerName = '';
  String _customerPhone = '';
  String _customerEmail = '';
  String _authToken = '';
  String _apiUrl = '';
  bool _isServerOnline = false;
  bool _isLoading = false;
  String? _errorMessage;
  int _loyaltyStamps = 0;

  String get customerName => _customerName;
  String get customerPhone => _customerPhone;
  String get customerEmail => _customerEmail;
  String get authToken => _authToken;
  bool get isAuthenticated => _authToken.isNotEmpty;
  String get apiUrl => _apiUrl.isNotEmpty ? _apiUrl : _apiService.baseUrl;
  bool get isServerOnline => _isServerOnline;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasSavedProfile => _customerName.isNotEmpty && _customerPhone.isNotEmpty;
  int get loyaltyStamps => _loyaltyStamps;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _loadProfile() {
    _customerName = _localStorageService.getCustomerName() ?? '';
    _customerPhone = _localStorageService.getCustomerPhone() ?? '';
    _customerEmail = _localStorageService.getCustomerEmail() ?? '';
    _authToken = _localStorageService.getAuthToken() ?? '';
    _loyaltyStamps = _localStorageService.getLoyaltyStamps(_customerPhone);
    final savedUrl = _localStorageService.getCustomApiUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _apiUrl = savedUrl;
      _apiService.updateBaseUrl(savedUrl);
    } else {
      _apiUrl = AppConfig.defaultApiBaseUrl;
    }
    checkServerConnection();
    notifyListeners();
  }

  Future<bool> register({
    required String fullName,
    required String phone,
    String? email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiService.registerCustomer(
        fullName: fullName,
        phone: phone,
        email: email,
        password: password,
      );
      await _applyAuthResponse(response);
      _isLoading = false;
      notifyListeners();
      return true;
    } on HttpException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } on SocketException {
      return _registerLocally(
        fullName: fullName,
        phone: phone,
        email: email,
        password: password,
      );
    } on TimeoutException {
      return _registerLocally(
        fullName: fullName,
        phone: phone,
        email: email,
        password: password,
      );
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login({
    required String identifier,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiService.loginCustomer(
        identifier: identifier,
        password: password,
      );
      await _applyAuthResponse(response);
      _isLoading = false;
      notifyListeners();
      return true;
    } on HttpException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } on SocketException {
      return _loginLocally(identifier: identifier, password: password);
    } on TimeoutException {
      return _loginLocally(identifier: identifier, password: password);
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _applyAuthResponse(Map<String, dynamic> response) async {
    final token = (response['access_token'] as String?) ?? '';
    final userMap = (response['user'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final name = (userMap['full_name'] as String?) ?? '';
    final phone = (userMap['phone'] as String?) ?? '';
    final email = (userMap['email'] as String?) ?? '';
    final serverStamps = (userMap['loyalty_stamps'] as num?)?.toInt() ?? 0;

    _authToken = token;
    _customerName = name;
    _customerPhone = phone;
    _customerEmail = email;

    await _localStorageService.setAuthToken(token);
    await _localStorageService.setCustomerName(name);
    await _localStorageService.setCustomerPhone(phone);
    await _localStorageService.setCustomerEmail(email);

    final localStamps = _localStorageService.getLoyaltyStamps(phone);
    final mergedStamps = serverStamps > localStamps ? serverStamps : localStamps;
    await _localStorageService.setLoyaltyStamps(phone, mergedStamps);
    _loyaltyStamps = mergedStamps;
  }

  Future<bool> _registerLocally({
    required String fullName,
    required String phone,
    String? email,
    required String password,
  }) async {
    final accounts = _localStorageService.getLocalAccounts();
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final cleanEmail = (email ?? '').trim().toLowerCase();

    final exists = accounts.any((acc) {
      final accPhone = (acc['phone'] as String? ?? '').replaceAll(RegExp(r'\D'), '');
      final accEmail = (acc['email'] as String? ?? '').trim().toLowerCase();
      return accPhone == cleanPhone || (cleanEmail.isNotEmpty && accEmail == cleanEmail);
    });

    if (exists) {
      _errorMessage = 'An account with this phone or email already exists.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    final newAcc = <String, dynamic>{
      'full_name': fullName.trim(),
      'phone': phone.trim(),
      'email': cleanEmail,
      'password': password,
    };
    accounts.add(newAcc);
    await _localStorageService.saveLocalAccounts(accounts);

    _authToken = 'local_token_${DateTime.now().millisecondsSinceEpoch}';
    _customerName = fullName.trim();
    _customerPhone = phone.trim();
    _customerEmail = cleanEmail;

    await _localStorageService.setAuthToken(_authToken);
    await _localStorageService.setCustomerName(_customerName);
    await _localStorageService.setCustomerPhone(_customerPhone);
    await _localStorageService.setCustomerEmail(_customerEmail);
    _loyaltyStamps = _localStorageService.getLoyaltyStamps(_customerPhone);

    _isLoading = false;
    notifyListeners();
    return true;
  }

  Future<bool> _loginLocally({
    required String identifier,
    required String password,
  }) async {
    final accounts = _localStorageService.getLocalAccounts();
    final cleanId = identifier.trim().toLowerCase();
    final digitsId = identifier.replaceAll(RegExp(r'\D'), '');

    final matched = accounts.where((acc) {
      final accPhone = (acc['phone'] as String? ?? '').trim().toLowerCase();
      final accDigits = accPhone.replaceAll(RegExp(r'\D'), '');
      final accEmail = (acc['email'] as String? ?? '').trim().toLowerCase();
      final phoneMatch = accPhone == cleanId || (digitsId.isNotEmpty && accDigits == digitsId);
      final emailMatch = accEmail.isNotEmpty && accEmail == cleanId;
      return (phoneMatch || emailMatch) && acc['password'] == password;
    }).firstOrNull;

    if (matched == null) {
      _errorMessage = 'Invalid phone/email or password.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    _authToken = 'local_token_${DateTime.now().millisecondsSinceEpoch}';
    _customerName = (matched['full_name'] as String?) ?? '';
    _customerPhone = (matched['phone'] as String?) ?? '';
    _customerEmail = (matched['email'] as String?) ?? '';

    await _localStorageService.setAuthToken(_authToken);
    await _localStorageService.setCustomerName(_customerName);
    await _localStorageService.setCustomerPhone(_customerPhone);
    await _localStorageService.setCustomerEmail(_customerEmail);
    _loyaltyStamps = _localStorageService.getLoyaltyStamps(_customerPhone);

    _isLoading = false;
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    _authToken = '';
    _customerName = '';
    _customerPhone = '';
    _customerEmail = '';
    _loyaltyStamps = 0;
    _errorMessage = null;
    await _localStorageService.clearCustomerAuth();
    notifyListeners();
  }

  Future<void> saveProfile({
    required String name,
    required String phone,
    String? email,
  }) async {
    _customerName = name.trim();
    _customerPhone = phone.trim();
    if (email != null) {
      _customerEmail = email.trim();
      await _localStorageService.setCustomerEmail(_customerEmail);
    }
    await _localStorageService.setCustomerName(_customerName);
    await _localStorageService.setCustomerPhone(_customerPhone);
    _loyaltyStamps = _localStorageService.getLoyaltyStamps(_customerPhone);
    notifyListeners();
  }

  void refreshLoyaltyStamps() {
    _loyaltyStamps = _localStorageService.getLoyaltyStamps(_customerPhone);
    notifyListeners();
  }

  Future<void> addStampsForOrder(int drinksCount) async {
    if (_customerPhone.isEmpty || drinksCount <= 0) return;
    await _localStorageService.addLoyaltyStamps(_customerPhone, drinksCount);
    _loyaltyStamps = _localStorageService.getLoyaltyStamps(_customerPhone);
    notifyListeners();
  }

  Future<void> updateApiUrl(String newUrl) async {
    final clean = newUrl.trim();
    _apiUrl = clean;
    if (clean.isNotEmpty) {
      await _localStorageService.setCustomApiUrl(clean);
      _apiService.updateBaseUrl(clean);
    } else {
      await _localStorageService.clearCustomApiUrl();
      _apiService.updateBaseUrl(AppConfig.defaultApiBaseUrl);
    }
    await checkServerConnection();
    notifyListeners();
  }

  Future<void> checkServerConnection() async {
    _isServerOnline = await _apiService.checkHealth();
    notifyListeners();
  }
}
