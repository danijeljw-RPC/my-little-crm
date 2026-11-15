import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../domain/crm_service.dart';
import '../../domain/models.dart';

class FollowUpsScreen extends StatefulWidget {
  const FollowUpsScreen({super.key, required this.service});
  final CrmService service;
  @override
  State<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpData {
  const _FollowUpData(this.items, this.partyNames);
  final List<Interaction> items;
  final Map<PartyId, String> partyNames;
}

class _FollowUpsScreenState extends State<FollowUpsScreen> {
  late Future<_FollowUpData> _items;

  @override
  void initState() {
    super.initState();
    _items = _load();
    widget.service.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.service.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _items = _load();
    });
  }

  Future<_FollowUpData> _load() async {
    final items = await widget.service.outstandingFollowUps();
    final parties = await widget.service.parties.list();
    return _FollowUpData(items, {for (final p in parties) p.id: p.name});
  }

  Future<void> _complete(Interaction item) async {
    try {
      await widget.service.completeFollowUp(item.id);
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
  Widget build(BuildContext context) => FutureBuilder<_FollowUpData>(
    future: _items,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load follow-ups. Please try again.'),
              TextButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!;
      if (data.items.isEmpty) {
        return const Center(child: Text('No outstanding follow-ups'));
      }
      final now = widget.service.clock.now();
      final groups = {
        for (final urgency in FollowUpUrgency.values)
          urgency:
              data.items
                  .where((i) => i.followUp!.urgency(now) == urgency)
                  .toList()
                ..sort(
                  (a, b) => a.followUp!.effectiveDueAt.compareTo(
                    b.followUp!.effectiveDueAt,
                  ),
                ),
      };
      return ListView(
        children: [
          for (final MapEntry(key: urgency, value: items) in groups.entries)
            if (items.isNotEmpty) ...[
              _SectionHeader(urgency: urgency, count: items.length),
              for (final item in items)
                _FollowUpTile(
                  item: item,
                  partyName: data.partyNames[item.partyId] ?? 'Unknown party',
                  urgency: urgency,
                  onComplete: _complete,
                ),
            ],
        ],
      );
    },
  );
}

extension FollowUpUrgencyLabel on FollowUpUrgency {
  String get label => switch (this) {
    FollowUpUrgency.overdue => 'Overdue',
    FollowUpUrgency.today => 'Due today',
    FollowUpUrgency.upcoming => 'Upcoming',
  };
  IconData get icon => switch (this) {
    FollowUpUrgency.overdue => Icons.warning_amber_rounded,
    FollowUpUrgency.today => Icons.today_outlined,
    FollowUpUrgency.upcoming => Icons.event_outlined,
  };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.urgency, required this.count});
  final FollowUpUrgency urgency;
  final int count;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = urgency == FollowUpUrgency.overdue
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Row(
          children: [
            Icon(urgency.icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(
              '${urgency.label} ($count)',
              style: theme.textTheme.titleSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowUpTile extends StatelessWidget {
  const _FollowUpTile({
    required this.item,
    required this.partyName,
    required this.urgency,
    required this.onComplete,
  });
  final Interaction item;
  final String partyName;
  final FollowUpUrgency urgency;
  final Future<void> Function(Interaction) onComplete;
  @override
  Widget build(BuildContext context) {
    final format = AppDateFormat.of(context);
    final followUp = item.followUp!;
    final due = followUp.hasTime
        ? format.dateTime(followUp.dueAt)
        : format.date(followUp.dueAt);
    final overdue = urgency == FollowUpUrgency.overdue;
    final theme = Theme.of(context);
    return ListTile(
      leading: overdue
          ? Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.error,
              semanticLabel: 'Overdue',
            )
          : null,
      title: Text(partyName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.summary),
          Text(
            // The word "Overdue" carries the state, not just the colour.
            overdue ? 'Overdue · was due $due' : 'Due $due',
            style: overdue
                ? TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  )
                : null,
          ),
        ],
      ),
      trailing: IconButton(
        tooltip: 'Complete follow-up',
        icon: const Icon(Icons.check_circle_outline),
        onPressed: () => onComplete(item),
      ),
    );
  }
}
