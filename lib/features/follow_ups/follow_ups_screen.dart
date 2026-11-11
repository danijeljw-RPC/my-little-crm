import 'package:flutter/material.dart';

import '../../domain/crm_service.dart';
import '../../domain/models.dart';

class FollowUpsScreen extends StatefulWidget {
  const FollowUpsScreen({super.key, required this.service});
  final CrmService service;
  @override
  State<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends State<FollowUpsScreen> {
  late Future<List<Interaction>> _items;
  @override
  void initState() {
    super.initState();
    _items = widget.service.outstandingFollowUps();
  }

  Future<void> _complete(Interaction item) async {
    try {
      await widget.service.completeFollowUp(item.id);
      if (mounted) {
        setState(() {
          _items = widget.service.outstandingFollowUps();
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not complete follow-up. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Interaction>>(
    future: _items,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load follow-ups. Please try again.'),
              TextButton(
                onPressed: () => setState(() {
                  _items = widget.service.outstandingFollowUps();
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
        return const Center(child: Text('No outstanding follow-ups'));
      }
      return ListView.builder(
        itemCount: snapshot.data!.length,
        itemBuilder: (context, index) => _FollowUpTile(
          item: snapshot.data![index],
          service: widget.service,
          onComplete: _complete,
        ),
      );
    },
  );
}

class _FollowUpTile extends StatelessWidget {
  const _FollowUpTile({
    required this.item,
    required this.service,
    required this.onComplete,
  });
  final Interaction item;
  final CrmService service;
  final Future<void> Function(Interaction) onComplete;
  @override
  Widget build(BuildContext context) => FutureBuilder<Party?>(
    future: service.parties.get(item.partyId),
    builder: (context, snapshot) => ListTile(
      title: Text(snapshot.data?.name ?? 'Unknown party'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.summary),
          Text(
            'Due ${item.followUp!.dueAt.toLocal().toString().substring(0, 10)}',
          ),
        ],
      ),
      trailing: IconButton(
        tooltip: 'Complete follow-up',
        icon: const Icon(Icons.check_circle_outline),
        onPressed: () => onComplete(item),
      ),
    ),
  );
}
