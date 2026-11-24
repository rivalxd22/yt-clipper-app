import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp( MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: HomeScreen(),
    ));

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();

  String? _extractVideoId(String url) {
    final regExp = RegExp(
      r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?|live|shorts)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})',
    );
    final match = regExp.firstMatch(url);
    return match?.group(1);
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
        builder: (_) => EditorScreen(url: _urlController.text.trim(), videoId: videoId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SpeedClip AI')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_call_rounded, size: 80, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text('YouTube Video ya Live Stream Link Paste Karein',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                hintText: 'https://youtube.com/watch?v=...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _openEditor,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.redAccent,
              ),
              child: const Text('Load Video & Clip', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class EditorScreen extends StatefulWidget {
  final String url;
  final String videoId;
  const EditorScreen({super.key, required this.url, required this.videoId});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final WebViewController _webController;

  double _startSec = 0;
  double _endSec = 15;
  final double _maxSec = 600;

  Offset camPos = const Offset(0.05, 0.05);
  Size camSize = const Size(0.30, 0.35);

  Offset screenPos = const Offset(0.35, 0.10);
  Size screenSize = const Size(0.60, 0.80);

  String _camPosition = 'top';
  String _captionStyle = 'speed';
  bool _isProcessing = false;

  final String backendUrl = "https://yt-clipper-backend-baf3.onrender.com/process-clip";

  @override
  void initState() {
    super.initState();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://www.youtube.com/embed/${widget.videoId}?autoplay=1'));
  }

  Future<void> _generateClip() async {
    setState(() => _isProcessing = true);
    try {
      final response = await http.post(
        Uri.parse(backendUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "url": widget.url,
          "start_time": _startSec,
          "end_time": _endSec,
          "cam_x": camPos.dx.clamp(0.0, 0.9),
          "cam_y": camPos.dy.clamp(0.0, 0.9),
          "cam_w": camSize.width.clamp(0.1, 1.0 - camPos.dx),
          "cam_h": camSize.height.clamp(0.1, 1.0 - camPos.dy),
          "screen_x": screenPos.dx.clamp(0.0, 0.9),
          "screen_y": screenPos.dy.clamp(0.0, 0.9),
          "screen_w": screenSize.width.clamp(0.1, 1.0 - screenPos.dx),
          "screen_h": screenSize.height.clamp(0.1, 1.0 - screenPos.dy),
          "cam_position": _camPosition,
          "caption_style": _captionStyle,
        }),
      );

      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/speed_clip_${DateTime.now().millisecondsSinceEpoch}.mp4');
        await file.writeAsBytes(response.bodyBytes);
        await Gal.putVideo(file.path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Clip Gallery mein save ho gayi! 🎉')),
          );
        }
      } else {
        throw Exception('Server Error: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crop & Captions')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = w * 9 / 16;
                return SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    children: [
                      WebViewWidget(controller: _webController),
                      Positioned(
                        left: camPos.dx * w,
                        top: camPos.dy * h,
                        child: GestureDetector(
                          onPanUpdate: (d) {
                            setState(() {
                              camPos = Offset(
                                (camPos.dx + d.delta.dx / w).clamp(0.0, 1.0 - camSize.width),
                                (camPos.dy + d.delta.dy / h).clamp(0.0, 1.0 - camSize.height),
                              );
                            });
                          },
                          child: Container(
                            width: camSize.width * w,
                            height: camSize.height * h,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.red, width: 2.5),
                              color: Colors.red.withOpacity(0.2),
                            ),
                            child: const Center(
                              child: Text('FACECAM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: screenPos.dx * w,
                        top: screenPos.dy * h,
                        child: GestureDetector(
                          onPanUpdate: (d) {
                            setState(() {
                              screenPos = Offset(
                                (screenPos.dx + d.delta.dx / w).clamp(0.0, 1.0 - screenSize.width),
                                (screenPos.dy + d.delta.dy / h).clamp(0.0, 1.0 - screenSize.height),
                              );
                            });
                          },
                          child: Container(
                            width: screenSize.width * w,
                            height: screenSize.height * h,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.blueAccent, width: 2.5),
                              color: Colors.blue.withOpacity(0.2),
                            ),
                            child: const Center(
                              child: Text('GAMEPLAY / SCREEN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 15),
            Text('Timeline Select Karein: ${_startSec.toInt()}s - ${_endSec.toInt()}s'),
            RangeSlider(
              values: RangeValues(_startSec, _endSec),
              min: 0,
              max: _maxSec,
              onChanged: (v) {
                setState(() {
                  _startSec = v.start;
                  _endSec = v.end;
                });
              },
            ),
            const Divider(),
            const Text('Facecam Position:', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Facecam Upar (Top)'),
                  selected: _camPosition == 'top',
                  onSelected: (_) => setState(() => _camPosition = 'top'),
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text('Facecam Niche (Bottom)'),
                  selected: _camPosition == 'bottom',
                  onSelected: (_) => setState(() => _camPosition = 'bottom'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text('Caption Style:', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('IShowSpeed Yellow'),
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
            _isProcessing
                ? const Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text('Clip render ho rahi hai (40-60s)...'),
                      ],
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _generateClip,
                    icon: const Icon(Icons.download, color: Colors.white),
                    label: const Text('Generate & Save Clip', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      backgroundColor: Colors.green,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
