import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/routing/app_router.dart';
import 'core/services/voice_assistant.dart';

void main() {
  runApp(
    const ProviderScope(
      child: NeuroBridgeApp(),
    ),
  );
}

class NeuroBridgeApp extends StatelessWidget {
  const NeuroBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NeuroBridge',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            ValueListenableBuilder<String>(
              valueListenable: VoiceAssistant().currentSpeechContent,
              builder: (context, value, _) {
                if (value.isEmpty) return const SizedBox.shrink();
                return Positioned(
                  bottom: 40,
                  left: 24,
                  right: 24,
                  child: IgnorePointer(
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                             BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))
                          ]
                        ),
                        child: Text(
                          value,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A), // Строгий темно-синий
          primary: const Color(0xFF1E3A8A),
          onPrimary: Colors.white,
          secondary: const Color(0xFF2563EB),
          surface: Colors.white,
          onSurface: const Color(0xFF0F172A),
          brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18, color: Color(0xFF0F172A)),
          bodyMedium: TextStyle(fontSize: 16, color: Color(0xFF0F172A)),
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          titleMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
          labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 2)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 2)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 3)),
          labelStyle: const TextStyle(fontSize: 18, color: Color(0xFF475569)),
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF38BDF8),
          primary: const Color(0xFF38BDF8),
          onPrimary: const Color(0xFF0F172A),
          surface: const Color(0xFF0F172A),
          onSurface: const Color(0xFFF8FAFC),
          brightness: Brightness.dark,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18, color: Color(0xFFF8FAFC)),
          bodyMedium: TextStyle(fontSize: 16, color: Color(0xFFF8FAFC)),
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFF8FAFC)),
          titleMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFFF8FAFC)),
          labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: const Color(0xFF1E293B),
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF334155), width: 2)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF334155), width: 2)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 3)),
          labelStyle: const TextStyle(fontSize: 18, color: Color(0xFF94A3B8)),
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
