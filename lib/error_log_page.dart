import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_service.dart';

/// ده خطای اخیر، جدیدترین اول
class ErrorLogPage extends StatefulWidget {
  const ErrorLogPage({super.key});

  @override
  State<ErrorLogPage> createState() => _ErrorLogPageState();
}

class _ErrorLogPageState extends State<ErrorLogPage> {
  List<String> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await ErrorLog.all();
    if (mounted) setState(() => _items = l);
  }

  void _msg(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('خطاهای اخیر'),
        actions: [
          TextButton(
            onPressed: _items.isEmpty
                ? null
                : () async {
                    await ErrorLog.clear();
                    await _load();
                    _msg('فهرست خطاها پاک شد');
                  },
            child: const Text('پاک کردن'),
          ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(child: Text('خطایی ثبت نشده است'))
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (c, i) => ListTile(
                title: Text('${i + 1}. ${_items[i]}'),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'کپی خطای ${i + 1}',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _items[i]));
                    _msg('خطای ${i + 1} کپی شد');
                  },
                ),
              ),
            ),
    );
  }
}
