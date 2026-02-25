import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../ui/main_screen.dart';
import '../../ui/settings_screen.dart';
import '../../ui/room_screen.dart';

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
      path: '/room/:roomId',
      builder: (context, state) {
        final roomId = state.pathParameters['roomId'] ?? '1';
        final isCreator = (state.extra as bool?) ?? false;
        return RoomScreen(roomId: roomId, isCreator: isCreator);
      },
    ),
  ],
);
