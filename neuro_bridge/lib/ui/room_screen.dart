import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'call_screen.dart';
import 'multi_select_dropdown.dart';

class RoomScreen extends StatefulWidget {
  final String roomId;
  final bool isCreator;

  const RoomScreen({super.key, required this.roomId, required this.isCreator});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  int _tabIndex = 0; // 0 - Video, 1 - Materials
  bool _callStarted = false;

  List<String> _selectedProfiles = ['Нет нарушений'];
  final List<String> _profiles = [
    'Нет нарушений',
    'Нарушения зрения',
    'Нарушения речи', 
    'Нарушения слуха',
    'СДВГ',
    'Когнитивные трудности',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
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

  @override
  Widget build(BuildContext context) {
    bool isVideoCallActive = _tabIndex == 0 && _callStarted;

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: isVideoCallActive ? Colors.black : Theme.of(context).scaffoldBackgroundColor,
      ),
      child: Scaffold(
        appBar: isVideoCallActive ? null : AppBar(
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
          child: isVideoCallActive 
            ? _buildVideoTab() 
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    children: [
                       // Верхняя часть (профиль и комната)
                       Padding(
                         padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                         child: MultiSelectDropdown(
                           items: _profiles,
                           selectedItems: _selectedProfiles,
                           onChanged: (val) {
                             _saveProfile(val);
                           },
                         )
                       ),
                       Padding(
                         padding: const EdgeInsets.all(8.0),
                         child: Text('Комната: ${widget.roomId}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                       ),
                       
                       // Основная вкладка (материалы)
                       Expanded(
                         child: AnimatedSwitcher(
                           duration: const Duration(milliseconds: 300),
                           child: _tabIndex == 0 ? _buildVideoTab() : MaterialsTab(roomId: widget.roomId, isCreator: widget.isCreator),
                         ),
                       )
                    ]
                  ),
                ),
              ),
        ),
        bottomNavigationBar: Container(
           color: isVideoCallActive ? Colors.black : Theme.of(context).colorScheme.surface,
           height: 80,
           child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                 constraints: const BoxConstraints(maxWidth: 600),
                 child: Row(
                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                   children: [
                     _buildTabButton(1, Icons.folder, 'Материалы', isVideoCallActive),
                     _buildTabButton(0, Icons.videocam, 'Видеозвонок', isVideoCallActive),
                   ],
                 ),
              ),
           ),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label, bool isDarkState) {
    final isSelected = _tabIndex == index;
    final primaryColor = Theme.of(context).colorScheme.primaryContainer;
    final onPrimaryColor = Theme.of(context).colorScheme.onPrimaryContainer;
    
    Color bgColor;
    Color fgColor;
    
    if (isSelected) {
      bgColor = primaryColor;
      fgColor = onPrimaryColor;
    } else {
      if (isDarkState) {
        bgColor = Colors.white12;
        fgColor = Colors.white70;
      } else {
        bgColor = Theme.of(context).colorScheme.surface;
        fgColor = Theme.of(context).colorScheme.onSurface;
      }
    }

    return ElevatedButton.icon(
      onPressed: () => setState(() => _tabIndex = index),
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        elevation: isSelected ? 2 : 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    );
  }

  Widget _buildVideoTab() {
    if (!_callStarted) {
       return Center(
         child: ElevatedButton.icon(
           onPressed: () => setState(() => _callStarted = true),
           icon: const Icon(Icons.call),
           label: Text(widget.isCreator ? 'Начать видеозвонок' : 'Присоединиться к видеозвонку', style: const TextStyle(fontSize: 18)),
           style: ElevatedButton.styleFrom(
             padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
             backgroundColor: Colors.green,
             foregroundColor: Colors.white,
           )
         )
       );
    }
    // Интеграция существующего звонка
    return CallScreen(roomId: widget.roomId, isCreator: widget.isCreator);
  }
}

class MaterialsTab extends StatefulWidget {
  final String roomId;
  final bool isCreator;
  const MaterialsTab({super.key, required this.roomId, required this.isCreator});

  @override
  State<MaterialsTab> createState() => _MaterialsTabState();
}

class _MaterialsTabState extends State<MaterialsTab> {
  List<String> _materials = [];
  bool _loading = true;
  String _ip = '192.168.123.5';

  @override
  void initState() {
    super.initState();
    _fetchMaterials();
  }

