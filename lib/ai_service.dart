import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// تنظیمات هوش مصنوعی: آدرس سرویس و کلید API
class AiSettings {
  final String baseUrl;
  final String apiKey;
  const AiSettings(this.baseUrl, this.apiKey);

  static const String defaultBaseUrl = 'https://api.gapgpt.app/v1';

  static Future<AiSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final base = p.getString('ai_base_url')?.trim() ?? '';
    final key = p.getString('ai_api_key')?.trim() ?? '';
    return AiSettings(base.isEmpty ? defaultBaseUrl : base, key);
  }

  static Future<void> save(String baseUrl, String apiKey) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ai_base_url', baseUrl.trim());
    await p.setString('ai_api_key', apiKey.trim());
  }
}

class AiException implements Exception {
  final String message;
  AiException(this.message);
  @override
  String toString() => message;
}

/// کارهای هوش مصنوعی: تشخیص گفتار، ترجمه و ساخت صدای انگلیسی
/// سرویس طوری نوشته شده که با درگاه سازگار با OpenAI کار کند.
class AiService {
  final AiSettings s;
  AiService(this.s);

  Map<String, String> get _auth => {'Authorization': 'Bearer ${s.apiKey}'};

  void _check(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw AiException('خطای سرویس، کد ${r.statusCode}');
    }
  }

  /// آزمایش کلید: فهرست مدل‌ها را می‌گیرد
  Future<void> testKey() async {
    final r = await http
        .get(Uri.parse('${s.baseUrl}/models'), headers: _auth)
        .timeout(const Duration(seconds: 30));
    _check(r);
  }

  /// تبدیل صدا به متن
  Future<String> transcribe(File audio) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('${s.baseUrl}/audio/transcriptions'))
      ..headers.addAll(_auth)
      ..fields['model'] = 'whisper-1'
      ..files.add(await http.MultipartFile.fromPath('file', audio.path));
    final streamed = await req.send().timeout(const Duration(minutes: 10));
    final r = await http.Response.fromStream(streamed);
    _check(r);
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    return (j['text'] as String?) ?? '';
  }

  /// ترجمه متن به انگلیسی
  Future<String> translateToEnglish(String text) async {
    final r = await http
        .post(
          Uri.parse('${s.baseUrl}/chat/completions'),
          headers: {..._auth, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': 'gpt-4o-mini',
            'messages': [
              {
                'role': 'system',
                'content':
                    'Translate the user text into natural English. Return only the translation.'
              },
              {'role': 'user', 'content': text},
            ],
          }),
        )
        .timeout(const Duration(minutes: 5));
    _check(r);
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final choices = j['choices'] as List;
    final msg = (choices.first as Map)['message'] as Map;
    return (msg['content'] as String?) ?? '';
  }

  /// ساخت صدای انگلیسی از متن و ذخیره در فایل خروجی
  Future<void> speak(String text, File out) async {
    final r = await http
        .post(
          Uri.parse('${s.baseUrl}/audio/speech'),
          headers: {..._auth, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': 'tts-1',
            'voice': 'alloy',
            'input': text,
            'response_format': 'mp3',
          }),
        )
        .timeout(const Duration(minutes: 10));
    _check(r);
    await out.writeAsBytes(r.bodyBytes);
  }
}
