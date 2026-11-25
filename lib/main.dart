import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomeScreen(),
    ));

String globalBackendUrl = "https://yt-clipper-backend-baf3.onrender.com";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _wakingServer = false;

  String? _extractVideoId(String url) {
    final regExp = RegExp(
      r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?|live|shorts)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})',
    );
    return regExp.firstMatch(url)?.group(1);
  }

  void _openEditor() {
    final videoId = _extractVideoId(_urlController.text.trim());
    if (videoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valid YouTube link paste karein!')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          videoId: videoId,
          videoUrl: _urlController.text.trim(),
        ),
      ),
    );
  }

  Future<void> _wakeServer() async {
    setState(() => _wakingServer = true);
    try {
      final res = await http
          .get(Uri.parse(globalBackendUrl))
          .timeout(const Duration(seconds: 65));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server Ready! (${res.statusCode})')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server wake-up error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _wakingServer = false);
    }
  }

  void _openSettings() {
    final ctrl = TextEditingController(text: globalBackendUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Backend Server URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _wakeServer();
              },
              icon: const Icon(Icons.bolt),
              label: const Text('Wake Up Render Server'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => globalBackendUrl = ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clippix'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.content_cut, size: 72, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text(
              'YouTube Video Link Paste Karein',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'https://youtu.be/...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _urlController.clear(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: _openEditor,
                icon: const Icon(Icons.video_settings),
                label: const Text('Load Video & Edit', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _wakingServer ? null : _wakeServer,
              icon: _wakingServer
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.power_settings_new),
              label: Text(_wakingServer ? 'Server Jaag Raha Hai...' : 'Wake Up Server'),
            ),
          ],
        ),
      ),
    );
  }
}

class EditorScreen extends StatefulWidget {
  final String videoId;
  final String videoUrl;
  const EditorScreen({super.key, required this.videoId, required this.videoUrl});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final WebViewController _webController;

  double _startSec = 0;
  double _endSec = 25;
  double _maxSec = 1800;

  final TextEditingController _startCtrl = TextEditingController(text: "00:00");
  final TextEditingController _endCtrl = TextEditingController(text: "00:25");

  Offset camPos = const Offset(0.05, 0.08);
  Size camSize = const Size(0.32, 0.35);

  Offset screenPos = const Offset(0.35, 0.12);
  Size screenSize = const Size(0.60, 0.75);

  bool _editBoxes = false;
  String _camPosition = 'top';
  String _captionStyle = 'speed';
  bool _isProcessing = false;

