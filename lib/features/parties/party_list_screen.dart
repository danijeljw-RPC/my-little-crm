import 'package:flutter/material.dart';

import '../../domain/crm_service.dart';
import '../../domain/models.dart';
import 'party_history_screen.dart';

class PartyListScreen extends StatelessWidget {
  const PartyListScreen({super.key, required this.service});
  final CrmService service;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Party>>(
    future: service.parties.list(),
    builder: (context, snapshot) {
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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PartyHistoryScreen(service: service, party: party),
                ),
              ),
            ),
        ],
      );
    },
  );
}
