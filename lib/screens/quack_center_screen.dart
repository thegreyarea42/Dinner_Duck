import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:ndef_record/ndef_record.dart';
import 'package:dinner_duck/main.dart';
import 'package:dinner_duck/services/quack_service.dart';

/// The Quack Center handles device-to-device synchronization.
///
/// Connection priority:
///   1. QR Code  — Device A shows QR, Device B scans it  (most reliable)
///   2. NFC      — Devices tap together to share the URL  (fast fallback)
///   3. mDNS     — Automatic discovery if on same network (background bonus)
class QuackCenterScreen extends StatefulWidget {
  final String quackCode;
  final Function(String) onQuackCodeChanged;
  final Function(Map<String, dynamic>) onDataReceived;

  const QuackCenterScreen({
    super.key,
    required this.quackCode,
    required this.onQuackCodeChanged,
    required this.onDataReceived,
  });

  @override
  State<QuackCenterScreen> createState() => _QuackCenterScreenState();
}

class _QuackCenterScreenState extends State<QuackCenterScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final QuackService _quackService = QuackService();

  // Possible views: 'loading', 'ready', 'scanning'
  String _viewState = 'loading';
  String? _mySyncUrl;
  bool _nfcAvailable = false;
  bool _nfcSharing = false;
  bool _isSyncing = false;

  static const Color deepGreen = Color(0xFF064E40);
  static const Color creamOrange = Color(0xFFFFCC99);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    NfcManager.instance.stopSession().catchError((_) {});
    // Don't stop quacking — keeps the live window open after leaving
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Initialization — starts server immediately, shows QR ASAP
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initialize() async {
    // 1. Start the server + mDNS discovery in the background immediately
    _quackService.startQuacking(
      quackCode: widget.quackCode,
      onDataReceived: widget.onDataReceived,
      onSyncExcellent: () {
        if (mounted) _showSuccessOverlay();
      },
      onDeviceFound: (host, port, deviceName) {
        // mDNS auto-found a peer — show confirmation dialog instantly
        _onDeviceFound(host, port, deviceName);
      },
    );

    // 2. Get our URL (server already started above)
    // Poll briefly since server start is async
    for (int i = 0; i < 10; i++) {
      _mySyncUrl = await _quackService.getSyncUrl();
      if (_mySyncUrl != null) break;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // 3. Check NFC availability
    try {
      final availability = await NfcManager.instance.checkAvailability();
      _nfcAvailable = availability == NfcAvailability.enabled;
    } catch (_) {
      _nfcAvailable = false;
    }

    if (mounted) {
      setState(() => _viewState = 'ready');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NFC Share — writes the sync URL as an NDEF record
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _startNfcShare() async {
    if (_mySyncUrl == null || !_nfcAvailable) return;
    setState(() => _nfcSharing = true);

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (NfcTag tag) async {
          try {
            final ndef = NdefAndroid.from(tag);
            if (ndef == null || !ndef.isWritable) {
              _showSnack('NFC tag is not writable or not NDEF.');
              await NfcManager.instance.stopSession();
              return;
            }
            final message = NdefMessage(records: [
              NdefRecord(
                typeNameFormat: TypeNameFormat.wellKnown,
                type: Uint8List.fromList([0x55]), // 'U'
                identifier: Uint8List(0),
                payload: Uint8List.fromList([0x00, ...utf8.encode(_mySyncUrl!)]),
              ),
            ]);
            await ndef.writeNdefMessage(message);
            await NfcManager.instance.stopSession();
            if (mounted) {
              _showSnack('Sync URL written! Let the other device tap to read.');
            }
          } catch (e) {
            await NfcManager.instance.stopSession();
            if (mounted) _showSnack('NFC write failed: $e');
          } finally {
            if (mounted) setState(() => _nfcSharing = false);
          }
        },
      );
    } catch (e) {
      _showSnack('NFC error: $e');
      setState(() => _nfcSharing = false);
    }
  }

  Future<void> _startNfcRead() async {
    if (!_nfcAvailable) return;
    setState(() => _nfcSharing = true);
    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (NfcTag tag) async {
          try {
            final ndef = NdefAndroid.from(tag);
            if (ndef == null) {
              await NfcManager.instance.stopSession();
              return;
            }
            final cachedMessage = ndef.cachedNdefMessage;
            if (cachedMessage == null || cachedMessage.records.isEmpty) {
              await NfcManager.instance.stopSession();
              return;
            }
            final record = cachedMessage.records.first;
            // NDEF URI record: first byte is the prefix code, rest is the URI
            final payload = record.payload;
            final prefixCode = payload[0];
            const prefixes = [
              '', 'http://www.', 'https://www.', 'http://', 'https://',
              'tel:', 'mailto:', 'ftp://anonymous:anonymous@', 'ftp://ftp.',
              'ftps://', 'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://',
              'news:', 'telnet://', 'imap:', 'rtsp://', 'urn:', 'pop:',
              'sip:', 'sips:', 'tftp:', 'btspp://', 'btl2cap://', 'btgoep://',
              'tcpobex://', 'irdaobex://', 'file://', 'urn:epc:id:',
              'urn:epc:tag:', 'urn:epc:pat:', 'urn:epc:raw:', 'urn:epc:',
              'urn:nfc:',
            ];
            final prefix = prefixCode < prefixes.length ? prefixes[prefixCode] : '';
            final uriBody = String.fromCharCodes(payload.skip(1));
            final url = '$prefix$uriBody';
            await NfcManager.instance.stopSession();
            if (mounted) {
              setState(() => _nfcSharing = false);
              await _connectToUrl(url);
            }
          } catch (e) {
            await NfcManager.instance.stopSession();
            if (mounted) _showSnack('NFC read failed: $e');
          } finally {
            if (mounted) setState(() => _nfcSharing = false);
          }
        },
      );
    } catch (e) {
      _showSnack('NFC error: $e');
      setState(() => _nfcSharing = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Syncing logic
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _connectToUrl(String url) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      await _quackService.manualSync(url, widget.onDataReceived, () async {
        await HapticFeedback.lightImpact();
        if (mounted) _showSuccessOverlay();
      });
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _onDeviceFound(String host, int port, String deviceName) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: deepGreen,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: creamOrange, width: 2),
        ),
        title: const Text(
          'Duck Detected!',
          style: TextStyle(
              color: creamOrange,
              fontWeight: FontWeight.bold,
              fontSize: 20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flutter_dash, color: creamOrange, size: 52),
            const SizedBox(height: 12),
            Text(
              'A shredded duck with code "${widget.quackCode}" was found. Eat bread together?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, height: 1.4),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        actions: [
          SizedBox(
            height: 48,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white60,
                minimumSize: const Size(48, 48),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Stay Silent',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: creamOrange,
                foregroundColor: deepGreen,
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _quackService.syncDevice(
                  host,
                  port,
                  widget.onDataReceived,
                  () async {
                    await HapticFeedback.lightImpact();
                    if (mounted) _showSuccessOverlay();
                  },
                );
              },
              child: const Text('Eat Bread!',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // QR scanning
  // ─────────────────────────────────────────────────────────────────────────

  void _scanQRCode() async {
    setState(() => _viewState = 'scanning');
  }

  void _onQrScanned(String url) async {
    setState(() => _viewState = 'ready');
    await _connectToUrl(url);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Success overlay
  // ─────────────────────────────────────────────────────────────────────────

  void _showSuccessOverlay() {
    OverlayEntry? entry;
    Timer? dismissTimer;

    void dismiss() {
      dismissTimer?.cancel();
      if (entry != null) {
        entry!.remove();
        entry = null;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DinnerDuckApp()),
          (route) => false,
        );
      }
    }

    entry = OverlayEntry(
      builder: (_) => GestureDetector(
        onTap: dismiss,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.4),
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (context, value, child) => Transform.scale(
                scale: value,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(36),
                    decoration: BoxDecoration(
                      color: deepGreen.withValues(alpha: 0.97),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: creamOrange, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 28,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: creamOrange, size: 100),
                        SizedBox(height: 20),
                        Text(
                          'Excellent',
                          style: TextStyle(
                            color: creamOrange,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'SHREDDED SYNC COMPLETE!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry!);
    dismissTimer = Timer(const Duration(seconds: 5), dismiss);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: deepGreen,
      appBar: AppBar(
        title: const Text(
          'Quack Center',
          style: TextStyle(color: creamOrange, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: creamOrange),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_viewState) {
      case 'scanning':
        return _buildScannerView();
      case 'loading':
        return _buildLoadingView();
      default:
        return _buildReadyView();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Views
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: creamOrange),
          SizedBox(height: 20),
          Text(
            'Starting shredded server...',
            style: TextStyle(color: creamOrange, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildReadyView() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Section A: My code + QR ─────────────────────────────────
            _sectionHeader('Device A — Show this QR', Icons.qr_code),
            const SizedBox(height: 4),
            Text(
              'Code: ${widget.quackCode}   •   Open Quack Center on both devices',
              style: TextStyle(
                color: creamOrange.withValues(alpha: 0.65),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_mySyncUrl != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: _mySyncUrl!,
                  version: QrVersions.auto,
                  size: 200,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: deepGreen,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: deepGreen,
                  ),
                ),
              )
            else
              Container(
                height: 200,
                width: 200,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: creamOrange, width: 1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                        color: creamOrange, strokeWidth: 2),
                    const SizedBox(height: 12),
                    Text(
                      'Getting network URL...',
                      style: TextStyle(
                          color: creamOrange.withValues(alpha: 0.7),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // ── Section B: Scan ─────────────────────────────────────────
            _sectionHeader('Device B — Scan the QR', Icons.qr_code_scanner),
            const SizedBox(height: 12),
            if (_isSyncing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: creamOrange),
                    SizedBox(height: 12),
                    Text(
                      'Connecting...',
                      style: TextStyle(color: creamOrange, fontSize: 14),
                    ),
                  ],
                ),
              )
            else
              _wideButton(
                label: 'Scan Companion QR',
                icon: Icons.camera_alt,
                filled: true,
                onPressed: _scanQRCode,
              ),

            const SizedBox(height: 24),

            // ── Section C: NFC ──────────────────────────────────────────
            if (_nfcAvailable) ...[
              _sectionHeader('NFC — Tap to Connect', Icons.nfc),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _wideButton(
                      label: _nfcSharing ? 'Tap now...' : 'Share via NFC',
                      icon: Icons.upload,
                      filled: false,
                      onPressed: _nfcSharing ? null : _startNfcShare,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _wideButton(
                      label: 'Read NFC',
                      icon: Icons.download,
                      filled: false,
                      onPressed: _nfcSharing ? null : _startNfcRead,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Device A taps "Share", Device B taps "Read", then hold phones together.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: creamOrange.withValues(alpha: 0.55),
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── Section D: mDNS status ───────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: creamOrange.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  ScaleTransition(
                    scale:
                        Tween(begin: 0.8, end: 1.0).animate(_pulseController),
                    child: const Icon(Icons.wifi_tethering,
                        color: creamOrange, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Auto-detecting nearby ducks with code "${widget.quackCode}"...',
                      style: TextStyle(
                        color: creamOrange.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final code = barcode.rawValue;
              if (code != null) {
                _onQrScanned(code);
                break;
              }
            }
          },
        ),
        Positioned(
          top: 16,
          left: 16,
          child: SafeArea(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: deepGreen.withValues(alpha: 0.85),
                foregroundColor: creamOrange,
              ),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
              onPressed: () => setState(() => _viewState = 'ready'),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: creamOrange, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: deepGreen.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Aim at the QR code on the companion device',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: creamOrange,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: creamOrange, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: creamOrange,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Divider(
                color: creamOrange.withValues(alpha: 0.3), thickness: 1)),
      ],
    );
  }

  Widget _wideButton({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              filled ? creamOrange : creamOrange.withValues(alpha: 0.12),
          foregroundColor: filled ? deepGreen : creamOrange,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
          disabledForegroundColor: creamOrange.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: filled ? 2 : 0,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14)),
      ),
    );
  }
}
