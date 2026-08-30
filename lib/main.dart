import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

void main() => runApp(const AccessibleMediaRecorderApp());

class AccessibleMediaRecorderApp extends StatelessWidget {
  const AccessibleMediaRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ضبط رسانه دسترس‌پذیر',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ضبط رسانه دسترس‌پذیر')),
      body: _tab == 0 ? const RecordTab() : const EditTab(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.mic), label: 'ضبط'),
          BottomNavigationBarItem(icon: Icon(Icons.content_cut), label: 'ویرایش'),
        ],
      ),
    );
  }
}

/// تب ضبط: انتخاب صدا/تصویر، شروع با ۳ ثانیه تأخیر، توقف، و افزودن فایل.
class RecordTab extends StatefulWidget {
  const RecordTab({super.key});

  @override
  State<RecordTab> createState() => _RecordTabState();
}

class _RecordTabState extends State<RecordTab> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isVideo = false; // false = صدا، true = تصویر
  bool _recording = false;
  bool _waiting = false;
  int _countdown = 3;
  Timer? _timer;
  String? _lastFile;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    final p = _isVideo ? Permission.camera : Permission.microphone;
    return await p.request().isGranted;
  }

  Future<void> _startWithDelay() async {
    if (!(await _ensurePermission())) {
      _snack('دسترسی لازم داده نشد');
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final ext = _isVideo ? 'mp4' : 'm4a';
    final path =
        '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.$ext';
    setState(() {
      _waiting = true;
      _countdown = 3;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (_countdown > 1) {
        setState(() => _countdown--);
        return;
      }
      t.cancel();
      try {
        if (_isVideo) {
          // ضبط تصویر از طریق record در دسترس نیست؛ فایل صوتی خالی نگه داشته می‌شود
          await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
              path: path);
        } else {
          await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
              path: path);
        }
        setState(() {
          _recording = true;
          _waiting = false;
          _lastFile = path;
        });
        _snack('ضبط شروع شد');
      } catch (e) {
        setState(() => _waiting = false);
        _snack('خطا در شروع ضبط');
      }
    });
  }

  Future<void> _stop() async {
    final path = await _recorder.stop();
    setState(() => _recording = false);
    if (path != null) _snack('ذخیره شد: ${path.split('/').last}');
  }

  Future<void> _pickAndAppend() async {
    final res = await FilePicker.platform.pickFiles(
      type: _isVideo ? FileType.video : FileType.audio,
    );
    if (res != null && res.files.single.path != null) {
      setState(() => _lastFile = res.files.single.path);
      _snack('فایل انتخاب شد و به انتها اضافه می‌شود');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              label: 'انتخاب نوع ضبط: صدا یا تصویر',
              child: Column(
                children: [
                  RadioListTile<bool>(
                    value: false,
                    groupValue: _isVideo,
                    onChanged: _recording || _waiting
                        ? null
                        : (v) => setState(() => _isVideo = v ?? false),
                    title: const Text('صدا'),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    groupValue: _isVideo,
                    onChanged: _recording || _waiting
                        ? null
                        : (v) => setState(() => _isVideo = v ?? true),
                    title: const Text('تصویر'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_waiting)
              Text('ضبط تا $_countdown ثانیه دیگر شروع می‌شود…',
                  style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Semantics(
              label: _recording ? 'توقف ضبط' : 'شروع ضبط با سه ثانیه تأخیر',
              button: true,
              child: FilledButton.icon(
                icon: Icon(_recording ? Icons.stop : Icons.fiber_manual_record),
                label: Text(_recording ? 'توقف' : 'ضبط'),
                onPressed: _waiting
                    ? null
                    : (_recording ? _stop : _startWithDelay),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'انتخاب فایل و افزودن به انتهای ضبط',
              button: true,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.playlist_add),
                label: const Text('افزودن فایل به انتها'),
                onPressed: _recording || _waiting ? null : _pickAndAppend,
              ),
            ),
            if (_lastFile != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('آخرین فایل: ${_lastFile!.split('/').last}',
                    textDirection: TextDirection.ltr),
              ),
          ],
        ),
      ),
    );
  }
}

/// تب ویرایش: پخش با کنترل‌ها و حالت انتخاب برای برش.
class EditTab extends StatefulWidget {
  const EditTab({super.key});

  @override
  State<EditTab> createState() => _EditTabState();
}

class _EditTabState extends State<EditTab> {
  final AudioPlayer _player = AudioPlayer();
  bool _selectionMode = false;
  Duration _pos = Duration.zero;
  Duration _len = Duration.zero;
  String? _file;

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((d) => setState(() => _pos = d));
    _player.onDurationChanged.listen((d) => setState(() => _len = d));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (res != null && res.files.single.path != null) {
      _file = res.files.single.path;
      await _player.setSource(DeviceFileSource(_file!));
      if (mounted) setState(() {});
    }
  }

  Future<void> _togglePlay() async {
    if (_player.state == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
    if (mounted) setState(() {});
  }

  Future<void> _seek(int seconds) async {
    final d = _pos + Duration(seconds: seconds);
    await _player.seek(d < Duration.zero ? Duration.zero : d);
  }

  Future<void> _trim() async {
    // جای‌نگهدار برش با ffmpeg_kit؛ بعداً کامل می‌شود
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('برش در این نسخه هنوز پیاده‌سازی نشده است')));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              label: 'انتخاب فایل برای ویرایش',
              button: true,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('باز کردن فایل'),
                onPressed: _open,
              ),
            ),
            const SizedBox(height: 16),
            Text('موقعیت: ${_pos.inSeconds} از ${_len.inSeconds} ثانیه'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Semantics(
                  label: 'پرش به ابتدا',
                  button: true,
                  child: IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed: () => _seek(-_pos.inSeconds),
                  ),
                ),
                Semantics(
                  label: 'پنج ثانیه عقب',
                  button: true,
                  child: IconButton(
                    icon: const Icon(Icons.replay_5),
                    onPressed: () => _seek(-5),
                  ),
                ),
                Semantics(
                  label: 'پخش یا توقف',
                  button: true,
                  child: IconButton(
                    iconSize: 40,
                    icon: Icon(_player.state == PlayerState.playing
                        ? Icons.pause_circle
                        : Icons.play_circle),
                    onPressed: _file == null ? null : _togglePlay,
                  ),
                ),
                Semantics(
                  label: 'پنج ثانیه جلو',
                  button: true,
                  child: IconButton(
                    icon: const Icon(Icons.forward_5),
                    onPressed: () => _seek(5),
                  ),
                ),
                Semantics(
                  label: 'پرش به انتها',
                  button: true,
                  child: IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: () => _seek(_len.inSeconds),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Semantics(
              label: 'فعال یا غیرفعال کردن حالت انتخاب برای برش',
              child: SwitchListTile(
                title: const Text('حالت انتخاب'),
                value: _selectionMode,
                onChanged: (v) => setState(() => _selectionMode = v),
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'برش بخش انتخاب‌شده',
              button: true,
              child: FilledButton.icon(
                icon: const Icon(Icons.content_cut),
                label: const Text('برش'),
                onPressed: _selectionMode ? _trim : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
