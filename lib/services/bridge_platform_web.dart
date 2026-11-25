import 'bridge_platform_helper.dart';

BridgePlatform getBridgePlatform() => BridgePlatformWeb();

class BridgePlatformWeb implements BridgePlatform {
  @override
  Future<bool> startServer({
    required int port,
    required Future<Map<String, dynamic>> Function(String path, String method, String body) onRequest,
  }) async => false;

  @override
  Future<String?> scanMaster(int port) async => null;

  @override
  Future<bool> postStatus({
    required String ip,
    required int port,
    required String orderId,
    required String newStatus,
  }) async => false;

  @override
  Future<List<Map<String, dynamic>>?> getOrders({
    required String ip,
    required int port,
  }) async => null;

  @override
  Future<void> startUdpBeacon({
    required int port,
    required String message,
  }) async {}

  @override
  void stopUdpBeacon() {}

  @override
  Future<void> listenUdpBeacon({
    required int port,
    required void Function(String masterIp, int masterPort, String storeName) onMasterFound,
  }) async {}

  @override
  void stopListeningUdpBeacon() {}

  @override
  Future<String?> getLocalIp() async => null;
}
