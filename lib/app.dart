import 'package:flutter/material.dart';

import 'domain/crm_service.dart';
import 'domain/models.dart';
import 'domain/repositories.dart';
import 'core/clock.dart';
import 'features/follow_ups/follow_ups_screen.dart';
import 'features/parties/party_list_screen.dart';
import 'features/parties/party_history_screen.dart';
import 'features/search/search_screen.dart';
import 'features/interactions/interaction_editor.dart';

class MyLittleCrmApp extends StatelessWidget {
  const MyLittleCrmApp({super.key, this.service});
  final CrmService? service;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'My Little CRM',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff315dce)),
      useMaterial3: true,
    ),
    home: InteractionHome(
      service:
          service ??
          CrmService(
            parties: MemoryPartyRepository(),
            interactions: MemoryInteractionRepository(),
            clock: const SystemClock(),
          ),
    ),
  );
}

class InteractionHome extends StatefulWidget {
  const InteractionHome({super.key, required this.service});
  final CrmService service;
  @override
  State<InteractionHome> createState() => _InteractionHomeState();
}

class _InteractionHomeState extends State<InteractionHome> {
  final List<_Entry> _entries = [];
  var _selectedIndex = 0;
  int _revision = 0;
  String? _loadError;
  int _loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _add() async {
    await editInteraction(context, widget.service);
    await _reload();
  }

  Future<void> _reload() async {
    final generation = ++_loadGeneration;
    try {
      final parties = await widget.service.parties.list();
      final entries = <_Entry>[];
      for (final party in parties) {
        for (final interaction in await widget.service.partyHistory(party.id)) {
          entries.add(_Entry(party: party, interaction: interaction));
        }
      }
      entries.sort(
        (a, b) => b.interaction.timestamp.compareTo(a.interaction.timestamp),
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = null;
        _revision++;
        _entries.clear();
        _entries.addAll(entries);
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(
          () => _loadError = 'Could not load interactions. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My Little CRM')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _add,
      icon: const Icon(Icons.add),
      label: const Text('Add interaction'),
    ),
    body: _selectedIndex == 3
        ? SearchScreen(service: widget.service, revision: _revision)
        : _selectedIndex == 2
        ? PartyListScreen(
            key: ValueKey(_revision),
            service: widget.service,
            onReturn: _reload,
          )
        : _selectedIndex == 1
        ? FollowUpsScreen(key: ValueKey(_revision), service: widget.service)
        : _loadError != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!),
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          )
        : _entries.isEmpty
        ? const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.forum_outlined, size: 52),
                SizedBox(height: 12),
                Text('Interactions'),
                SizedBox(height: 6),
                Text('No interactions yet'),
                Text('Record a conversation, promise, or follow-up.'),
              ],
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: _entries.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (_, index) {
              final entry = _entries[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.forum_outlined),
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PartyHistoryScreen(
                          service: widget.service,
                          party: entry.party,
                        ),
                      ),
                    );
                    await _reload();
                  },
                  title: Text(entry.party.name),
                  subtitle: Text(entry.interaction.summary),
                  trailing: Text(
                    entry.interaction.timestamp.toLocal().toString().substring(
                      0,
                      16,
                    ),
                  ),
                ),
              );
            },
          ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        setState(() => _selectedIndex = index);
        _reload();
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.forum_outlined),
          label: 'Interactions',
        ),
        NavigationDestination(
          icon: Icon(Icons.checklist_outlined),
          label: 'Follow-ups',
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          label: 'Parties',
        ),
        NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
      ],
    ),
  );
}

class _Entry {
  const _Entry({required this.party, required this.interaction});
  final Party party;
  final Interaction interaction;
}
