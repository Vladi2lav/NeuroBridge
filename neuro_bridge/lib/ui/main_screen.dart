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
      description: "Главный экран приложения NeuroBridge. Здесь можно создать комнату или присоединиться к ней по номеру.",
      availableActions: {
         "CREATE_ROOM": "Создать новую комнату для звонка",
         "JOIN_ROOM": "Присоединиться по коду. ТЕГ должен содержать код: [ACTION:JOIN_ROOM|кодизцифр]",
         "OPEN_SETTINGS": "Открыть настройки приложения",
      },
      onAction: (action) {
         if (action == "CREATE_ROOM") {
             _createRoom();
         } else if (action.startsWith("JOIN_ROOM|")) {
             final code = action.split("|")[1].trim();
             _roomController.text = code;
             _joinRoom();
         } else if (action == "OPEN_SETTINGS") {
             context.push('/settings');
         }
      }
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

    // Запускаем бесконечный цикл: говорим, слушаем, ждем, повторяем,
    // пока пользователь не ответит голосом или не нажмет кнопку в UI
    bool answered = false;
    while (!answered && mounted && _isWelcomeDialogOpen) {
        await VoiceAssistant().speak(welcomeText);
        
        if (!mounted || !_isWelcomeDialogOpen) break;
        String answer = await VoiceAssistant().listenOnce();

        if (answer.isNotEmpty && mounted && _isWelcomeDialogOpen) {
            answered = true;
            VoiceAssistant().determineBlindness(answer, (blind) {
               if (mounted && _isWelcomeDialogOpen) {
                  _isWelcomeDialogOpen = false;
                  Navigator.pop(context); // закрываем диалог
                  if (blind) {
                      _enableBlind();
                  } else {
                      VoiceAssistant().disableBlindMode();
                  }
               }
            });
        }
        
        // Если ответ не получен и диалог всё ещё открыт, ждём 5 секунд перед повтором
        if (!answered && mounted && _isWelcomeDialogOpen) {
            await Future.delayed(const Duration(seconds: 5));
        }
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
    final isDesktop = MediaQuery.of(context).size.width > 800;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('NeuroBridge', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: Icon(Icons.settings_outlined, color: Theme.of(context).colorScheme.primary),
              onPressed: () => context.push('/settings'),
              tooltip: 'Настройки',
            ),
          )
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 64.0 : 24.0,
              vertical: isDesktop ? 48.0 : 24.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Текст приветствия
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                    children: [
                      const TextSpan(text: 'Инклюзивное общение\nбез '),
                      TextSpan(
                        text: 'границ',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Создавайте комнаты, подключайтесь к звонкам и используйте персонализированные инструменты доступности.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                
                SizedBox(height: isDesktop ? 64 : 40),

                // Основной блок действий
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (isDesktop) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildCreateRoomSection(),
                          ),
                          const SizedBox(width: 40),
                          Expanded(
                            child: _buildJoinRoomSection(),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildCreateRoomSection(),
                          const SizedBox(height: 32),
                          const Row(
                            children: [
                              Expanded(child: Divider()),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('ИЛИ', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                              Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 32),
                          _buildJoinRoomSection(),
                        ],
                      );
                    }
                  },
                ),
                
                SizedBox(height: isDesktop ? 48 : 32),
                
                // Профиль адаптации вынесен ниже
                if (!VoiceAssistant().isBlindModeActive)
                  _buildProfileCard(),
                  
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateRoomSection() {
    return Container(
      padding: const EdgeInsets.all(32),
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
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.video_call_rounded, size: 32, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 24),
          const Text(
            'Начать встречу',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Создайте новую защищенную комнату и пригласите участников.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), height: 1.5),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _createRoom,
              icon: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add),
              label: Text(
                _isLoading ? 'Создание...' : 'Новая комната', 
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinRoomSection() {
    return Container(
      padding: const EdgeInsets.all(32),
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
        border: Border.all(color: Theme.of(context).colorScheme.secondary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.meeting_room_rounded, size: 32, color: Theme.of(context).colorScheme.secondary),
          ),
          const SizedBox(height: 24),
          const Text(
            'Присоединиться',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Введите код встречи, предоставленный организатором.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), height: 1.5),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _roomController,
            decoration: InputDecoration(
              labelText: 'Код комнаты',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              prefixIcon: Icon(Icons.dialpad, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            ),
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _joinRoom(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _joinRoom,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text('Присоединиться', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.accessibility_new_rounded, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              const Text(
                'Профиль адаптации',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
    );
  }
}