  Future<void> _fetchMaterials() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _ip = prefs.getString('backend_ip') ?? '192.168.123.5';
    
    try {
      final res = await http.get(Uri.parse('http://$_ip:8001/api/rooms/${widget.roomId}/materials'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          _materials = List<String>.from(data['materials']);
        });
      }
    } catch (e) {
      debugPrint('Error fetching materials: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadMaterial() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(withData: true); // need to ensure bytes are fetched for web/mobile uniformily
    if (result != null && result.files.single.bytes != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Загрузка...')));
      try {
        var request = http.MultipartRequest('POST', Uri.parse('http://$_ip:8001/api/rooms/${widget.roomId}/materials/upload'));
        request.files.add(http.MultipartFile.fromBytes(
          'file', 
          result.files.single.bytes!,
          filename: result.files.single.name,
        ));
        var res = await request.send();
        if (res.statusCode == 200) {
          _fetchMaterials();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка загрузки на сервер')));
        }
      } catch (e) {
        debugPrint('Upload err: $e');
      }
    }
  }

  Future<void> _generateMaterial() async {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    await showDialog(context: context, builder: (ctx) => AlertDialog(
       title: const Text('Сгенерировать лекцию (ИИ)'),
       content: Column(
         mainAxisSize: MainAxisSize.min,
         children: [
           TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Название темы')),
           const SizedBox(height: 8),
           TextField(controller: descController, decoration: const InputDecoration(labelText: 'Краткое описание'), maxLines: 3),
         ]
       ),
       actions: [
         TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
         ElevatedButton(
           onPressed: () async {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Генерация...')));
              try {
                final res = await http.post(
                  Uri.parse('http://$_ip:8001/api/rooms/${widget.roomId}/materials/generate'),
                  headers: {'Content-Type': 'application/json'},
                  body: json.encode({'title': titleController.text, 'description': descController.text})
                );
                if (res.statusCode == 200) {
                   _fetchMaterials();
                }
              } catch (e) {
                debugPrint('Gen err: $e');
              }
           }, 
           child: const Text('Сгенерировать')
         )
       ]
    ));
  }

  void _showAddDialog() {
    showModalBottomSheet(
      context: context, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Способ добавления материала', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
               leading: const Icon(Icons.upload_file),
               title: const Text('Загрузить с устройства'),
               subtitle: const Text('Любые форматы (Office, PDF, картинки)'),
               onTap: () {
                 Navigator.pop(context);
                 _uploadMaterial();
               }
            ),
            ListTile(
               leading: const Icon(Icons.auto_awesome),
               title: const Text('Сгенерировать'),
               subtitle: const Text('Нейросеть сгенерирует текст по теме'),
               onTap: () {
                 Navigator.pop(context);
                 _generateMaterial();
               }
            ),
          ]
        ),
      )
    );
  }

  void _openMaterial(String filename) async {
    final url = Uri.parse('http://$_ip:8001/api/rooms/${widget.roomId}/materials/$filename');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть файл')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
         Padding(
           padding: const EdgeInsets.all(16.0),
           child: ElevatedButton.icon(
             onPressed: _showAddDialog,
             icon: const Icon(Icons.add),
             label: const Text('Добавить материал', style: TextStyle(fontSize: 16)),
             style: ElevatedButton.styleFrom(
               minimumSize: const Size(double.infinity, 50),
               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
             )
           ),
         ),
         Expanded(
           child: _loading 
             ? const Center(child: CircularProgressIndicator())
             : _materials.isEmpty
               ? const Center(child: Text('Пока нет материалов. Добавьте первый.', style: TextStyle(color: Colors.grey)))
               : RefreshIndicator(
                   onRefresh: _fetchMaterials,
                   child: ListView.builder(
                     itemCount: _materials.length + 1, 
                     itemBuilder: (context, index) {
                       if (index == _materials.length) return const SizedBox(height: 100); 
                       final mat = _materials[index];
                       return Card(
                         margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                         child: ListTile(
                           leading: const Icon(Icons.insert_drive_file, color: Colors.deepPurple),
                           title: Text(mat),
                           trailing: const Icon(Icons.download),
                           onTap: () => _openMaterial(mat),
                         ),
                       );
                     },
                   ),
                 ),
         )
      ],
    );
  }
}
