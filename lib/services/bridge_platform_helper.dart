import 'bridge_platform_stub.dart'
    if (dart.library.io) 'bridge_platform_native.dart'
    if (dart.library.html) 'bridge_platform_web.dart';

abstract class BridgePlatform {
  static BridgePlatform get instance => getBridgePlatform();

  Future<bool> startServer({
    required int port,
    required Future<Map<String, dynamic>> Function(String path, String method, String body) onRequest,
  });

  Future<String?> scanMaster(int port);

  Future<bool> postStatus({
    required String ip,
    required int port,
    required String orderId,
    required String newStatus,
  });

  Future<List<Map<String, dynamic>>?> getOrders({
    required String ip,
    required int port,
  });

  Future<void> startUdpBeacon({
    required int port,
    required String message,
  });

  void stopUdpBeacon();

  Future<void> listenUdpBeacon({
    required int port,
    required void Function(String masterIp, int masterPort, String storeName) onMasterFound,
  });

  void stopListeningUdpBeacon();

  Future<String?> getLocalIp();
}
