import 'package:flutter/material.dart';

import 'ai_service.dart';

/// صفحه‌ی تنظیمات: آدرس سرویس و کلید API هوش مصنوعی
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

const _roles = [
  ('chat', 'ترجمه', AiSettings.defaultChatModel),
  ('stt', 'تبدیل گفتار به متن', AiSettings.defaultSttModel),
  ('tts', 'ساخت صدا', AiSettings.defaultTtsModel),
];

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _keyCtrl = TextEditingController();
  final Map<String, List<TextEditingController>> _c = {
    for (final r in _roles)
      r.$1: List.generate(3, (_) => TextEditingController())
  };
  final Map<String, int> _sel = {for (final r in _roles) r.$1: 0};
  String _savedKey = '';
  String _status = '';
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AiSettings.load();
    if (!mounted) return;
    setState(() {
      _urlCtrl.text = s.baseUrl;
      _savedKey = s.apiKey;
    });
    for (final r in _roles) {
      final (l, i) = await AiSettings.loadList(r.$1, r.$3);
      for (var k = 0; k < 3; k++) {
        _c[r.$1]![k].text = l[k];
      }
      _sel[r.$1] = i;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    for (final l in _c.values) {
      for (final x in l) {
        x.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _store() async {
    // اگر فیلد کلید خالی بماند، کلید ذخیره‌شده‌ی قبلی حفظ می‌شود
    final k = _keyCtrl.text.trim().isEmpty ? _savedKey : _keyCtrl.text.trim();
    String pick(String r) {
      final t = _c[r]![_sel[r]!].text.trim();
      return t;
    }

    for (final r in _roles) {
      await AiSettings.saveList(
          r.$1, _c[r.$1]!.map((e) => e.text).toList(), _sel[r.$1]!);
    }
    await AiSettings.save(_urlCtrl.text, k,
        chat: pick('chat'), stt: pick('stt'), tts: pick('tts'));
    final s = await AiSettings.load();
    if (!mounted) return;
    setState(() {
      _savedKey = s.apiKey;
      _urlCtrl.text = s.baseUrl;
      _keyCtrl.clear();
    });
  }

  Future<void> _save() async {
    await _store();
    if (!mounted) return;
    setState(() => _status =
        'تنظیمات ذخیره شد. طول کلید ذخیره‌شده ${_savedKey.length} نویسه است');
  }

  Future<void> _test([String role = 'chat']) async {
    await _store();
    setState(() {
      _testing = true;
      _status = 'در حال آزمایش کلید…';
    });
    String result;
    try {
      await AiService(await AiSettings.load()).testModel(role);
      result = 'آزمایش موفق بود. مدل انتخاب‌شده پاسخ داد';
    } catch (e) {
      await ErrorLog.add('آزمایش کلید', e);
      result = 'آزمایش انجام نشد. ${e.toString()}. آدرس و کلید را بررسی کنید';
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _status = result;
    });
  }

  Widget _group(String role, String title) {
    final names = ['اول', 'دوم', 'سوم'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('مدل $title',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          for (var i = 0; i < 3; i++)
            Row(
              children: [
                Semantics(
                  label: 'انتخاب مدل ${names[i]} برای $title',
                  child: Radio<int>(
                    value: i,
                    groupValue: _sel[role],
                    onChanged: _testing
                        ? null
                        : (v) {
                            setState(() => _sel[role] = v!);
                            _test(role);
                          },
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextField(
                      controller: _c[role]![i],
                      decoration: InputDecoration(
                        labelText: 'مدل ${names[i]} $title',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(
            header: true,
            child: Text(
              'هوش مصنوعی',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'برای ترجمه‌ی صدا به انگلیسی به یک کلید API نیاز است. کلید و آدرس سرویس را از سایت ارائه‌دهنده بگیرید و اینجا وارد کنید. کلید فقط داخل این گوشی ذخیره می‌شود.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'آدرس کامل API (تا بخش v1)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'کلید API',
              helperText: _savedKey.isEmpty
                  ? 'کلیدی ذخیره نشده است'
                  : 'کلید ذخیره‌شده دارد، ${_savedKey.length} نویسه. برای تغییر، کلید تازه را بنویسید',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          for (final r in _roles) _group(r.$1, r.$2),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _testing ? null : _save,
                  child: const Text('ذخیره تنظیمات'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing ? null : () => _test(),
                  child: const Text('آزمایش کلید'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(_status),
          ),
        ],
      ),
    );
  }
}
