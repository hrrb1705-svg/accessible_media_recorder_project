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
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';

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
  static const MethodChannel _screenChannel =
      MethodChannel('acc_rec/screen_events');

  final AudioRecorder _recorder = AudioRecorder();
  final FocusNode _mainButtonFocus = FocusNode();
  bool _isVideo = false; // false = صدا، true = تصویر
  _RecState _state = _RecState.idle;
  int _countdown = 3;
  Timer? _countdownTimer;
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;
  String? _tempFile;

  @override
  void initState() {
    super.initState();
    _screenChannel.setMethodCallHandler((call) async {
      if (call.method == 'screenOn' && _state == _RecState.recording) {
        await _pause();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _elapsedTimer?.cancel();
    _recorder.dispose();
    _mainButtonFocus.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    final p = _isVideo ? Permission.camera : Permission.microphone;
    return await p.request().isGranted;
  }

  void _focusMainButtonNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mainButtonFocus.requestFocus();
    });
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
        _focusMainButtonNextFrame();
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
      _focusMainButtonNextFrame();
    } catch (e) {
      _snack('خطا در توقف موقت');
    }
  }

  Future<void> _resume() async {
    try {
      await _recorder.resume();
      _startElapsedTimer();
      setState(() => _state = _RecState.recording);
      _focusMainButtonNextFrame();
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
        return 'شروع ضبط';
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
                  focusNode: _mainButtonFocus,
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
  final TextEditingController _stepController =
      TextEditingController(text: '5.0');
  bool _isVideo = false; // false = صدا، true = تصویر
  Duration _pos = Duration.zero;
  Duration _len = Duration.zero;
  String? _file;
  Duration? _selStart;
  Duration? _selEnd;
  String? _trimmedFile;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((d) => setState(() => _pos = d));
    _player.onDurationChanged.listen((d) => setState(() => _len = d));
  }

  @override
  void dispose() {
    _player.dispose();
    _stepController.dispose();
    super.dispose();
  }

  double get _stepSeconds =>
      double.tryParse(_stepController.text.replaceAll(',', '.')) ?? 5.0;

  Future<void> _open() async {
    final res = await FilePicker.platform.pickFiles(
      type: _isVideo ? FileType.video : FileType.audio,
      initialDirectory: '/storage/emulated/0/acc-rec',
    );
    if (res != null && res.files.single.path != null) {
      _file = res.files.single.path;
      _selStart = null;
      _selEnd = null;
      _trimmedFile = null;
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

  Future<void> _seek(double seconds) async {
    final d = _pos + Duration(milliseconds: (seconds * 1000).round());
    await _player.seek(d < Duration.zero ? Duration.zero : d);
  }

  void _markSelection() {
    setState(() {
      if (_selStart == null) {
        _selStart = _pos;
      } else if (_selEnd == null) {
        _selEnd = _pos;
      } else {
        _selStart = _pos;
        _selEnd = null;
      }
      _trimmedFile = null;
    });
  }

  // این متن فقط برای صفحه‌خوان استفاده می‌شود، نه به عنوان متن روی دکمه
  String _selectionButtonLabel() {
    if (_selStart == null) return 'علامت‌گذاری شروع انتخاب';
    if (_selEnd == null) return 'علامت‌گذاری پایان انتخاب';
    return 'انتخاب کامل شد، برای انتخاب تازه دوباره فشار دهید';
  }

  // نماد کوچک روی دکمه‌ی انتخاب، به‌جای متن طولانی
  IconData _selectionButtonIcon() {
    if (_selStart == null) return Icons.fiber_manual_record;
    if (_selEnd == null) return Icons.stop;
    return Icons.restart_alt;
  }

  Future<void> _trim() async {
    if (_file == null || _selStart == null || _selEnd == null) return;
    if (_selEnd! <= _selStart!) {
      _snack('پایان انتخاب باید بعد از شروع باشد');
      return;
    }
    setState(() => _isBusy = true);
    try {
      final tempDir = await getTemporaryDirectory();
      final ext = _isVideo ? 'mp4' : 'mp3';
      final outPath =
          '${tempDir.path}/trim_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final startSec = _selStart!.inMilliseconds / 1000.0;
      final durSec =
          (_selEnd! - _selStart!).inMilliseconds / 1000.0;

      final command = _isVideo
          ? '-y -i "${_file!}" -ss $startSec -t $durSec '
              '-c:v libx264 -preset veryfast -c:a aac "$outPath"'
          : '-y -ss $startSec -i "${_file!}" -t $durSec '
              '-c:a libmp3lame -q:a 2 "$outPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        setState(() {
          _trimmedFile = outPath;
          _isBusy = false;
        });
        _snack('برش انجام شد. حالا می‌توانید ذخیره کنید');
      } else {
        setState(() => _isBusy = false);
        _snack('برش انجام نشد. لطفاً دوباره تلاش کنید');
      }
    } catch (e) {
      setState(() => _isBusy = false);
      _snack('خطا در برش فایل');
    }
  }

  Future<void> _save() async {
    if (_trimmedFile == null) return;
    final ext = _trimmedFile!.split('.').last;
    final defaultBase = 'cut_${DateTime.now().millisecondsSinceEpoch}';
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
    if (chosenBase == null || chosenBase.isEmpty) return;
    final chosen = '$chosenBase.$ext';

    final granted = await Permission.manageExternalStorage.request();
    if (!granted.isGranted) {
      _snack('دسترسی به حافظه داده نشد');
      return;
    }
    try {
      // همان پوشه‌ای که تب ضبط استفاده می‌کند، تا هر دو تب یک پوشه ببینند
      final folder = Directory('/storage/emulated/0/acc-rec');
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      final destPath = '${folder.path}/$chosen';
      await File(_trimmedFile!).copy(destPath);
      setState(() {
        _trimmedFile = null;
        _selStart = null;
        _selEnd = null;
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

  @override
  Widget build(BuildContext context) {
    final canTrim = _selStart != null && _selEnd != null && !_isBusy;
    final canSave = _trimmedFile != null && !_isBusy;
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
                      onChanged: (v) => setState(() => _isVideo = v ?? false),
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
                      onChanged: (v) => setState(() => _isVideo = v ?? true),
                    ),
                    const Text('تصویر'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // نمایشگر زمان و گام پرش، درست زیر ردیف صدا و تصویر
          Semantics(
            label:
                'موقعیت پخش: ${_pos.inSeconds} ثانیه از ${_len.inSeconds} ثانیه',
            child: Text(
              '${_pos.inSeconds} / ${_len.inSeconds} ثانیه',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('میزان پرش (ثانیه): '),
              SizedBox(
                width: 70,
                child: Semantics(
                  label: 'مقدار پرش به جلو یا عقب به ثانیه',
                  child: TextField(
                    controller: _stepController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          if (_selStart != null)
            Text(
              _selEnd != null
                  ? 'انتخاب: ${_selStart!.inSeconds} تا ${_selEnd!.inSeconds} ثانیه'
                  : 'شروع انتخاب: ${_selStart!.inSeconds} ثانیه',
            ),
          if (_isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('در حال برش…'),
            ),
          // وسط صفحه فقط برای پیش‌نمایش تصویر در نظر گرفته شده است، خالی می‌ماند
          Expanded(
            child: Center(
              child: SizedBox.shrink(),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                label: 'پرش به ابتدا',
                button: true,
                child: IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: _file == null ? null : () => _seek(-_pos.inSeconds.toDouble()),
                ),
              ),
              Semantics(
                label: '${_stepSeconds.toStringAsFixed(1)} ثانیه عقب',
                button: true,
                child: IconButton(
                  icon: const Icon(Icons.replay_5),
                  onPressed: _file == null ? null : () => _seek(-_stepSeconds),
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
                label: '${_stepSeconds.toStringAsFixed(1)} ثانیه جلو',
                button: true,
                child: IconButton(
                  icon: const Icon(Icons.forward_5),
                  onPressed: _file == null ? null : () => _seek(_stepSeconds),
                ),
              ),
              Semantics(
                label: 'پرش به انتها',
                button: true,
                child: IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: _file == null
                      ? null
                      : () => _seek((_len - _pos).inSeconds.toDouble()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Semantics(
                label: 'انتخاب فایل برای ویرایش',
                button: true,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('انتخاب فایل'),
                  onPressed: _open,
                ),
              ),
              Semantics(
                label: _selectionButtonLabel(),
                button: true,
                child: IconButton(
                  icon: Icon(_selectionButtonIcon()),
                  onPressed: _file == null ? null : _markSelection,
                ),
              ),
              Semantics(
                label: 'برش بخش انتخاب‌شده',
                button: true,
                child: FilledButton.icon(
                  icon: const Icon(Icons.content_cut),
                  label: const Text('برش'),
                  onPressed: canTrim ? _trim : null,
                ),
              ),
              Semantics(
                label: 'ذخیره فایل ویرایش‌شده',
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