  String _formatMMSS(double totalSeconds) {
    final int mins = totalSeconds ~/ 60;
    final int secs = (totalSeconds % 60).round();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  double? _parseMMSS(String input) {
    final clean = input.trim();
    if (clean.contains(':')) {
      final parts = clean.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]);
        final s = int.tryParse(parts[1]);
        if (m != null && s != null) return (m * 60 + s).toDouble();
      }
    } else {
      return double.tryParse(clean);
    }
    return null;
  }

  void _syncControllers() {
    _startCtrl.text = _formatMMSS(_startSec);
    _endCtrl.text = _formatMMSS(_endSec);
  }

  void _applyTypedTimes() {
    final s = _parseMMSS(_startCtrl.text);
    final e = _parseMMSS(_endCtrl.text);
    if (s == null || e == null || e <= s) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sahi time likhein (jaise 02:15 aur 02:45)')),
      );
      return;
    }
    setState(() {
      _startSec = s;
      _endSec = e;
      if (_endSec > _maxSec) _maxSec = _endSec + 60;
    });
    _seekVideoTo(_startSec.toInt());
  }

  void _seekVideoTo(int seconds) {
    final html = _buildPlayerHtml(widget.videoId, startSeconds: seconds);
    _webController.loadHtmlString(html, baseUrl: 'https://www.youtube-nocookie.com');
  }

  String _buildPlayerHtml(String id, {int startSeconds = 0}) {
    return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
  html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
  iframe { width: 100%; height: 100%; border: 0; }
</style>
</head>
<body>
  <iframe
    src="https://www.youtube-nocookie.com/embed/$id?start=$startSeconds&autoplay=1&playsinline=1&rel=0&modestbranding=1"
    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
    allowfullscreen>
  </iframe>
</body>
</html>
''';
  }

  @override
  void initState() {
    super.initState();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        "Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
      )
      ..loadHtmlString(
        _buildPlayerHtml(widget.videoId, startSeconds: 0),
        baseUrl: 'https://www.youtube-nocookie.com',
      );
  }

  Future<void> _generateClip() async {
    if (_endSec - _startSec > 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Free server ke liye 60 sec se chhoti clip rakhein!')),
      );
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final response = await http
          .post(
            Uri.parse('$globalBackendUrl/process-clip'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'url': widget.videoUrl,
              'start_time': _startSec,
              'end_time': _endSec,
              'cam_x': camPos.dx.clamp(0.0, 0.95),
              'cam_y': camPos.dy.clamp(0.0, 0.95),
              'cam_w': camSize.width.clamp(0.05, 1.0 - camPos.dx),
              'cam_h': camSize.height.clamp(0.05, 1.0 - camPos.dy),
              'screen_x': screenPos.dx.clamp(0.0, 0.95),
              'screen_y': screenPos.dy.clamp(0.0, 0.95),
              'screen_w': screenSize.width.clamp(0.05, 1.0 - screenPos.dx),
              'screen_h': screenSize.height.clamp(0.05, 1.0 - screenPos.dy),
              'cam_position': _camPosition,
              'caption_style': _captionStyle,
            }),
          )
          .timeout(const Duration(minutes: 4));

      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final filePath = '${dir.path}/short_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        await Gal.putVideo(filePath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('Video Gallery mein save ho gayi!'),
            ),
          );
        }
      } else {
        throw Exception('Server Error: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), duration: const Duration(seconds: 8)),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _buildBox({
    required String label,
    required Color color,
    required Offset pos,
    required Size size,
    required double containerW,
    required double containerH,
    required Function(Offset) onMove,
    required Function(Size) onResize,
  }) {
    return Positioned(
      left: pos.dx * containerW,
      top: pos.dy * containerH,
      child: IgnorePointer(
        ignoring: !_editBoxes,
        child: GestureDetector(
          onPanUpdate: (details) {
            final newDx = (pos.dx + details.delta.dx / containerW).clamp(0.0, 1.0 - size.width);
            final newDy = (pos.dy + details.delta.dy / containerH).clamp(0.0, 1.0 - size.height);
            onMove(Offset(newDx, newDy));
          },
          child: Container(
            width: size.width * containerW,
            height: size.height * containerH,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 2.5),
              color: color.withOpacity(_editBoxes ? 0.22 : 0.06),
            ),
            child: Stack(
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    color: Colors.black54,
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (_editBoxes)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onPanUpdate: (d) {
                        final newW = (size.width + d.delta.dx / containerW).clamp(0.1, 1.0 - pos.dx);
                        final newH = (size.height + d.delta.dy / containerH).clamp(0.1, 1.0 - pos.dy);
                        onResize(Size(newW, newH));
                      },
                      child: Container(
                        width: 22,
                        height: 22,
                        color: color,
                        child: const Icon(Icons.open_in_full, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final videoHeight = screenWidth * 9 / 16;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crop & Captions'),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _editBoxes = !_editBoxes),
            icon: Icon(
              _editBoxes ? Icons.lock_open : Icons.play_circle_fill,
              color: _editBoxes ? Colors.amber : Colors.greenAccent,
            ),
            label: Text(
              _editBoxes ? 'Adjust Boxes' : 'Play Mode',
              style: TextStyle(color: _editBoxes ? Colors.amber : Colors.greenAccent),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: screenWidth,
              height: videoHeight,
              child: Stack(
                children: [
                  WebViewWidget(controller: _webController),
                  _buildBox(
                    label: 'FACECAM',
                    color: Colors.redAccent,
                    pos: camPos,
                    size: camSize,
                    containerW: screenWidth,
                    containerH: videoHeight,
                    onMove: (p) => setState(() => camPos = p),
                    onResize: (s) => setState(() => camSize = s),
                  ),
                  _buildBox(
                    label: 'SCREEN',
                    color: Colors.blueAccent,
                    pos: screenPos,
                    size: screenSize,
                    containerW: screenWidth,
                    containerH: videoHeight,
                    onMove: (p) => setState(() => screenPos = p),
                    onResize: (s) => setState(() => screenSize = s),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Clip: ${_formatMMSS(_startSec)} - ${_formatMMSS(_endSec)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Duration: ${(_endSec - _startSec).toInt()}s',
                        style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  RangeSlider(
                    values: RangeValues(_startSec, _endSec),
                    min: 0,
                    max: _maxSec,
                    onChanged: (vals) {
                      setState(() {
                        _startSec = vals.start;
                        _endSec = vals.end;
                        _syncControllers();
                      });
                    },
                    onChangeEnd: (vals) {
                      _seekVideoTo(vals.start.toInt());
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _startCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Start (MM:SS)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _endCtrl,
                          decoration: const InputDecoration(
                            labelText: 'End (MM:SS)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _applyTypedTimes,
                        child: const Text('Set & Play'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Facecam Position:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Facecam Top')),
                          selected: _camPosition == 'top',
                          onSelected: (_) => setState(() => _camPosition = 'top'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Facecam Bottom')),
                          selected: _camPosition == 'bottom',
                          onSelected: (_) => setState(() => _camPosition = 'bottom'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Caption Style:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Red/White Viral'),
                        selected: _captionStyle == 'speed',
                        onSelected: (_) => setState(() => _captionStyle = 'speed'),
               ),
                      ChoiceChip(
                        label: const Text('Hormozi Green'),
                        selected: _captionStyle == 'hormozi',
                        onSelected: (_) => setState(() => _captionStyle = 'hormozi'),
                      ),
                      ChoiceChip(
                        label: const Text('No Captions'),
                        selected: _captionStyle == 'none',
                        onSelected: (_) => setState(() => _captionStyle = 'none'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _isProcessing ? null : _generateClip,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: Text(
                        _isProcessing ? 'Clip Ban Rahi Hai (Wait)...' : 'Generate & Save Clip',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
          
