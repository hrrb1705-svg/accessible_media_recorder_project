import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// تنظیمات هوش مصنوعی: آدرس اندپوینت، کلید API و نام مدل‌ها
class AiSettings {
  final String baseUrl;
  final String apiKey;
  final String chatModel;
  final String sttModel;
  final String ttsModel;
  const AiSettings(this.baseUrl, this.apiKey,
      [this.chatModel = defaultChatModel,
      this.sttModel = defaultSttModel,
      this.ttsModel = defaultTtsModel]);

  static const String defaultBaseUrl = 'https://api.gapgpt.ir/v1';
  static const String defaultChatModel = 'gpt-4o-mini';
  static const String defaultSttModel = 'whisper-1';
  static const String defaultTtsModel = 'tts-1';

  /// اگر کاربر آدرس کامل یک مسیر را بگذارد، بخش آخر حذف می‌شود
  static String normalize(String u) {
    var x = u.trim();
    for (final suffix in [
      '/chat/completions',
      '/audio/transcriptions',
      '/audio/speech',
      '/models',
    ]) {
      if (x.endsWith(suffix)) {
        x = x.substring(0, x.length - suffix.length);
      }
    }
    while (x.endsWith('/')) {
      x = x.substring(0, x.length - 1);
    }
    return x;
  }

  static Future<AiSettings> load() async {
    final p = await SharedPreferences.getInstance();
    String g(String k, String d) {
      final v = p.getString(k)?.trim() ?? '';
      return v.isEmpty ? d : v;
    }

    return AiSettings(
      normalize(g('ai_base_url', defaultBaseUrl)
          .replaceAll('gapgpt.app', 'gapgpt.ir')),
      p.getString('ai_api_key')?.trim() ?? '',
      g('ai_chat_model', defaultChatModel),
      g('ai_stt_model', defaultSttModel),
      g('ai_tts_model', defaultTtsModel),
    );
  }

  /// فهرست سه مدل و شماره‌ی انتخاب‌شده برای هر نقش
  static Future<(List<String>, int)> loadList(String role, String def) async {
    final p = await SharedPreferences.getInstance();
    var l = p.getStringList('ai_${role}_list') ?? [];
    if (l.length != 3) {
      final cur = p.getString('ai_${role}_model')?.trim() ?? '';
      l = [cur.isEmpty ? def : cur, '', ''];
    }
    var i = p.getInt('ai_${role}_sel') ?? 0;
    if (i < 0 || i > 2) i = 0;
    return (l, i);
  }

  static Future<void> saveList(String role, List<String> l, int sel) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('ai_${role}_list', l.map((e) => e.trim()).toList());
    await p.setInt('ai_${role}_sel', sel);
  }

  static Future<void> save(String baseUrl, String apiKey,
      {String chat = '', String stt = '', String tts = ''}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ai_base_url', normalize(baseUrl));
    await p.setString('ai_api_key', apiKey.trim());
    await p.setString('ai_chat_model', chat.trim());
    await p.setString('ai_stt_model', stt.trim());
    await p.setString('ai_tts_model', tts.trim());
  }
}

/// ثبت حداکثر ده خطای اخیر (جدیدترین اول)
class ErrorLog {
  static const _k = 'error_log';

  static Future<List<String>> all() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_k) ?? <String>[];
  }

  static Future<void> add(String where, Object e) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_k) ?? <String>[];
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    list.insert(0, '$stamp | $where | $e');
    while (list.length > 10) {
      list.removeLast();
    }
    await p.setStringList(_k, list);
  }

  static Future<void> removeAt(int i) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_k) ?? <String>[];
    if (i >= 0 && i < list.length) list.removeAt(i);
    await p.setStringList(_k, list);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_k);
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
      var body = utf8.decode(r.bodyBytes, allowMalformed: true);
      if (body.length > 400) body = body.substring(0, 400);
      throw AiException(
          'خطای سرویس، کد ${r.statusCode}، آدرس ${r.request?.url}، پاسخ: $body');
    }
  }

  /// آزمایش کلید: فهرست مدل‌ها را می‌گیرد
  Future<void> testKey() async {
    final r = await http
        .get(Uri.parse('${s.baseUrl}/models'), headers: _auth)
        .timeout(const Duration(seconds: 30));
    _check(r);
  }

  /// آزمایش مدل انتخاب‌شده برای یک نقش: chat، stt یا tts
  Future<void> testModel(String role) async {
    if (role == 'chat') {
      final r = await http
          .post(Uri.parse('${s.baseUrl}/chat/completions'),
              headers: {..._auth, 'Content-Type': 'application/json'},
              body: jsonEncode({
                'model': s.chatModel,
                'max_tokens': 5,
                'messages': [
                  {'role': 'user', 'content': 'hi'}
                ],
              }))
          .timeout(const Duration(seconds: 40));
      _check(r);
    } else if (role == 'tts') {
      final r = await http
          .post(Uri.parse('${s.baseUrl}/audio/speech'),
              headers: {..._auth, 'Content-Type': 'application/json'},
              body: jsonEncode({
                'model': s.ttsModel,
                'voice': 'alloy',
                'input': 'hi',
                'response_format': 'mp3',
              }))
          .timeout(const Duration(seconds: 40));
      _check(r);
    } else {
      final r = await http
          .get(Uri.parse('${s.baseUrl}/models'), headers: _auth)
          .timeout(const Duration(seconds: 30));
      _check(r);
      if (!r.body.contains('"${s.sttModel}"')) {
        throw AiException('مدل ${s.sttModel} در فهرست مدل‌های سرویس نیست');
      }
    }
  }

  /// تبدیل صدا به متن
  Future<String> transcribe(File audio) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('${s.baseUrl}/audio/transcriptions'))
      ..headers.addAll(_auth)
      ..fields['model'] = s.sttModel
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
            'model': s.chatModel,
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
            'model': s.ttsModel,
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
