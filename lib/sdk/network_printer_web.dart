import 'network_printer_helper.dart';

NetworkPrinterPlatform getNetworkPrinterPlatform() => NetworkPrinterWeb();

class NetworkPrinterWeb implements NetworkPrinterPlatform {
  @override
  Future<List<Map<String, dynamic>>> scanSubnet(int port) async => [];

  @override
  Future<bool> sendRawBytes(String ip, int port, List<int> bytes) async => false;
}
