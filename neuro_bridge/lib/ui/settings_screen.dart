import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _ipController = TextEditingController(text: '192.168.123.5');
  String _status = '';
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('backend_ip');
    if (ip != null && ip.isNotEmpty) {
      _ipController.text = ip;
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_ip', _ipController.text);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Настройки сохранены')),
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _status = 'Проверка...';
    });
    try {
      final response = await http.get(Uri.parse('http://${_ipController.text}:8001/docs')).timeout(const Duration(seconds: 3));
      setState(() {
         _status = response.statusCode == 200 ? 'Успешно!' : 'Ошибка: ${response.statusCode}';
      });
    } catch (e) {
      setState(() {
         _status = 'Ошибка подключения к серверу';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки подключения')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'Backend IP Address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _testConnection,
                  child: const Text('Тест соединения'),
                ),
                ElevatedButton(
                  onPressed: _saveSettings,
                  child: const Text('Сохранить'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Статус: $_status', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
