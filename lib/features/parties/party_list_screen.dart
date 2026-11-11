import 'package:flutter/material.dart';

import '../../domain/crm_service.dart';
import '../../domain/models.dart';
import 'party_history_screen.dart';

class PartyListScreen extends StatefulWidget {
  const PartyListScreen({super.key, required this.service, this.onReturn});
  final CrmService service;
  final Future<void> Function()? onReturn;
  @override
  State<PartyListScreen> createState() => _PartyListScreenState();
}

class _PartyListScreenState extends State<PartyListScreen> {
  late Future<List<Party>> _parties = widget.service.parties.list();
  CrmService get service => widget.service;
  Future<void> Function()? get onReturn => widget.onReturn;
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
              TextButton(
                onPressed: () => setState(() {
                  _parties = service.parties.list();
                }),
                child: const Text('Retry'),
              ),
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
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PartyHistoryScreen(service: service, party: party),
                  ),
                );
                await onReturn?.call();
              },
            ),
        ],
      );
    },
  );
}
