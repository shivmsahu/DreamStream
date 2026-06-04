import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/services.dart';

class LocalizationService {
  static Map<String, dynamic> _localizedStrings = {};

  static Future<void> load() async {
    try {
      String jsonString = await rootBundle.loadString('assets/lang/en.json');
      _localizedStrings = jsonDecode(jsonString);
    } catch (e) {
      print('Localization load error: $e');
    }
  }

  static String getString(String key, [Map<String, String>? args]) {
    String text = _localizedStrings[key] ?? key;
    if (args != null) {
      args.forEach((k, v) {
        text = text.replaceAll('{$k}', v);
      });
    }
    return text;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalizationService.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: LocalizationService.getString('app_title'),
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          secondary: Color(0xFF6D28D9),
          surface: Color(0xFF1E1E1E),
          background: Color(0xFF121212),
          onBackground: Colors.white,
          onSurface: Colors.white,
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
          bodyLarge: TextStyle(color: Colors.white70),
        ),
        useMaterial3: true,
      ),
      home: Platform.isAndroid ? const AndroidWebcamScreen() : const PCReceiverScreen(),
    );
  }
}

class AndroidWebcamScreen extends StatefulWidget {
  const AndroidWebcamScreen({super.key});

  @override
  State<AndroidWebcamScreen> createState() => _AndroidWebcamScreenState();
}

