import 'network_printer_stub.dart'
    if (dart.library.io) 'network_printer_native.dart'
    if (dart.library.html) 'network_printer_web.dart';

abstract class NetworkPrinterPlatform {
  static NetworkPrinterPlatform get instance => getNetworkPrinterPlatform();

  Future<List<Map<String, dynamic>>> scanSubnet(int port);
  Future<bool> sendRawBytes(String ip, int port, List<int> bytes);
}
