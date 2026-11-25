import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum AppCurrency {
  szl('SZL', 'E', 18.50, 2, false),
  zar('ZAR', 'R', 18.50, 2, false),
  usd('USD', '\$', 1.00, 2, false),
  btc('BTC', '₿', 0.000011, 6, true),
  eth('ETH', 'Ξ', 0.00037, 5, true);

  final String code;
  final String symbol;
  final double rateFromUsd; // 1 USD = rateFromUsd of this currency
  final int decimals;
  final bool isCrypto;

  const AppCurrency(
    this.code,
    this.symbol,
    this.rateFromUsd,
    this.decimals,
    this.isCrypto,
  );
}

class CurrencyService extends ChangeNotifier {
  static const String _storageKey = 'barnock_preferred_currency';
  AppCurrency _currentCurrency = AppCurrency.szl; // Default to SZL
  bool _isLoadingRates = false;
  DateTime? _lastRatesUpdated;

  final Map<AppCurrency, double> _dynamicRates = {
    for (final c in AppCurrency.values) c: c.rateFromUsd,
  };

  CurrencyService() {
    _loadCurrency();
    fetchLiveRates();
  }

  AppCurrency get currentCurrency => _currentCurrency;
  bool get isLoadingRates => _isLoadingRates;
  DateTime? get lastRatesUpdated => _lastRatesUpdated;

  Future<void> _loadCurrency() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString(_storageKey);
      if (savedCode != null) {
        _currentCurrency = AppCurrency.values.firstWhere(
          (c) => c.code == savedCode,
          orElse: () => AppCurrency.szl,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading preferred currency: $e');
    }
  }

  Future<void> setCurrency(AppCurrency currency) async {
    if (_currentCurrency == currency) return;
    _currentCurrency = currency;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, currency.code);
    } catch (e) {
      debugPrint('Error saving preferred currency: $e');
    }
  }

  double getRate(AppCurrency currency) =>
      _dynamicRates[currency] ?? currency.rateFromUsd;

  Future<void> fetchLiveRates() async {
    _isLoadingRates = true;
    notifyListeners();

    // 1. Fetch Fiat rates (SZL, ZAR) from Open Exchange Rates API
    try {
      final fiatUri = Uri.parse('https://open.er-api.com/v6/latest/USD');
      final response =
          await http.get(fiatUri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rates = data['rates'] as Map<String, dynamic>?;
        if (rates != null) {
          final zarRate = (rates['ZAR'] as num?)?.toDouble();
          final szlRate = (rates['SZL'] as num?)?.toDouble() ?? zarRate;
          if (szlRate != null) _dynamicRates[AppCurrency.szl] = szlRate;
          if (zarRate != null) _dynamicRates[AppCurrency.zar] = zarRate;
        }
      }
    } catch (e) {
      debugPrint('Error fetching fiat exchange rates: $e');
    }

    // 2. Fetch Crypto rates (BTC, ETH in USD) from CoinGecko Public API
    try {
      final cryptoUri = Uri.parse(
        'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd',
      );
      final response =
          await http.get(cryptoUri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final btcUsd = (data['bitcoin']?['usd'] as num?)?.toDouble();
        final ethUsd = (data['ethereum']?['usd'] as num?)?.toDouble();

        if (btcUsd != null && btcUsd > 0) {
          _dynamicRates[AppCurrency.btc] = 1.0 / btcUsd;
        }
        if (ethUsd != null && ethUsd > 0) {
          _dynamicRates[AppCurrency.eth] = 1.0 / ethUsd;
        }
      }
    } catch (e) {
      debugPrint('Error fetching crypto exchange rates: $e');
    }

    _lastRatesUpdated = DateTime.now();
    _isLoadingRates = false;
    notifyListeners();
  }

  double convertFromUsd(double usdAmount) {
    return usdAmount * getRate(_currentCurrency);
  }

  String format(double usdAmount, [AppCurrency? specificCurrency]) {
    final curr = specificCurrency ?? _currentCurrency;
    final converted = usdAmount * getRate(curr);
    final formattedVal = converted.toStringAsFixed(curr.decimals);
    if (curr.isCrypto) {
      return '$formattedVal ${curr.symbol}';
    }
    return '${curr.symbol} $formattedVal';
  }

  /// Returns payment deposit instructions according to chosen currency
  Map<String, String> getPaymentDetails(AppCurrency currency) {
    switch (currency) {
      case AppCurrency.szl:
      case AppCurrency.zar:
        return {
          'method': 'Bank EFT (FNB Eswatini / Standard Bank)',
          'account': 'Account: 62894109823 | Branch: 280164 | Ref: Order-ID',
        };
      case AppCurrency.usd:
        return {
          'method': 'Credit Card / International Wire',
          'account': 'Stripe Gateway / SWIFT: BARNSZ22',
        };
      case AppCurrency.btc:
        return {
          'method': 'Bitcoin (BTC) Native SegWit',
          'account': 'bc1qbarnockhardware78xk9w3d2e0pqm4l56szt98g',
        };
      case AppCurrency.eth:
        return {
          'method': 'Ethereum (ETH / ERC-20)',
          'account': '0x71C8A97bB357F71dE434856E2a0D864F01d9B4E3',
        };
    }
  }
}