class _AndroidWebcamScreenState extends State<AndroidWebcamScreen> with SingleTickerProviderStateMixin {
  String _permStatus = LocalizationService.getString('requesting_permission');
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    
    _initServer();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<String> _getLocalIpAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      return 'Unknown';
    }
    return 'Unknown';
  }

  Future<void> _initServer() async {
    final status = await Permission.camera.request();
    final ip = await _getLocalIpAddress();
    if (status.isGranted) {
      setState(() {
        _permStatus = LocalizationService.getString('server_ready', {'ip': ip});
      });
    } else {
      setState(() {
        _permStatus = LocalizationService.getString('camera_permission_denied');
      });
    }
  }

  Future<void> _scanQrCode() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return;

    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(LocalizationService.getString('scan_pc_qr_code')), backgroundColor: const Color(0xFF121212)),
        body: MobileScanner(
          onDetect: (capture) async {
            if (_isScanning) return; // Prevent multiple scans
            
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              if (barcode.rawValue != null) {
                try {
                  final data = jsonDecode(barcode.rawValue!);
                  if (data['ip'] != null && data['port'] != null) {
                    _isScanning = true;
                    final pcIp = data['ip'];
                    final pcPort = data['port'];
                    final myIp = await _getLocalIpAddress();
                    
                    try {
                      final socket = await Socket.connect(pcIp, pcPort, timeout: const Duration(seconds: 3));
                      socket.write(jsonEncode({'phone_ip': myIp}));
                      await socket.flush();
                      socket.close();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService.getString('paired_successfully'))));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService.getString('error_connecting', {'error': e.toString()}))));
                      }
                    } finally {
                      _isScanning = false;
                    }
                    return;
                  }
                } catch (e) {
                  // Not valid JSON
                }
              }
            }
          },
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 10))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF8B5CF6).withOpacity(0.2),
                    border: Border.all(color: const Color(0xFF8B5CF6), width: 2),
                  ),
                  child: const Icon(Icons.camera_alt, size: 64, color: Color(0xFF8B5CF6)),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                LocalizationService.getString('server_title'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: const Color(0xFF8B5CF6)),
              ),
              const SizedBox(height: 16),
              Text(
                _permStatus,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _scanQrCode,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(LocalizationService.getString('scan_qr_to_pair')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PCReceiverScreen extends StatefulWidget {
  const PCReceiverScreen({super.key});

  @override
  State<PCReceiverScreen> createState() => _PCReceiverScreenState();
}

class _PCReceiverScreenState extends State<PCReceiverScreen> {
  String _status = LocalizationService.getString('disconnected');
  bool _isStreaming = false;
  bool _showPreview = true;
  Socket? _socket;
  Uint8List? _currentFrame;

  HttpServer? _mjpegServer;
  final List<HttpResponse> _mjpegClients = [];

  String _selectedResolution = '1280x720';
  int _selectedFps = 30;
  int _selectedRotation = 90;
  int _selectedQuality = 50; 
  String _connectionMode = 'Wi-Fi';
  final TextEditingController _ipController = TextEditingController();

  ServerSocket? _pairingServer;

  @override
  void initState() {
    super.initState();
    _startMjpegServer();
  }

  Future<void> _startMjpegServer() async {
    try {
      _mjpegServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 8081);
      _mjpegServer!.listen((HttpRequest request) {
        request.response.headers.add('Content-Type', 'multipart/x-mixed-replace; boundary=--myboundary');
        request.response.headers.add('Connection', 'close');
        request.response.headers.add('Cache-Control', 'no-cache, private');
        request.response.headers.add('Pragma', 'no-cache');
        
        _mjpegClients.add(request.response);
        request.response.done.then((_) {
          _mjpegClients.remove(request.response);
        });
      });
    } catch (e) {
      print('Failed to start MJPEG server: $e');
    }
  }

  void _broadcastMjpegFrame(List<int> frameBytes) {
    for (var client in _mjpegClients) {
      try {
        client.add(utf8.encode('--myboundary\r\n'));
        client.add(utf8.encode('Content-Type: image/jpeg\r\n'));
        client.add(utf8.encode('Content-Length: ${frameBytes.length}\r\n\r\n'));
        client.add(frameBytes);
        client.add(utf8.encode('\r\n'));
      } catch (e) {
        // Ignored
      }
    }
  }

  @override
  void dispose() {
    _stopStreaming();
    _pairingServer?.close();
    _mjpegServer?.close(force: true);
    for (var client in _mjpegClients) {
      client.close();
    }
    _ipController.dispose();
    super.dispose();
  }

  Future<String> _getLocalIpAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      return 'Unknown';
    }
    return 'Unknown';
  }

  Future<void> _showQrCodeDialog() async {
    final ip = await _getLocalIpAddress();
    if (ip == 'Unknown') {
      setState(() => _status = LocalizationService.getString('cannot_find_local_ip'));
      return;
    }

    try {
      _pairingServer?.close(); // close any existing server
      _pairingServer = await ServerSocket.bind(InternetAddress.anyIPv4, 8083);
      _pairingServer!.listen((Socket client) {
        client.listen((data) {
          try {
            final msg = utf8.decode(data);
            final json = jsonDecode(msg);
            if (json['phone_ip'] != null) {
              final phoneIp = json['phone_ip'];
              setState(() {
                _connectionMode = 'Wi-Fi';
                _ipController.text = phoneIp;
              });
              if (mounted && Navigator.canPop(context)) {
                Navigator.of(context).pop(); // Close dialog
              }
              client.close();
              _pairingServer?.close();
              
              // Automatically connect after a small delay
              Future.delayed(const Duration(milliseconds: 500), () {
                _startServerOnAndroid();
              });
            }
          } catch (e) {}
        });
      });
    } catch (e) {
      print('Pairing server error: $e');
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(LocalizationService.getString('scan_with_phone')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 250,
              height: 250,
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: QrImageView(
                data: jsonEncode({'ip': ip, 'port': 8083}),
                version: QrVersions.auto,
                backgroundColor: Colors.white,
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(LocalizationService.getString('tap_scan_qr'), textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _pairingServer?.close();
              Navigator.of(context).pop();
            },
            child: Text(LocalizationService.getString('cancel'), style: const TextStyle(color: Color(0xFF8B5CF6))),
          ),
        ],
      ),
    );
  }

  Future<void> _startServerOnAndroid() async {
    setState(() => _status = LocalizationService.getString('connecting'));
    try {
      int targetWidth = 1280;
      int targetHeight = 720;
      if (_selectedResolution == '1920x1080') { targetWidth = 1920; targetHeight = 1080; }
      else if (_selectedResolution == '640x480') { targetWidth = 640; targetHeight = 480; }
      else if (_selectedResolution == 'Max') { targetWidth = 0; targetHeight = 0; }

      String targetIp = '127.0.0.1';

      if (_connectionMode == 'USB (ADB)') {
        final adbPath = r'C:\Users\shiva\AppData\Local\Android\Sdk\platform-tools\adb.exe';
        await Process.run(adbPath, ['forward', 'tcp:8080', 'tcp:8080']);
        await Process.run(adbPath, ['forward', 'tcp:1935', 'tcp:1935']); 
      } else {
        targetIp = _ipController.text.trim();
        if (targetIp.isEmpty) {
          setState(() => _status = LocalizationService.getString('enter_ip_or_scan'));
          return;
        }
      }

      setState(() => _status = LocalizationService.getString('connecting_to_socket'));
      _socket = await Socket.connect(targetIp, 8080);
      
      _socket!.write("CONFIG:$targetWidth,$targetHeight,$_selectedFps,$_selectedRotation,MJPEG,$_selectedQuality\n");
      
      setState(() {
        _status = LocalizationService.getString('connected_playing');
        _isStreaming = true;
      });

      _handleSocketData(_socket!);
    } catch (e) {
      setState(() => _status = LocalizationService.getString('error', {'error': e.toString()}));
    }
  }

  void _handleSocketData(Socket socket) {
    int? expectedLength;
    List<int> buffer = [];

    socket.listen((data) {
      buffer.addAll(data);
      while (true) {
        if (expectedLength == null) {
          if (buffer.length >= 4) {
            final lengthBytes = buffer.sublist(0, 4);
            expectedLength = ByteData.sublistView(Uint8List.fromList(lengthBytes)).getInt32(0);
            buffer.removeRange(0, 4);
          } else {
            break;
          }
        }

        if (expectedLength != null && buffer.length >= expectedLength!) {
          final frameBytes = buffer.sublist(0, expectedLength!);
          buffer.removeRange(0, expectedLength!);
          expectedLength = null;

          if (mounted) {
            setState(() {
              _currentFrame = Uint8List.fromList(frameBytes);
            });
            _broadcastMjpegFrame(frameBytes);
          }
        } else {
          break;
        }
      }
    }, onDone: _stopStreaming, onError: (e) => _stopStreaming());
  }

  void _stopStreaming() {
    _socket?.close();
    if (mounted) {
      setState(() {
        _status = LocalizationService.getString('disconnected');
        _isStreaming = false;
        _currentFrame = null;
      });
    }
  }

  Widget _buildDropdown<T>(String label, T value, List<T> items, void Function(T?) onChanged, [String Function(T)? display]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              dropdownColor: const Color(0xFF1E1E1E),
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF8B5CF6)),
              isExpanded: true,
              style: const TextStyle(color: Colors.white),
              items: items.map((T val) => DropdownMenuItem<T>(
                value: val,
                child: Text(display != null ? display(val) : val.toString()),
              )).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Icon(Icons.videocam, color: Color(0xFF8B5CF6), size: 32),
                const SizedBox(width: 12),
                Text(
                  LocalizationService.getString('app_title'),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Spacer(),
                if (_isStreaming)
                  IconButton(
                    onPressed: () => setState(() => _showPreview = !_showPreview),
                    icon: Icon(_showPreview ? Icons.visibility : Icons.visibility_off, color: Colors.white70),
                    tooltip: _showPreview ? 'Hide Preview' : 'Show Preview',
                  ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isStreaming ? Colors.green.withOpacity(0.2) : Colors.white10,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _isStreaming ? Colors.green : Colors.white24),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: _isStreaming ? Colors.greenAccent : Colors.grey),
                      const SizedBox(width: 8),
                      Text(_status, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              ],
            ),
          ),
          // Video Player Area
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0D15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Center(
                child: _isStreaming 
                  ? (_currentFrame != null
                      ? _showPreview
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.memory(
                              _currentFrame!,
                              gaplessPlayback: true,
                              fit: BoxFit.contain,
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.visibility_off, size: 64, color: Colors.white24),
                              const SizedBox(height: 16),
                              Text(LocalizationService.getString('preview_hidden'), style: const TextStyle(color: Colors.white54, fontSize: 18)),
                            ],
                          )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                            const SizedBox(height: 16),
                            Text(LocalizationService.getString('waiting_for_connection'), style: const TextStyle(color: Colors.white54, fontSize: 18)),
                          ],
                        )
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.videocam_off, size: 64, color: Colors.white24),
                        const SizedBox(height: 16),
                        Text(LocalizationService.getString('waiting_for_connection'), style: const TextStyle(color: Colors.white54, fontSize: 18)),
                      ],
                    ),
              ),
            ),
          ),
          // OBS Helper URL if MJPEG
          if (_isStreaming)
            Container(
              margin: const EdgeInsets.only(top: 16, left: 24, right: 24),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.link, color: Color(0xFF8B5CF6)),
                  const SizedBox(width: 8),
                  Text(LocalizationService.getString('obs_media_source_url'), style: const TextStyle(color: Colors.white70)),
                  const SelectableText('http://127.0.0.1:8081', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20, color: Color(0xFF8B5CF6)),
                    tooltip: 'Copy',
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: 'http://127.0.0.1:8081'));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService.getString('copied'))));
                    },
                  ),
                ],
              ),
            ),
          // Control Panel
          Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildDropdown<String>(LocalizationService.getString('connection'), _connectionMode, ['USB (ADB)', 'Wi-Fi'], (v) => setState(() => _connectionMode = v!))),
                    const SizedBox(width: 16),
                    if (_connectionMode == 'Wi-Fi')
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(LocalizationService.getString('ip_address'), style: const TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF161616),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: TextField(
                                      controller: _ipController,
                                      style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        hintText: LocalizationService.getString('enter_ip'),
                                        hintStyle: const TextStyle(color: Colors.white30),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: _showQrCodeDialog,
                                  icon: const Icon(Icons.qr_code, color: Color(0xFF8B5CF6)),
                                  tooltip: 'Show QR for Pairing',
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    else
                      const Expanded(child: SizedBox()), // Placeholder
                    const SizedBox(width: 16),
                    Expanded(child: _buildDropdown<String>(LocalizationService.getString('resolution'), _selectedResolution, ['1920x1080', '1280x720', '640x480', 'Max'], (v) => setState(() => _selectedResolution = v!))),
                    const SizedBox(width: 16),
                    Expanded(child: _buildDropdown<int>(LocalizationService.getString('fps'), _selectedFps, [15, 30, 60], (v) => setState(() => _selectedFps = v!), (v) => '$v ${LocalizationService.getString('fps')}')),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown<int>(LocalizationService.getString('quality'), _selectedQuality, [30, 50, 70, 90], (v) => setState(() => _selectedQuality = v!), (v) => '$v%')
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: !_isStreaming
                        ? ElevatedButton(
                            onPressed: _startServerOnAndroid,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B5CF6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: Text(LocalizationService.getString('connect'), style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          )
                        : ElevatedButton(
                            onPressed: _stopStreaming,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: const Color(0xFFFFB4AB),
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(color: Color(0xFF93000A)),
                              ),
                              elevation: 0,
                            ),
                            child: Text(LocalizationService.getString('stop_stream'), style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
