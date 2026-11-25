import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool get isOnline => isOnlineNotifier.value;

  Future<void> init() async {
    try {
      final initial = await _connectivity.checkConnectivity();
      _updateStatus(initial);
      _subscription = _connectivity.onConnectivityChanged.listen(_updateStatus);
    } catch (e) {
      debugPrint('Connectivity init error: $e');
      isOnlineNotifier.value = true;
    }
  }

  void _updateStatus(List<ConnectivityResult> results) {
    final online = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
    isOnlineNotifier.value = online;
  }

  void dispose() {
    _subscription?.cancel();
  }
}
