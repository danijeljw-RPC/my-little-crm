import 'package:flutter/material.dart';

import 'domain/crm_service.dart';
import 'domain/models.dart';
import 'domain/repositories.dart';
import 'core/clock.dart';

class MyLittleCrmApp extends StatelessWidget {
  const MyLittleCrmApp({super.key, this.service});
  final CrmService? service;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'My Little CRM',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff315dce)), useMaterial3: true),
    home: InteractionHome(service: service ?? CrmService(parties: MemoryPartyRepository(), interactions: MemoryInteractionRepository(), clock: const SystemClock())),
  );
}

class InteractionHome extends StatefulWidget {
  const InteractionHome({super.key, required this.service});
  final CrmService service;
  @override State<InteractionHome> createState() => _InteractionHomeState();
}

class _InteractionHomeState extends State<InteractionHome> {
  final List<_Entry> _entries = [];

  Future<void> _add() async {
    final draft = await showModalBottomSheet<_Draft>(context: context, isScrollControlled: true, builder: (_) => const _EntryForm());
    if (draft == null) return;
    final interaction = await widget.service.createInteraction(CreateInteractionCommand(partyName: draft.party, summary: draft.summary));
    if (!mounted) return;
    setState(() => _entries.insert(0, _Entry(party: draft.party, interaction: interaction)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My Little CRM')),
    floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add interaction')),
    body: _entries.isEmpty
        ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.forum_outlined, size: 52), SizedBox(height: 12), Text('Interactions'), SizedBox(height: 6), Text('No interactions yet'), Text('Record a conversation, promise, or follow-up.')]))
        : ListView.separated(padding: const EdgeInsets.all(20), itemCount: _entries.length, separatorBuilder: (context, index) => const SizedBox(height: 10), itemBuilder: (_, index) {
            final entry = _entries[index];
            return Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.forum_outlined)), title: Text(entry.party), subtitle: Text(entry.interaction.summary), trailing: const Text('Today')));
          }),
  );
}

class _Entry { const _Entry({required this.party, required this.interaction}); final String party; final Interaction interaction; }
class _Draft { const _Draft(this.party, this.summary); final String party; final String summary; }

class _EntryForm extends StatefulWidget { const _EntryForm(); @override State<_EntryForm> createState() => _EntryFormState(); }
class _EntryFormState extends State<_EntryForm> {
  final _party = TextEditingController();
  final _summary = TextEditingController();
  @override void dispose() { _party.dispose(); _summary.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('New interaction', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 16),
      TextField(key: const Key('party-name'), controller: _party, decoration: const InputDecoration(labelText: 'Company or person', border: OutlineInputBorder())), const SizedBox(height: 12),
      TextField(key: const Key('summary'), controller: _summary, maxLines: 3, decoration: const InputDecoration(labelText: 'What was discussed?', border: OutlineInputBorder())), const SizedBox(height: 16),
      FilledButton(onPressed: () { if (_party.text.trim().isNotEmpty && _summary.text.trim().isNotEmpty) Navigator.pop(context, _Draft(_party.text.trim(), _summary.text.trim())); }, child: const Text('Save interaction')),
    ]),
  );
}
