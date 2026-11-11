import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MyLittleCrmApp extends StatelessWidget {
  const MyLittleCrmApp({super.key});

  static final GoRouter _router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (context, state) => const _HomeScreen()),
      GoRoute(path: '/parties', builder: (context, state) => const _PlaceholderScreen('Parties')),
      GoRoute(path: '/search', builder: (context, state) => const _PlaceholderScreen('Search')),
      GoRoute(path: '/follow-ups', builder: (context, state) => const _PlaceholderScreen('Follow-ups')),
    ],
  );

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'My Little CRM',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff315dce)),
          useMaterial3: true,
        ),
        routerConfig: _router,
      );
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My Little CRM')),
        body: const Center(child: Text('Interactions')),
      );
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Text(title)),
      );
}
