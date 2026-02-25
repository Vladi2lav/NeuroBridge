import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'multi_select_dropdown.dart';
import '../core/services/voice_assistant.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _roomController = TextEditingController();
  List<String> _selectedProfiles = ['Нет нарушений'];
  bool _isLoading = false;

  final List<String> _profiles = [
    'Нет нарушений',
    'Нарушения зрения', // Слепота
    'Нарушения речи',   // Немота
    'Нарушения слуха',  // Глухота
    'СДВГ',
    'Когнитивные трудности', // Тупой
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile().then((_) {
       _initVoice();
    });
  }

  Future<void> _initVoice() async {
    await VoiceAssistant().init();
    
    VoiceAssistant().currentContext = VoiceCommandContext(
      screenName: "MainScreen",
      onCreateRoom: () => _createRoom(),
      onJoinRoom: (code) {
         _roomController.text = code;
         _joinRoom();
      },
      onJoinCall: () {}
    );

    if (_selectedProfiles.contains("Нарушения зрения")) {
       VoiceAssistant().activateBlindMode();
    } else if (_selectedProfiles.length == 1 && _selectedProfiles.first == "Нет нарушений") {
       _runWelcomeRoutine();
    }
  }

  bool _isWelcomeDialogOpen = false;

  void _runWelcomeRoutine() async {
    if (!mounted) return;

    // Сразу показываем окно до того как загрузится ответ от Gemini, 
    // чтобы пользователь не ждал текста перед тем как увидеть само всплывающее окно
    _isWelcomeDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Окно адаптации'),
        content: const Text('...'), // Будет обновлено, или останется таким пока говорит ИИ
        actions: [
          TextButton(onPressed: () {
            if (_isWelcomeDialogOpen) {
               _isWelcomeDialogOpen = false;
               Navigator.pop(ctx);
               VoiceAssistant().stop();
               VoiceAssistant().disableBlindMode();
            }
          }, child: const Text('Да, я вижу (отключить ИИ)')),
          TextButton(onPressed: () { 
            if (_isWelcomeDialogOpen) {
               _isWelcomeDialogOpen = false;
               Navigator.pop(ctx);
               VoiceAssistant().stop();
               _enableBlind();
            }
          }, child: const Text('Нет, я не вижу (включить ИИ)')),
        ],
      )
    );

    final welcomeText = await VoiceAssistant().generateWelcomeSpeech();

    if (!mounted || !_isWelcomeDialogOpen) return;

    // Закрываем окно с загрузкой и показываем с реальным текстом
    Navigator.pop(context);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Окно адаптации'),
        content: Text(welcomeText),
        actions: [
          TextButton(onPressed: () {
            if (_isWelcomeDialogOpen) {
               _isWelcomeDialogOpen = false;
               Navigator.pop(ctx);
               VoiceAssistant().stop();
               VoiceAssistant().disableBlindMode();
            }
          }, child: const Text('Да, я вижу (отключить ИИ)')),
          TextButton(onPressed: () { 
            if (_isWelcomeDialogOpen) {
               _isWelcomeDialogOpen = false;
               Navigator.pop(ctx);
               VoiceAssistant().stop();
               _enableBlind();
            }
          }, child: const Text('Нет, я не вижу (включить ИИ)')),
        ],
      )
    );

    // Играем закешированное сгенерированное аудио без лишних запросов к API
    await VoiceAssistant().speakWelcomeAudio();
    String answer = await VoiceAssistant().listenOnce();

    if (answer.isNotEmpty && mounted && _isWelcomeDialogOpen) {
        VoiceAssistant().determineBlindness(answer, (blind) {
           if (mounted && _isWelcomeDialogOpen) {
              _isWelcomeDialogOpen = false;
              Navigator.pop(context);
              if (blind) {
                  _enableBlind();
              } else {
                  VoiceAssistant().disableBlindMode();
              }
           }
        });
    }
  }

  void _enableBlind() {
     _saveProfile(['Нарушения зрения']);
     VoiceAssistant().activateBlindMode();
     setState(() {}); // redraw to hide dropdown
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedProfiles = prefs.getStringList('user_profiles') ?? ['Нет нарушений'];
    });
  }

  Future<void> _saveProfile(List<String> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('user_profiles', values);
    setState(() {
      _selectedProfiles = values;
    });
  }

  Future<void> _createRoom() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final ip = prefs.getString('backend_ip') ?? '192.168.123.5';
      final response = await http.get(Uri.parse('http://$ip:8001/api/rooms/available')).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final roomId = data['room_id'];
        if (mounted) {
           context.push('/room/$roomId', extra: true); // true means isCreator
        }
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка создания комнаты: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _joinRoom() {
    if (_roomController.text.isNotEmpty) {
      context.push('/room/${_roomController.text}', extra: false); // false means join
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите номер комнаты')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NeuroBridge'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
            tooltip: 'Настройки',
          )
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              // Выбор профиля
              if (!VoiceAssistant().isBlindModeActive)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ваш профиль адаптации',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        MultiSelectDropdown(
                          items: _profiles,
                          selectedItems: _selectedProfiles,
                          onChanged: (val) {
                            _saveProfile(val);
                            if (val.contains("Нарушения зрения")) {
                               VoiceAssistant().activateBlindMode();
                               setState((){});
                            } else {
                               VoiceAssistant().disableBlindMode();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              
              const Spacer(),

              // Кнопка Создать
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _createRoom,
                icon: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_circle_outline),
                label: Text(_isLoading ? 'Создание...' : 'Создать комнату', style: const TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              
              const SizedBox(height: 32),
              
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('ИЛИ', style: TextStyle(color: Colors.grey))),
                  Expanded(child: Divider()),
                ],
              ),
              
              const SizedBox(height: 32),

              // Поле ввода и кнопка Присоединиться
              TextField(
                controller: _roomController,
                decoration: InputDecoration(
                  labelText: 'Номер комнаты',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  prefixIcon: const Icon(Icons.meeting_room),
                ),
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _joinRoom(),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _joinRoom,
                icon: const Icon(Icons.group_add),
                label: const Text('Присоединиться', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const Spacer(),
            ],
          ),
         ),
        ),
       ),
      ),
    );
  }
}
