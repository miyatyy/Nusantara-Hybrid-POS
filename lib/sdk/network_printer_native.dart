import 'dart:io';
import 'network_printer_helper.dart';

NetworkPrinterPlatform getNetworkPrinterPlatform() => NetworkPrinterNative();

class NetworkPrinterNative implements NetworkPrinterPlatform {
  @override
  Future<List<Map<String, dynamic>>> scanSubnet(int port) async {
    final List<Map<String, dynamic>> discovered = [];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      String? localSubnet;
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && (addr.address.startsWith('192.168.') || addr.address.startsWith('10.'))) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              localSubnet = '${parts[0]}.${parts[1]}.${parts[2]}';
              break;
            }
          }
        }
        if (localSubnet != null) break;
      }
      localSubnet ??= '192.168.1';

      final List<Future<Map<String, dynamic>?>> sweepTasks = [];
      for (int i = 1; i <= 254; i++) {
        final ip = '$localSubnet.$i';
        sweepTasks.add(() async {
          final sw = Stopwatch()..start();
          try {
            final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 350));
            socket.destroy();
            sw.stop();
            return {
              'ip': ip,
              'port': port,
              'latencyMs': sw.elapsedMilliseconds,
            };
          } catch (_) {
            return null;
          }
        }());
      }

      final results = await Future.wait(sweepTasks);
      for (final r in results) {
        if (r != null) discovered.add(r);
      }
    } catch (_) {}
    return discovered;
  }

  @override
  Future<bool> sendRawBytes(String ip, int port, List<int> bytes) async {
    try {
      final socket = await Socket.connect(ip.trim(), port, timeout: const Duration(seconds: 2));
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
