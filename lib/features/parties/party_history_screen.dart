import 'package:flutter/material.dart';
import '../../domain/crm_service.dart';
import '../../domain/models.dart';

class PartyHistoryScreen extends StatelessWidget {
  const PartyHistoryScreen({super.key, required this.service, required this.party});
  final CrmService service;
  final Party party;
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(party.name)), body: FutureBuilder<List<Interaction>>(
    future: service.partyHistory(party.id), builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      return ListView(children: [for (final item in snapshot.data!) ListTile(title: Text(item.summary), subtitle: Text(item.timestamp.toLocal().toString()), trailing: item.followUp?.status == FollowUpStatus.completed ? const Icon(Icons.check_circle) : null)]);
    }));
}
