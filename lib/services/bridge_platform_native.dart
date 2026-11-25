import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'bridge_platform_helper.dart';

BridgePlatform getBridgePlatform() => BridgePlatformNative();

class BridgePlatformNative implements BridgePlatform {
  dynamic _server;
  RawDatagramSocket? _beaconSocket;
  Timer? _beaconTimer;
  RawDatagramSocket? _listenerSocket;

  @override
  Future<bool> startServer({
    required int port,
    required Future<Map<String, dynamic>> Function(String path, String method, String body) onRequest,
  }) async {
    if (_server != null) return true;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      debugPrint('[BridgePlatformNative] Master HTTP Server running on port $port');

      _server.listen((HttpRequest request) async {
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        final method = request.method;

        String body = '';
        if (method == 'POST' || method == 'PUT') {
          body = await utf8.decodeStream(request);
        }

        try {
          // Pass full path with query if present
          final fullPath = request.uri.hasQuery ? '${request.uri.path}?${request.uri.query}' : request.uri.path;
          final res = await onRequest(fullPath, method, body);
          final statusCode = res['statusCode'] as int? ?? HttpStatus.ok;
          final contentType = res['contentType'] as String? ?? 'application/json';

          request.response.statusCode = statusCode;
          if (contentType == 'text/html') {
            request.response.headers.contentType = ContentType.html;
            request.response.write(res['data']?.toString() ?? '');
          } else {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode(res['data']));
          }
        } catch (e) {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'error': e.toString()}));
        } finally {
          await request.response.close();
        }
      });

      return true;
    } catch (e) {
      debugPrint('[BridgePlatformNative] Start server error: $e');
      return false;
    }
  }

  @override
  Future<String?> scanMaster(int port) async {
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

      final List<Future<String?>> pingTasks = [];
      for (int i = 1; i <= 254; i++) {
        final ip = '$localSubnet.$i';
        pingTasks.add(() async {
          try {
            final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 300));
            socket.destroy();

            final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 600);
            final req = await client.getUrl(Uri.parse('http://$ip:$port/ping'));
            final resp = await req.close();
            if (resp.statusCode == 200) {
              final body = await utf8.decodeStream(resp);
              final map = jsonDecode(body);
              if (map['role'] == 'master_cashier') {
                return ip;
              }
            }
          } catch (_) {}
          return null;
        }());
      }

      final results = await Future.wait(pingTasks);
      return results.firstWhere((ip) => ip != null, orElse: () => null);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> postStatus({
    required String ip,
    required int port,
    required String orderId,
    required String newStatus,
  }) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client.postUrl(Uri.parse('http://$ip:$port/orders/status'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'orderId': orderId, 'status': newStatus}));
      final resp = await req.close();
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<Map<String, dynamic>>?> getOrders({
    required String ip,
    required int port,
  }) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client.getUrl(Uri.parse('http://$ip:$port/orders'));
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final body = await utf8.decodeStream(resp);
        final list = jsonDecode(body);
        if (list is List) {
          return list.cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> startUdpBeacon({
    required int port,
    required String message,
  }) async {
    stopUdpBeacon();
    try {
      _beaconSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _beaconSocket?.broadcastEnabled = true;
      final bytes = utf8.encode(message);

      _beaconTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        try {
          _beaconSocket?.send(bytes, InternetAddress('255.255.255.255'), port);
        } catch (_) {}
      });
      debugPrint('[BridgePlatformNative] UDP Beacon broadcasting on port $port');
    } catch (e) {
      debugPrint('[BridgePlatformNative] UDP Beacon error: $e');
    }
  }

  @override
  void stopUdpBeacon() {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _beaconSocket?.close();
    _beaconSocket = null;
  }

  @override
  Future<void> listenUdpBeacon({
    required int port,
    required void Function(String masterIp, int masterPort, String storeName) onMasterFound,
  }) async {
    try {
      _listenerSocket?.close();
      _listenerSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
      _listenerSocket?.broadcastEnabled = true;
      _listenerSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _listenerSocket?.receive();
          if (datagram != null) {
            final text = utf8.decode(datagram.data);
            if (text.startsWith('NUSANTARA_POS_MASTER|')) {
              final parts = text.split('|');
              final pPort = parts.length > 1 ? int.tryParse(parts[1]) ?? 8765 : 8765;
              final store = parts.length > 2 ? parts[2] : 'Nusantara POS';
              onMasterFound(datagram.address.address, pPort, store);
            }
          }
        }
      });
      debugPrint('[BridgePlatformNative] Listening for UDP Beacon on port $port');
    } catch (e) {
      debugPrint('[BridgePlatformNative] UDP Beacon listener error: $e');
    }
  }

  @override
  void stopListeningUdpBeacon() {
    _listenerSocket?.close();
    _listenerSocket = null;
  }

  @override
  Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && (addr.address.startsWith('192.168.') || addr.address.startsWith('10.'))) {
            return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }
}
