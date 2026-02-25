import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _roomController = TextEditingController();
  String _selectedProfile = 'Нет нарушений';
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
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedProfile = prefs.getString('user_profile') ?? 'Нет нарушений';
    });
  }

  Future<void> _saveProfile(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_profile', value);
    setState(() {
      _selectedProfile = value;
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Выбор профиля (радиокнопки в виде выпадающего списка или карточек)
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
                      DropdownButtonFormField<String>(
                        value: _profiles.contains(_selectedProfile) ? _selectedProfile : _profiles.first,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        items: _profiles.map((profile) {
                          return DropdownMenuItem(
                            value: profile,
                            child: Text(profile),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) _saveProfile(val);
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
    );
  }
}
