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
      SnackBar(
        content: const Text('Настройки сохранены', style: TextStyle(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _testConnection() async {
    setState(() => _status = 'Проверка связи...');
    try {
      final response = await http.get(Uri.parse('http://${_ipController.text}:8001/docs')).timeout(const Duration(seconds: 3));
      if (mounted) setState(() => _status = response.statusCode == 200 ? 'Успешно! Сервер доступен.' : 'Ошибка: ${response.statusCode}');
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
    _ipController.dispose();
    _geminiTestController.dispose();
    super.dispose();
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0, top: 24.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Настройки', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 40.0 : 20.0,
              vertical: 24.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Блок сервера
                _buildSectionHeader('Сервер (Backend)', Icons.dns_rounded),
                _buildCard(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Укажите локальный IP-адрес сервера обработки ИИ и звонков. Если сервер и устройство в одной сети - введите IPv4 адрес компьютера.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _ipController,
                          decoration: const InputDecoration(
                            labelText: 'IP Адрес',
                            prefixIcon: Icon(Icons.router),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _testConnection,
                                icon: const Icon(Icons.wifi_tethering),
                                label: const Text('Тест связи'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _saveSettings,
                                icon: const Icon(Icons.save_rounded),
                                label: const Text('Сохранить'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 2. Блок тестирования нейросетей
                _buildSectionHeader('Диагностика Нейросетей', Icons.psychology_rounded),
                _buildCard(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Статус
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: _status.contains('Ошибка') 
                                ? Colors.red.withOpacity(0.08) 
                                : _status.contains('Успешно') || _status.contains('Gemini')
                                    ? Colors.green.withOpacity(0.08)
                                    : Theme.of(context).colorScheme.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _status.contains('Ошибка') 
                                  ? Colors.red.withOpacity(0.3) 
                                  : _status.contains('Успешно') || _status.contains('Gemini')
                                      ? Colors.green.withOpacity(0.3)
                                      : Theme.of(context).colorScheme.primary.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _status.contains('Ошибка') ? Icons.error_outline : Icons.info_outline,
                                color: _status.contains('Ошибка') ? Colors.red : Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  _status.isEmpty ? 'Система готова к тестам' : _status,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: _status.contains('Ошибка') 
                                        ? Colors.red 
                                        : Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        const Text('Синтез речи (TTS)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _testTTS, 
                            icon: const Icon(Icons.volume_up), 
                            label: const Text('Проверить голос ассистента'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                              foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Divider(height: 1),
                        ),

                        const Text('Языковая модель (LLM)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _geminiTestController,
                          decoration: const InputDecoration(
                            labelText: 'Запрос для Gemini',
                            prefixIcon: Icon(Icons.chat_bubble_outline),
                          ),
                          maxLines: null,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _testGemini, 
                            icon: const Icon(Icons.auto_awesome), 
                            label: const Text('Отправить запрос Gemini'),
                          ),
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Divider(height: 1),
                        ),

                        const Text('Распознавание речи (STT)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isListening ? null : _startListen,
                                icon: const Icon(Icons.mic),
                                label: const Text('Слушать'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: !_isListening ? null : _stopListen,
                                icon: const Icon(Icons.mic_off),
                                label: const Text('Стоп'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Container(
                          height: 220,
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.terminal, color: Colors.greenAccent.shade400, size: 20),
                                  const SizedBox(width: 8),
                                  const Text('Лог транскрипции', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: _voiceLogs.isEmpty
                                  ? const Center(child: Text('Ожидание транскрипции...\nНажмите "Слушать".', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, height: 1.5)))
                                  : ListView.builder(
                                      itemCount: _voiceLogs.length,
                                      reverse: true, // Auto-scroll to bottom behavior
                                      itemBuilder: (ctx, i) {
                                        // Reverse list view means index 0 is at bottom.
                                        final index = _voiceLogs.length - 1 - i;
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('> ', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                              Expanded(
                                                child: Text(
                                                  _voiceLogs[index], 
                                                  style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)
                                                )
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                    ),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 48), // Padding at the bottom
              ],
            ),
          ),
        ),
      ),
    );
  }
}
