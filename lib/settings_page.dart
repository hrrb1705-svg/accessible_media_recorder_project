import 'package:flutter/material.dart';

import 'ai_service.dart';

/// صفحه‌ی تنظیمات: آدرس سرویس و کلید API هوش مصنوعی
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _keyCtrl = TextEditingController();
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
      _keyCtrl.text = s.apiKey;
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await AiSettings.save(_urlCtrl.text, _keyCtrl.text);
    if (!mounted) return;
    setState(() => _status = 'تنظیمات ذخیره شد');
  }

  Future<void> _test() async {
    await AiSettings.save(_urlCtrl.text, _keyCtrl.text);
    setState(() {
      _testing = true;
      _status = 'در حال آزمایش کلید…';
    });
    String result;
    try {
      await AiService(await AiSettings.load()).testKey();
      result = 'کلید درست است و سرویس پاسخ داد';
    } catch (e) {
      result = 'آزمایش انجام نشد. ${e.toString()}. آدرس و کلید را بررسی کنید';
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _status = result;
    });
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
              labelText: 'آدرس سرویس هوش مصنوعی',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'کلید API',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
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
                  onPressed: _testing ? null : _test,
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
