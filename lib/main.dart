import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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

/// تب ضبط: انتخاب صدا/تصویر، شروع با ۳ ثانیه تأخیر، مکث و ادامه با کلید صدا یا دکمه، توقف کامل، و ذخیره در پوشه.
class RecordTab extends StatefulWidget {
  const RecordTab({super.key});

  @override
  State<RecordTab> createState() => _RecordTabState();
}

enum _RecState { idle, waiting, recording, paused, finished }

class _RecordTabState extends State<RecordTab> {
  static const MethodChannel _serviceChannel =
      MethodChannel('acc_rec/foreground_service');

  final AudioRecorder _recorder = AudioRecorder();
  bool _isVideo = false; // false = صدا، true = تصویر
  _RecState _state = _RecState.idle;
  int _countdown = 3;
  Timer? _countdownTimer;
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;
  String? _tempFile;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _elapsedTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    final p = _isVideo ? Permission.camera : Permission.microphone;
    return await p.request().isGranted;
  }

  String _formatElapsed() {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _elapsedSeconds++);
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
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
      _state = _RecState.waiting;
      _countdown = 3;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (_countdown > 1) {
        setState(() => _countdown--);
        return;
      }
      t.cancel();
      try {
        await Permission.notification.request();
        await _serviceChannel.invokeMethod('start');
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
            path: path);
        setState(() {
          _state = _RecState.recording;
          _tempFile = path;
          _elapsedSeconds = 0;
        });
        _startElapsedTimer();
      } catch (e) {
        setState(() => _state = _RecState.idle);
        _snack('خطا در شروع ضبط');
      }
    });
  }

  Future<void> _pause() async {
    try {
      await _recorder.pause();
      _stopElapsedTimer();
      setState(() => _state = _RecState.paused);
    } catch (e) {
      _snack('خطا در توقف موقت');
    }
  }

  Future<void> _resume() async {
    try {
      await _recorder.resume();
      _startElapsedTimer();
      setState(() => _state = _RecState.recording);
    } catch (e) {
      _snack('خطا در ادامه ضبط');
    }
  }

  Future<void> _finish() async {
    final path = await _recorder.stop();
    _stopElapsedTimer();
    await _serviceChannel.invokeMethod('stop');
    setState(() {
      _state = _RecState.finished;
      _tempFile = path ?? _tempFile;
    });
    _snack('ضبط پایان یافت. حالا می‌توانید ذخیره کنید');
  }

  Future<void> _save() async {
    if (_tempFile == null) return;
    final ext = _tempFile!.split('.').last;
    final defaultBase = 'rec_${DateTime.now().millisecondsSinceEpoch}';
    final controller = TextEditingController(text: defaultBase);
    final chosenBase = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('نام فایل برای ذخیره'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'نام فایل',
              helperText: 'پسوند فایل (.${ext}) خودکار اضافه می‌شود و ثابت است',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('ذخیره'),
            ),
          ],
        );
      },
    );
    if (chosenBase == null) {
      // کاربر انصراف را انتخاب کرد؛ ضبط کنار گذاشته می‌شود و کلید ذخیره غیرفعال می‌شود
      setState(() {
        _state = _RecState.idle;
        _tempFile = null;
        _elapsedSeconds = 0;
      });
      return;
    }
    if (chosenBase.isEmpty) return;
    final chosen = '$chosenBase.$ext';

    final granted = await Permission.manageExternalStorage.request();
    if (!granted.isGranted) {
      _snack('دسترسی به حافظه داده نشد');
      return;
    }
    try {
      final folder = Directory('/storage/emulated/0/acc-rec');
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      final destPath = '${folder.path}/$chosen';
      await File(_tempFile!).copy(destPath);
      setState(() {
        _state = _RecState.idle;
        _tempFile = null;
        _elapsedSeconds = 0;
      });
      _snack('در پوشه acc-rec ذخیره شد: $chosen');
    } catch (e) {
      _snack('خطا در ذخیره فایل');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _mainButtonLabel() {
    switch (_state) {
      case _RecState.idle:
        return 'ضبط';
      case _RecState.recording:
        return 'توقف موقت';
      case _RecState.paused:
        return 'ادامه ضبط';
      case _RecState.waiting:
        return 'در حال شمارش…';
      case _RecState.finished:
        return 'ضبط تمام شده';
    }
  }

  Future<void> _mainButtonPressed() async {
    switch (_state) {
      case _RecState.idle:
        await _startWithDelay();
        break;
      case _RecState.recording:
        await _pause();
        break;
      case _RecState.paused:
        await _resume();
        break;
      case _RecState.waiting:
      case _RecState.finished:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canFinish =
        _state == _RecState.recording || _state == _RecState.paused;
    final canSave = _state == _RecState.finished;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MergeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Radio<bool>(
                      value: false,
                      groupValue: _isVideo,
                      onChanged: _state == _RecState.idle
                          ? (v) => setState(() => _isVideo = v ?? false)
                          : null,
                    ),
                    const Text('صدا'),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              MergeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Radio<bool>(
                      value: true,
                      groupValue: _isVideo,
                      onChanged: _state == _RecState.idle
                          ? (v) => setState(() => _isVideo = v ?? true)
                          : null,
                    ),
                    const Text('تصویر'),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_state == _RecState.waiting)
                    Text('ضبط تا $_countdown ثانیه دیگر شروع می‌شود…',
                        style: Theme.of(context).textTheme.titleMedium),
                  if (_state == _RecState.recording ||
                      _state == _RecState.paused)
                    Semantics(
                      label: 'زمان سپری شده ضبط: ${_formatElapsed()}',
                      child: Text(
                        _formatElapsed(),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  // این فضا برای پیش‌نمایش تصویر در حین ضبط ویدیو در نظر گرفته شده است
                ],
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Semantics(
                label: _mainButtonLabel(),
                button: true,
                child: FilledButton.icon(
                  icon: Icon(_state == _RecState.recording
                      ? Icons.pause
                      : Icons.fiber_manual_record),
                  label: Text(_mainButtonLabel()),
                  onPressed: _state == _RecState.waiting ||
                          _state == _RecState.finished
                      ? null
                      : _mainButtonPressed,
                ),
              ),
              Semantics(
                label: 'پایان کامل ضبط',
                button: true,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.stop_circle),
                  label: const Text('پایان ضبط'),
                  onPressed: canFinish ? _finish : null,
                ),
              ),
              Semantics(
                label: 'ذخیره فایل ضبط شده در پوشه اکسی رک',
                button: true,
                child: FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('ذخیره'),
                  onPressed: canSave ? _save : null,
                ),
              ),
            ],
          ),
        ],
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
