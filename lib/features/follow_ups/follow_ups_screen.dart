import 'package:flutter/material.dart';

import '../../domain/crm_service.dart';
import '../../domain/models.dart';

class FollowUpsScreen extends StatefulWidget {
  const FollowUpsScreen({super.key, required this.service});
  final CrmService service;
  @override State<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends State<FollowUpsScreen> {
  late Future<List<Interaction>> _items;
  @override void initState() { super.initState(); _items = widget.service.outstandingFollowUps(); }
  Future<void> _complete(Interaction item) async {
    await widget.service.completeFollowUp(item.id);
    final refreshed = widget.service.outstandingFollowUps();
    if (mounted) {
      setState(() {
        _items = refreshed;
      });
    }
  }
  @override Widget build(BuildContext context) => FutureBuilder<List<Interaction>>(
    future: _items,
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      if (snapshot.data!.isEmpty) return const Center(child: Text('No outstanding follow-ups'));
      return ListView.builder(itemCount: snapshot.data!.length, itemBuilder: (context, index) => _FollowUpTile(item: snapshot.data![index], service: widget.service, onComplete: _complete));
    },
  );
}

class _FollowUpTile extends StatelessWidget {
  const _FollowUpTile({required this.item, required this.service, required this.onComplete});
  final Interaction item;
  final CrmService service;
  final Future<void> Function(Interaction) onComplete;
  @override Widget build(BuildContext context) => FutureBuilder<Party?>(
    future: service.parties.get(item.partyId),
    builder: (context, snapshot) => ListTile(
      title: Text(snapshot.data?.name ?? 'Unknown party'), subtitle: Text(item.summary),
      trailing: IconButton(tooltip: 'Complete follow-up', icon: const Icon(Icons.check_circle_outline), onPressed: () => onComplete(item)),
    ),
  );
}
