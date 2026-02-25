import 'package:flutter/material.dart';
import 'join_call_screen.dart';
import 'connection_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NeuroBridge'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
             icon: const Icon(Icons.settings),
             onPressed: () {
               Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionScreen()));
             },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner/Header
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Добро пожаловать в NeuroBridge',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Инклюзивная платформа для онлайн-образования',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Video Call Button
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const JoinCallScreen()),
                );
              },
              icon: const Icon(Icons.video_call, size: 32),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text('Видеозвонок', style: TextStyle(fontSize: 20)),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Problem Selection
            Text(
              'Выбор проблем адаптации',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: [
                _buildProblemChip('Нарушения моторики', Icons.pan_tool, context),
                _buildProblemChip('Слабое зрение', Icons.visibility, context),
                _buildProblemChip('Слабый слух', Icons.hearing, context),
                _buildProblemChip('Трудности концентрации', Icons.psychology, context),
              ],
            ),
            const SizedBox(height: 32),

            // Features List
            Text(
              'Функции платформы',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildFeatureCard(
              'Управление жестами',
              'Встроенный трекинг рук во время видеозвонка для управления интерфейсом без мыши.',
              Icons.do_not_touch,
              context,
            ),
            _buildFeatureCard(
              'Адаптивный интерфейс',
              'Увеличение шрифтов, контрастные схемы и поддержка чтения с экрана.',
              Icons.format_size,
              context,
            ),
            _buildFeatureCard(
              'Субтитры и транскрипция',
              'Автоматический перевод голоса в текст в реальном времени.',
              Icons.subtitles,
              context,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProblemChip(String label, IconData icon, BuildContext context) {
    return FilterChip(
      label: Text(label),
      avatar: Icon(icon, size: 18),
      onSelected: (bool selected) {
        // Implement logic later
      },
    );
  }

  Widget _buildFeatureCard(String title, String desc, IconData icon, BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16.0),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Icon(icon, color: Theme.of(context).colorScheme.onSecondaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(desc),
        ),
      ),
    );
  }
}
