import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dinner_duck/services/quack_service.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter_tts/flutter_tts.dart';

class QuackPondScreen extends StatefulWidget {
  final Function(Map<String, dynamic>) onDataReceived;

  const QuackPondScreen({super.key, required this.onDataReceived});

  @override
  State<QuackPondScreen> createState() => _QuackPondScreenState();
}

class _QuackPondScreenState extends State<QuackPondScreen> with SingleTickerProviderStateMixin {
  late AnimationController _waveController;
  final QuackService _quackService = QuackService();
  bool _isSearching = false;
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _waveController.dispose();
    _quackService.stopQuacking();
    super.dispose();
  }

  Future<void> _playQuack() async {
    try {
      await _flutterTts.setPitch(2.0);
      await _flutterTts.setSpeechRate(1.0);
      await _flutterTts.speak("Quack!");
    } catch (e) {
      // Ignore audio errors
    }
  }

  void _onQuack() async {
    setState(() => _isSearching = true);
    _waveController.repeat();
    _playQuack();
    
    await _quackService.startQuacking(
      quackCode: '0000',
      onDataReceived: (shreddedData) {
        widget.onDataReceived(shreddedData);
      },
      onSyncExcellent: () {
        // Handled in _executeSync
      },
      onDeviceFound: (host, port, deviceName) {
        _onDeviceFound(host, port, deviceName);
      },
    );
  }

  void _onDeviceFound(String host, int port, String deviceName) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF002B21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.orange, width: 2)),
        title: const Text("Duck Detected!", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        content: Text("Sync with $deviceName?", style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white60, minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.pop(context),
            child: const Text("Stay Silent"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: const Color(0xFF002B21),
              minimumSize: const Size(48, 48),
            ),
            onPressed: () {
              Navigator.pop(context);
              _executeSync(host, port);
            },
            child: const Text("Quack Back"),
          ),
        ],
      ),
    );
  }

  Future<void> _executeSync(String host, int port) async {
    await _quackService.syncDevice(host, port, widget.onDataReceived, () async {
      await HapticFeedback.lightImpact();
      _playQuack();
      Fluttertoast.showToast(
        msg: "Sync Excellent!",
        backgroundColor: Colors.orange,
        textColor: Colors.white,
        gravity: ToastGravity.CENTER,
        toastLength: Toast.LENGTH_LONG,
      );
      if (mounted) {
        setState(() => _isSearching = false);
        _waveController.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002B21), // Midnight UI: Deep Green
      appBar: AppBar(
        title: const Text("The Pond", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.orange),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "SHREDDED SYNC",
              style: TextStyle(
                color: Colors.orange,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              height: 250,
              width: 250,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_isSearching)
                    AnimatedBuilder(
                      animation: _waveController,
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            for (int i = 0; i < 4; i++)
                              Transform.scale(
                                scale: 1.0 + ((_waveController.value + (i * 0.25)) % 1.0) * 3.5,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.orange.withValues(alpha: (1.0 - ((_waveController.value + (i * 0.25)) % 1.0)).clamp(0.0, 1.0)),
                                      width: 3,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.orange, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        )
                      ],
                    ),
                    child: Icon(
                      _isSearching ? Icons.waves : Icons.pets,
                      color: Colors.orange,
                      size: 60,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _isSearching 
                  ? "Listening for nearby ducks..." 
                  : "Sync your shredded recipes and lists with others on your network.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.orange.withValues(alpha: 0.8),
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 80),
            GestureDetector(
              onTap: _isSearching ? null : _onQuack,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                decoration: BoxDecoration(
                  color: _isSearching ? Colors.grey.withValues(alpha: 0.1) : Colors.orange,
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: _isSearching ? [] : [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    )
                  ],
                ),
                child: Text(
                  _isSearching ? "QUACKING..." : "START QUACKING",
                  style: TextStyle(
                    color: _isSearching ? Colors.orange.withValues(alpha: 0.5) : const Color(0xFF002B21),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
