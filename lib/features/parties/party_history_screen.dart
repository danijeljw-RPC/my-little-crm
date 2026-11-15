import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../domain/crm_service.dart';
import '../../domain/models.dart';
import '../export/history_export_service.dart';
import '../interactions/interaction_editor.dart';

enum _PartyAction { rename, merge, delete }

class PartyHistoryScreen extends StatefulWidget {
  const PartyHistoryScreen({
    super.key,
    required this.service,
    required this.party,
    this.embedded = false,
    this.highlight,
    this.onPartyChanged,
  });
  final CrmService service;
  final Party party;

  /// Shown as the detail pane of a two-pane layout rather than as a route.
  final bool embedded;

  /// An interaction to mark as selected (two-pane home list).
  final InteractionId? highlight;

  /// Embedded only: called with the merge target after a merge, or null after
  /// the party is deleted, so the host can change its selection.
  final ValueChanged<Party?>? onPartyChanged;
  @override
  State<PartyHistoryScreen> createState() => _PartyHistoryScreenState();
}

class _PartyHistoryScreenState extends State<PartyHistoryScreen> {
  CrmService get service => widget.service;
  late Party party = widget.party;
  late Future<List<Interaction>> _history = service.partyHistory(party.id);

  /// Set while this screen merges or deletes its own party, so the change
  /// notification does not also close it; and once it has closed.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    service.revision.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant PartyHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.party.id != widget.party.id ||
        oldWidget.party.name != widget.party.name) {
      party = widget.party;
      _history = service.partyHistory(party.id);
    }
  }

  @override
  void dispose() {
    service.revision.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _history = service.partyHistory(party.id);
    });
    try {
      final current = await service.parties.get(party.id);
      if (!mounted) return;
      if (current == null) {
        if (!_leaving) _leave(null);
      } else if (current.name != party.name) {
        setState(() => party = current);
      }
    } catch (_) {
      // The history FutureBuilder reports storage failures with Retry.
    }
  }

  /// The party was merged away or deleted: show [next] or close.
  void _leave(Party? next) {
    _leaving = true;
    if (widget.embedded) {
      widget.onPartyChanged?.call(next);
    } else if (next == null) {
      Navigator.of(context).maybePop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PartyHistoryScreen(service: service, party: next),
        ),
      );
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _export(BuildContext context, String format) async {
    final exporter = HistoryExportService(
      service,
      dateFormat: AppDateFormat.of(context),
    );
    try {
      final document = format == 'PDF'
          ? await exporter.exportPdf(party.id)
          : await exporter.exportJson(party.id);
      final saved = await exporter.save(document);
      if (context.mounted && saved) _message('History exported');
    } catch (error) {
      _message(
        error is StateError &&
                error.message == HistoryExportService.unsupportedPdfTextMessage
            ? HistoryExportService.unsupportedPdfTextMessage
            : 'Could not export history. Please try again.',
      );
    }
  }

  Future<void> _onAction(_PartyAction action) => switch (action) {
    _PartyAction.rename => _rename(),
    _PartyAction.merge => _chooseMergeTarget(),
    _PartyAction.delete => _delete(),
  };

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: party.name),
    );
    if (name == null || name.trim().isEmpty || name.trim() == party.name) {
      return;
    }
    try {
      final renamed = await service.renameParty(party.id, name);
      if (mounted) setState(() => party = renamed);
      _message('Renamed to ${renamed.name}');
    } on PartyNameConflict catch (conflict) {
      if (!mounted) return;
      final merge = await _confirm(
        title: '"${conflict.existing.name}" already exists',
        body:
            'Merge "${party.name}" into "${conflict.existing.name}" instead? '
            'All of its interactions will move there.',
        action: 'Merge',
      );
      if (merge) await _merge(conflict.existing);
    } catch (_) {
      _message('Could not rename. Please try again.');
    }
  }

  Future<void> _chooseMergeTarget() async {
    final List<Party> others;
    try {
      others = (await service.parties.list())
          .where((p) => p.id != party.id)
          .toList();
    } catch (_) {
      _message('Could not load parties. Please try again.');
      return;
    }
    if (!mounted) return;
    if (others.isEmpty) {
      _message('There is no other party to merge into.');
      return;
    }
    final target = await showDialog<Party>(
      context: context,
      builder: (_) => _MergeTargetDialog(source: party, parties: others),
    );
    if (target == null || !mounted) return;
    final count = await service.partyInteractionCount(party.id);
    final ok = await _confirm(
      title: 'Merge into "${target.name}"?',
      body:
          '${_interactions(count)} will move from "${party.name}" to '
          '"${target.name}", and "${party.name}" will be removed.',
      action: 'Merge',
    );
    if (ok) await _merge(target);
  }

  Future<void> _merge(Party target) async {
    _leaving = true;
    try {
      await service.mergeParties(source: party.id, target: target.id);
      _message('Merged into ${target.name}');
      if (mounted) _leave(target);
    } catch (_) {
      _leaving = false;
      _message('Could not merge. Please try again.');
    }
  }

  Future<void> _delete() async {
    final int count;
    try {
      count = await service.partyInteractionCount(party.id);
    } catch (_) {
      _message('Could not delete. Please try again.');
      return;
    }
    final ok = await _confirm(
      title: 'Delete "${party.name}"?',
      body: count == 0
          ? 'This party has no interactions. This cannot be undone.'
          : 'This also deletes ${_interactions(count)}. This cannot be undone.',
      action: count == 0 ? 'Delete party' : 'Delete party and $count',
    );
    if (!ok) return;
    _leaving = true;
    try {
      await service.deleteParty(party.id);
      _message('Deleted ${party.name}');
      if (mounted) _leave(null);
    } catch (_) {
      _leaving = false;
      _message('Could not delete. Please try again.');
    }
  }

  static String _interactions(int count) =>
      count == 1 ? '1 interaction' : '$count interactions';

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final format = AppDateFormat.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(party.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Export history',
            icon: const Icon(Icons.ios_share),
            onSelected: (format) => _export(context, format),
            itemBuilder: (_) => [
              for (final format in ['PDF', 'JSON'])
                PopupMenuItem(value: format, child: Text('Export $format')),
            ],
          ),
          PopupMenuButton<_PartyAction>(
            tooltip: 'Party actions',
            onSelected: _onAction,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _PartyAction.rename,
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Rename'),
                ),
              ),
              PopupMenuItem(
                value: _PartyAction.merge,
                child: ListTile(
                  leading: Icon(Icons.merge_type),
                  title: Text('Merge into another party'),
                ),
              ),
              PopupMenuItem(
                value: _PartyAction.delete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete party'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<Interaction>>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load history. Please try again.'),
                  TextButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(child: Text('No interactions with this party'));
          }
          return ListView(
            children: [
              for (final item in snapshot.data!)
                ListTile(
                  selected: item.id == widget.highlight,
                  onTap: () => editInteraction(
                    context,
                    service,
                    existing: item,
                    partyName: party.name,
                  ),
                  title: Text(item.summary),
                  subtitle: Text(
                    [
                      '${format.dateTime(item.timestamp)} · ${item.method.name}',
                      if (item.contactName != null) item.contactName!,
                      ...item.referenceNumbers,
                      if (item.commitment != null) item.commitment!,
                      if (item.followUp != null)
                        'Follow-up '
                            '${item.followUp!.hasTime ? format.dateTime(item.followUp!.dueAt) : format.date(item.followUp!.dueAt)}'
                            ': ${item.followUp!.status.name}',
                    ].join('\n'),
                  ),
                  trailing: item.followUp?.status == FollowUpStatus.completed
                      ? const Icon(Icons.check_circle)
                      : const Icon(Icons.edit_outlined),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename party'),
    content: TextField(
      key: const Key('rename-party'),
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Company or person'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Rename'),
      ),
    ],
  );
}

class _MergeTargetDialog extends StatefulWidget {
  const _MergeTargetDialog({required this.source, required this.parties});
  final Party source;
  final List<Party> parties;
  @override
  State<_MergeTargetDialog> createState() => _MergeTargetDialogState();
}

class _MergeTargetDialogState extends State<_MergeTargetDialog> {
  String _filter = '';
  @override
  Widget build(BuildContext context) {
    final matches = widget.parties
        .where((p) => p.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    return AlertDialog(
      title: Text('Merge "${widget.source.name}" into…'),
      content: SizedBox(
        width: 400,
        height: 360,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Find a party',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _filter = value.trim()),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final party in matches)
                    ListTile(
                      title: Text(party.name),
                      onTap: () => Navigator.pop(context, party),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
