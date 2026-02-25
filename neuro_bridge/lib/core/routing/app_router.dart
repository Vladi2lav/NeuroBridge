import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../ui/main_screen.dart';
import '../../ui/settings_screen.dart';
import '../../ui/call_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/main',
  routes: [
    GoRoute(
      path: '/main',
      builder: (context, state) => const MainScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/call',
      builder: (context, state) {
        final extras = state.extra as Map<String, dynamic>?;
        final roomId = extras?['roomId'] ?? '1';
        final isCreator = extras?['isCreator'] ?? true;
        return CallScreen(roomId: roomId, isCreator: isCreator);
      },
    ),
  ],
);
