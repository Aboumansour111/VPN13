import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  final store = const FlutterSecureStorage();
  final username = TextEditingController(text: 'admin');
  final password = TextEditingController();

  String? token;
  List<dynamic> rows = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    restore();
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  void msg(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> restore() async {
    final saved = await store.read(key: 'admin_token');
    if (!mounted) return;
    if (saved != null) {
      token = saved;
      await list();
    } else {
      setState(() {});
    }
  }

  Future<void> login() async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/admin/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username.text.trim(),
              'password': password.text,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        final detail = jsonDecode(response.body)['detail'] ?? 'ورود ناموفق';
        throw Exception(detail);
      }

      token = jsonDecode(response.body)['access_token'] as String;
      await store.write(key: 'admin_token', value: token);
      password.clear();
      if (mounted) setState(() {});
      await list();
    } catch (error) {
      msg('خطا در ورود: $error');
    }
  }

  Future<void> logout() async {
    await store.delete(key: 'admin_token');
    token = null;
    rows = [];
    if (mounted) setState(() {});
  }

  Future<void> list() async {
    if (token == null) return;
    if (mounted) setState(() => loading = true);

    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/api/admin/servers'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401 || response.statusCode == 403) {
        await logout();
        msg('نشست مدیر منقضی شده است؛ دوباره وارد شوید.');
      } else if (response.statusCode == 200) {
        rows = jsonDecode(response.body) as List<dynamic>;
      } else {
        throw Exception('دریافت فهرست سرورها ناموفق بود: ${response.statusCode}');
      }
    } catch (error) {
      msg('خطا در دریافت سرورها: $error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit([Map<String, dynamic>? item]) async {
    final name = TextEditingController(text: item?['name'] ?? '');
    final config = TextEditingController(text: item?['config'] ?? '');
    final description =
        TextEditingController(text: item?['description'] ?? '');
    final order = TextEditingController(
      text: '${item?['sort_order'] ?? 0}',
    );
    final formKey = GlobalKey<FormState>();
    bool active = item?['active'] ?? true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(item == null ? 'افزودن سرور' : 'ویرایش سرور'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'نام سرور'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'نام سرور لازم است'
                              : null,
                    ),
                    TextFormField(
                      controller: config,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'کانفیگ (لینک یا JSON)',
                        alignLabelWithHint: true,
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'کانفیگ لازم است'
                              : null,
                    ),
                    TextFormField(
                      controller: description,
                      decoration:
                          const InputDecoration(labelText: 'توضیحات'),
                    ),
                    TextFormField(
                      controller: order,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ترتیب نمایش (عدد کمتر، بالاتر)',
                      ),
                      validator: (value) =>
                          int.tryParse(value ?? '') == null ||
                                  int.parse(value!) < 0
                              ? 'یک عدد صفر یا بزرگ‌تر وارد کنید'
                              : null,
                    ),
                    SwitchListTile(
                      value: active,
                      onChanged: (value) =>
                          setDialogState(() => active = value),
                      title: const Text('سرور فعال باشد'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('لغو'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && token != null) {
      try {
        final body = jsonEncode({
          'name': name.text.trim(),
          'config': config.text.trim(),
          'description':
              description.text.trim().isEmpty ? null : description.text.trim(),
          'active': active,
          'sort_order': int.parse(order.text),
        });
        final url = Uri.parse(
          '${AppConfig.apiBaseUrl}/api/admin/servers'
          '${item == null ? '' : '/${item['id']}'}',
        );
        final headers = {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        };
        final response = item == null
            ? await http.post(url, headers: headers, body: body)
            : await http.put(url, headers: headers, body: body);

        if (response.statusCode < 300) {
          await list();
        } else {
          msg('ذخیره سرور ناموفق بود: ${response.body}');
        }
      } catch (error) {
        msg('خطا در ذخیره سرور: $error');
      }
    }

    name.dispose();
    config.dispose();
    description.dispose();
    order.dispose();
  }

  Future<void> remove(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف سرور؟'),
        content: Text('سرور «${item['name']}» حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || token == null) return;

    try {
      final response = await http.delete(
        Uri.parse(
          '${AppConfig.apiBaseUrl}/api/admin/servers/${item['id']}',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 204) {
        await list();
      } else {
        msg('حذف سرور ناموفق بود: ${response.body}');
      }
    } catch (error) {
      msg('خطا در حذف سرور: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VPN13 | مدیریت سرورها'),
        actions: [
          if (token != null)
            IconButton(
              onPressed: () => edit(),
              tooltip: 'افزودن سرور',
              icon: const Icon(Icons.add),
            ),
          if (token != null)
            IconButton(
              onPressed: logout,
              tooltip: 'خروج مدیر',
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: token == null
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.admin_panel_settings, size: 64),
                      const SizedBox(height: 24),
                      TextField(
                        controller: username,
                        decoration:
                            const InputDecoration(labelText: 'نام مدیر'),
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        controller: password,
                        obscureText: true,
                        onSubmitted: (_) => login(),
                        decoration:
                            const InputDecoration(labelText: 'رمز عبور'),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: loading ? null : login,
                        child: const Text('ورود مدیر'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: list,
                  child: rows.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('هنوز سروری اضافه نشده است')),
                          ],
                        )
                      : ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final item =
                                Map<String, dynamic>.from(rows[index] as Map);
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              child: ListTile(
                                title: Text(item['name'] as String),
                                subtitle: Text(
                                  item['active'] == true ? 'فعال' : 'غیرفعال',
                                ),
                                trailing: Wrap(
                                  children: [
                                    IconButton(
                                      onPressed: () => edit(item),
                                      tooltip: 'ویرایش',
                                      icon: const Icon(Icons.edit),
                                    ),
                                    IconButton(
                                      onPressed: () => remove(item),
                                      tooltip: 'حذف',
                                      icon: const Icon(Icons.delete),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
