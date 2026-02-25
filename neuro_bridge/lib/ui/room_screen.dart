import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'call_screen.dart';

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

  String _selectedProfile = 'Нет нарушений';
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
      body: Column(
        children: [
           // Верхняя часть (профиль и комната)
           Padding(
             padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
             child: DropdownButtonFormField<String>(
                value: _profiles.contains(_selectedProfile) ? _selectedProfile : _profiles.first,
                isExpanded: true,
                decoration: InputDecoration(
                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                   contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                items: _profiles.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (val) { if (val != null) _saveProfile(val); },
             )
           ),
           Padding(
             padding: const EdgeInsets.all(8.0),
             child: Text('Комната: ${widget.roomId}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
           ),
           
           // Основная вкладка (видеозвонок или материалы)
           Expanded(
             child: AnimatedSwitcher(
               duration: const Duration(milliseconds: 300),
               child: _tabIndex == 0 ? _buildVideoTab() : MaterialsTab(roomId: widget.roomId, isCreator: widget.isCreator),
             ),
           )
        ]
      ),
      // Плавающие кнопки в самом низу
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            FloatingActionButton.extended(
              heroTag: 'materials_btn',
              onPressed: () => setState(() => _tabIndex = 1),
              icon: const Icon(Icons.folder),
              label: const Text('Материалы'),
              backgroundColor: _tabIndex == 1 ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surface,
              foregroundColor: _tabIndex == 1 ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurface,
            ),
            FloatingActionButton.extended(
              heroTag: 'video_btn',
              onPressed: () => setState(() => _tabIndex = 0),
              icon: const Icon(Icons.videocam),
              label: const Text('Видеозвонок'),
              backgroundColor: _tabIndex == 0 ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surface,
              foregroundColor: _tabIndex == 0 ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
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
