import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:dinner_duck/services/persistence_service.dart';
import 'package:dinner_duck/models/recipe.dart';
import 'package:flutter/foundation.dart';

/// The Quack Service handles mDNS (Bonsoir) broadcasting and discovery,
/// as well as the local shelf server for sharing shredded app data.
/// Uses a static port (8080) and a 5-second discovery heartbeat.
class QuackService {
  static final QuackService _instance = QuackService._internal();
  factory QuackService() => _instance;
  QuackService._internal();

  static const String _serviceType = '_dinnerduck._tcp';
  // Static port with a fallback to 0 (random) if 8080 is in use.
  static const int _preferredPort = 8080;

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  HttpServer? _server;
  final PersistenceService _persistenceService = PersistenceService();
  final NetworkInfo _networkInfo = NetworkInfo();

  bool _isQuacking = false;
  bool get isQuacking => _isQuacking;

  bool _isLiveExcellent = false;
  bool get isLiveExcellent => _isLiveExcellent;

  String? _pairedHost;
  int? _pairedPort;
  String? _serviceName;

  final _breadController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<bool>.broadcast();
  final _timerController = StreamController<int>.broadcast();
  Stream<bool> get statusStream => _statusController.stream;
  Stream<int> get timerStream => _timerController.stream;

  Timer? _liveSyncTimer;
  Timer? _countdownTimer;
  Timer? _discoveryHeartbeat;
  int _remainingSeconds = 0;

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Starts the local server + immediately begins mDNS broadcast & discovery.
  Future<void> startQuacking({
    required String quackCode,
    required Function(Map<String, dynamic> data) onDataReceived,
    required VoidCallback onSyncExcellent,
    required Function(String host, int port, String deviceName) onDeviceFound,
  }) async {
    if (_isQuacking) return;
    _isQuacking = true;

    // 1. Start the server first
    await _startServer(onDataReceived, onSyncExcellent);
    if (_server == null) {
      _isQuacking = false;
      return;
    }

    // 2. Broadcast + discover immediately (no waiting on QR or anything else)
    await _startBroadcast(quackCode);
    await _startDiscovery(quackCode, onDeviceFound);

    // 3. mDNS heartbeat — re-runs discovery every 5s if it stops or errors
    _discoveryHeartbeat = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_isQuacking || _isLiveExcellent) return;
      if (_discovery == null) {
        debugPrint('[Heartbeat] Discovery is null — restarting...');
        await _startDiscovery(quackCode, onDeviceFound);
      }
    });
  }

  Future<void> stopQuacking() async {
    _isQuacking = false;
    _isLiveExcellent = false;
    _statusController.add(false);
    _liveSyncTimer?.cancel();
    _countdownTimer?.cancel();
    _discoveryHeartbeat?.cancel();
    _discoveryHeartbeat = null;
    _remainingSeconds = 0;
    _timerController.add(0);
    _pairedHost = null;
    _pairedPort = null;
    _serviceName = null;
    await _server?.close(force: true);
    _server = null;
    await _broadcast?.stop();
    _broadcast = null;
    await _discovery?.stop();
    _discovery = null;
  }

  /// Pushes local updates as "Bread" to all listeners (SSE + REST back-link).
  void pushBread(Map<String, dynamic> data) async {
    if (!_isLiveExcellent) return;

    final shreddedMap = _prepareShreddedMap(data);
    _breadController.add(shreddedMap);

    if (_pairedHost != null && _pairedPort != null) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 5);
        final uri = Uri.parse('http://$_pairedHost:$_pairedPort/bread');
        final request = await client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(shreddedMap));
        await request.close();
        client.close();
      } catch (e) {
        debugPrint('[QuackService] Failed to REST push bread: $e');
      }
    }
  }

  Future<void> syncDevice(
    String host,
    int port,
    Function(Map<String, dynamic>) onDataReceived,
    VoidCallback onSyncExcellent,
  ) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      final request =
          await client.getUrl(Uri.parse('http://$host:$port/shredded-data'));
      final response = await request.close();

      if (response.statusCode == HttpStatus.ok) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        onDataReceived(data);

        final handshakeRequest =
            await client.postUrl(Uri.parse('http://$host:$port/handshake'));
        await handshakeRequest.close();

        _pairedHost = host;
        _pairedPort = port;
        _listenForBread(host, port, onDataReceived);

        _startLiveWindow();
        onSyncExcellent();
      }
      client.close();
    } catch (e) {
      debugPrint('[QuackService] Sync with peer at $host failed: $e');
    }
  }

  /// Returns the WiFi URL for QR-based shredded data sync.
  Future<String?> getSyncUrl() async {
    if (_server == null) return null;
    final ip = await _networkInfo.getWifiIP();
    if (ip == null || ip.isEmpty) {
      return 'http://10.0.2.2:${_server!.port}/shredded-data';
    }
    return 'http://$ip:${_server!.port}/shredded-data';
  }

  Future<void> manualSync(
    String url,
    Function(Map<String, dynamic>) onDataReceived,
    VoidCallback onSyncExcellent,
  ) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        final body = await response.transform(utf8.decoder).join();
        onDataReceived(jsonDecode(body));

        final uri = Uri.parse(url);
        final handshakeRequest = await client.postUrl(
            Uri.parse('${uri.scheme}://${uri.host}:${uri.port}/handshake'));
        await handshakeRequest.close();

        _pairedHost = uri.host;
        _pairedPort = uri.port;
        _listenForBread(uri.host, uri.port, onDataReceived);
        _startLiveWindow();
        onSyncExcellent();
      }
      client.close();
    } catch (e) {
      debugPrint('[QuackService] Manual sync failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _startServer(
    Function(Map<String, dynamic>) onReceived,
    VoidCallback onExcellent,
  ) async {
    final router = Router();

    router.get('/shredded-data', (Request request) async {
      final allData = await _persistenceService.loadAllData();
      return Response.ok(
        jsonEncode(_prepareShreddedMap(allData)),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/handshake', (Request request) async {
      debugPrint('[QuackService] Handshake received — starting live window.');
      _startLiveWindow();
      onExcellent();
      return Response.ok('Excellent Handshake');
    });

    router.get('/bread-stream', (Request request) {
      final stream = _breadController.stream.map((data) {
        return utf8.encode('data: ${jsonEncode(data)}\n\n');
      });
      return Response.ok(stream, headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
      });
    });

    router.post('/bread', (Request request) async {
      final body = await request.readAsString();
      try {
        final data = jsonDecode(body) as Map<String, dynamic>;
        onReceived(data);
        return Response.ok('Bread Quacked');
      } catch (e) {
        debugPrint('[QuackService] Error decoding bread POST: $e');
        return Response.internalServerError();
      }
    });

    // Try preferred static port first, fall back to random
    try {
      _server =
          await io.serve(router.call, InternetAddress.anyIPv4, _preferredPort);
      debugPrint('[QuackService] Server on static port ${_server!.port}');
    } catch (_) {
      try {
        _server = await io.serve(router.call, InternetAddress.anyIPv4, 0);
        debugPrint('[QuackService] Static port busy — using ${_server!.port}');
      } catch (e) {
        debugPrint('[QuackService] Failed to start server: $e');
      }
    }
  }

  Future<void> _startBroadcast(String quackCode) async {
    final String uid = '${DateTime.now().millisecondsSinceEpoch % 1000}';
    _serviceName = 'Duck-$quackCode-$uid';

    try {
      final broadcastService = BonsoirService(
        name: _serviceName!,
        type: _serviceType,
        port: _server!.port,
      );
      _broadcast = BonsoirBroadcast(service: broadcastService);
      await _broadcast!.initialize();
      await _broadcast!.start();
      debugPrint('[QuackService] Broadcasting as $_serviceName on port ${_server!.port}');
    } catch (e) {
      debugPrint('[QuackService] Broadcast failed: $e');
    }
  }

  Future<void> _startDiscovery(
    String quackCode,
    Function(String, int, String) onDeviceFound,
  ) async {
    // Clean up previous discovery before restarting
    if (_discovery != null) {
      try {
        await _discovery!.stop();
      } catch (_) {}
      _discovery = null;
    }

    try {
      _discovery = BonsoirDiscovery(type: _serviceType);
      await _discovery!.initialize();

      _discovery!.eventStream!.listen(
        (event) {
          if (event is BonsoirDiscoveryServiceFoundEvent) {
            event.service.resolve(_discovery!.serviceResolver);
          } else if (event is BonsoirDiscoveryServiceResolvedEvent) {
            final resolved = event.service;
            // Skip self
            if (resolved.name == _serviceName) return;
            // Quack Code filter
            if (!resolved.name.startsWith('Duck-$quackCode-')) return;

            final host = resolved.toJson()['host'] as String? ?? resolved.name;
            final port = resolved.port;
            debugPrint('[QuackService] Peer found: ${resolved.name} @ $host:$port');
            onDeviceFound(host, port, 'Companion Duck');
          }
        },
        onError: (e) {
          debugPrint('[QuackService] Discovery error: $e — heartbeat will retry.');
          _discovery = null; // Heartbeat will restart it
        },
        onDone: () {
          debugPrint('[QuackService] Discovery stream done — heartbeat will retry.');
          _discovery = null; // Heartbeat will restart it
        },
        cancelOnError: false,
      );

      await _discovery!.start();
      debugPrint('[QuackService] Discovery started for code $quackCode');
    } catch (e) {
      debugPrint('[QuackService] Failed to start discovery: $e');
      _discovery = null;
    }
  }

  Map<String, dynamic> _prepareShreddedMap(Map<String, dynamic> allData) {
    return {
      'mealPlans': (allData['mealPlans'] as List)
          .map((e) => e is Recipe ? e.toJson() : e)
          .toList(),
      'cookbook': (allData['cookbook'] as List)
          .map((e) => e is Recipe ? e.toJson() : e)
          .toList(),
      'groceryList': allData['groceryList'],
      'staples': allData['staples'],
      'categoryOrder': allData['categoryOrder'],
      'purchaseHistory': allData['purchaseHistory'],
      'checkedItems': allData['checkedItems'],
    };
  }

  void _startLiveWindow() {
    _isLiveExcellent = true;
    _statusController.add(true);
    _liveSyncTimer?.cancel();
    _countdownTimer?.cancel();
    _discoveryHeartbeat?.cancel(); // Stop searching once paired

    _remainingSeconds = 60 * 60;
    _timerController.add(_remainingSeconds);

    _countdownTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        _timerController.add(_remainingSeconds);
      } else {
        timer.cancel();
      }
    });

    _liveSyncTimer = Timer(const Duration(minutes: 60), () {
      _isLiveExcellent = false;
      _statusController.add(false);
      _countdownTimer?.cancel();
      _remainingSeconds = 0;
      _timerController.add(0);
      _pairedHost = null;
      _pairedPort = null;
      debugPrint('[QuackService] Live Duck window closed after 60 minutes.');
    });
  }

  void _listenForBread(
    String host,
    int port,
    Function(Map<String, dynamic>) onDataReceived,
  ) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final request = await client
          .getUrl(Uri.parse('http://$host:$port/bread-stream'));
      final response = await request.close();

      response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('data: ')) {
            try {
              final data =
                  jsonDecode(line.substring(6).trim()) as Map<String, dynamic>;
              onDataReceived(data);
            } catch (e) {
              debugPrint('[QuackService] Error decoding SSE bread: $e');
            }
          }
        },
        onDone: () {
          debugPrint('[QuackService] Bread stream closed.');
          client.close();
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[QuackService] Failed to listen for bread: $e');
    }
  }
}
