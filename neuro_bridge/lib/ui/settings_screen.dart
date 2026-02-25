import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../core/services/voice_assistant.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _ipController = TextEditingController(text: '192.168.123.5');
  String _status = '';
  
  // AI Test states
  bool _isListening = false;
  final List<String> _voiceLogs = [];
  final TextEditingController _geminiTestController = TextEditingController(text: 'Привет, ты тут?');

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('backend_ip');
    if (ip != null && ip.isNotEmpty) {
      setState(() {
        _ipController.text = ip;
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_ip', _ipController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Настройки сохранены')),
    );
  }

  Future<void> _testConnection() async {
    setState(() => _status = 'Проверка...');
    try {
      final response = await http.get(Uri.parse('http://${_ipController.text}:8001/docs')).timeout(const Duration(seconds: 3));
      if (mounted) setState(() => _status = response.statusCode == 200 ? 'Успешно!' : 'Ошибка: ${response.statusCode}');
    } catch (e) {
      if (mounted) setState(() => _status = 'Ошибка подключения к серверу');
    }
  }

  // AI TESTS
  Future<void> _testTTS() async {
    await VoiceAssistant().init();
    await VoiceAssistant().testTTS("Проверка синтеза речи прошла успешно.");
  }

  Future<void> _testGemini() async {
    setState(() => _status = 'Жду ответа от Gemini...');
    await VoiceAssistant().init();
    final answer = await VoiceAssistant().testGemini(_geminiTestController.text);
    if (mounted) setState(() => _status = 'Gemini: $answer');
  }

  void _startListen() async {
    await VoiceAssistant().init();
    VoiceAssistant().startRawListening(
       (text) {
         if (mounted) {
           setState(() {
             _voiceLogs.add(text);
           });
         }
       },
       (running) {
         if (mounted) setState(() => _isListening = running);
       }
    );
  }

  void _stopListen() {
    VoiceAssistant().stopRawListening((running) {
       if (mounted) setState(() => _isListening = running);
    });
  }

  @override
  void dispose() {
    _stopListen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки и Диагностика Нейро')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Блок сервера
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Сервер (Backend)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(labelText: 'Backend IP Address'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ElevatedButton(onPressed: _testConnection, child: const Text('Тест сервера')),
                          const SizedBox(width: 10),
                          ElevatedButton(onPressed: _saveSettings, child: const Text('Сохранить конфиг')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 2. Блок тестирования нейросетей
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Тестирование нейросетей (Neuro API)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      
                      // Статус / Логи
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                        child: Text(_status.isEmpty ? 'Статус систем: Ожидание' : _status, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 16),
                      
                      const Text('TTS (Синтез речи)'),
                      ElevatedButton.icon(
                        onPressed: _testTTS, 
                        icon: const Icon(Icons.volume_up), 
                        label: const Text('Произнести проверочную фразу')
                      ),
                      const Divider(height: 30),

                      const Text('LLM (Gemini 1.5 Flash)'),
                      TextField(
                        controller: _geminiTestController,
                        decoration: const InputDecoration(labelText: 'Сообщение для нейросети'),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _testGemini, 
                        icon: const Icon(Icons.smart_toy), 
                        label: const Text('Отправить запрос')
                      ),
                      const Divider(height: 30),

                      const Text('STT (Распознавание речи)'),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isListening ? null : _startListen,
                            icon: const Icon(Icons.mic),
                            label: const Text('Начать слушать'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: !_isListening ? null : _stopListen,
                            icon: const Icon(Icons.mic_off),
                            label: const Text('Остановить'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text('Распознанный текст:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Container(
                        height: 150,
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12)
                        ),
                        child: _voiceLogs.isEmpty
                          ? const Text('Ожидание речи...', style: TextStyle(color: Colors.white54))
                          : ListView.builder(
                              itemCount: _voiceLogs.length,
                              itemBuilder: (ctx, i) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text('- ${_voiceLogs[i]}', style: const TextStyle(color: Colors.white)),
                                );
                              }
                            ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
