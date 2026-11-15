import 'package:flutter/material.dart';

import '../../domain/crm_service.dart';
import '../../domain/models.dart';
import 'party_history_screen.dart';

class PartyListScreen extends StatefulWidget {
  const PartyListScreen({
    super.key,
    required this.service,
    this.onSelect,
    this.selectedId,
  });
  final CrmService service;

  /// Two-pane mode: report the tapped party instead of pushing its history.
  final ValueChanged<Party>? onSelect;
  final PartyId? selectedId;
  @override
  State<PartyListScreen> createState() => _PartyListScreenState();
}

class _PartyListScreenState extends State<PartyListScreen> {
  late Future<List<Party>> _parties = widget.service.parties.list();
  CrmService get service => widget.service;

  @override
  void initState() {
    super.initState();
    service.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    service.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _parties = service.parties.list();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Party>>(
    future: _parties,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load parties. Please try again.'),
              TextButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.data!.isEmpty) {
        return const Center(child: Text('No parties yet'));
      }
      return ListView(
        children: [
          for (final party in snapshot.data!)
            ListTile(
              title: Text(party.name),
              selected: party.id == widget.selectedId,
              trailing: widget.onSelect == null
                  ? const Icon(Icons.chevron_right)
                  : null,
              onTap: () {
                if (widget.onSelect != null) {
                  widget.onSelect!(party);
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PartyHistoryScreen(service: service, party: party),
                  ),
                );
              },
            ),
        ],
      );
    },
  );
}
