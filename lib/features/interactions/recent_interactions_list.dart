import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../domain/crm_service.dart';
import '../../domain/models.dart';
import 'communication_method_icon.dart';

/// The home list: newest interactions first, loaded a page at a time from
/// SQLite as the user scrolls, instead of the whole ledger (#39).
class RecentInteractionsList extends StatefulWidget {
  const RecentInteractionsList({
    super.key,
    required this.service,
    required this.onOpen,
    this.selectedId,
    this.pageSize = 50,
  });
  final CrmService service;
  final ValueChanged<InteractionEntry> onOpen;
  final InteractionId? selectedId;
  final int pageSize;
  @override
  State<RecentInteractionsList> createState() => _RecentInteractionsListState();
}

class _RecentInteractionsListState extends State<RecentInteractionsList> {
  final List<InteractionEntry> _entries = [];
  bool _loading = false;
  bool _hasMore = true;
  bool _loaded = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.service.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.service.revision.removeListener(_reload);
    super.dispose();
  }

  /// Reloads from the top, keeping as many rows as were already shown.
  Future<void> _reload() async {
    final generation = ++_generation;
    final limit = _entries.length > widget.pageSize
        ? _entries.length
        : widget.pageSize;
    _loading = true; // may run from initState; no rebuild needed yet
    try {
      final page = await widget.service.recentInteractions(limit: limit);
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(page);
        _hasMore = page.length == limit;
        _loaded = true;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = 'Could not load interactions. Please try again.';
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _entries.isEmpty) return;
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final page = await widget.service.recentInteractions(
        limit: widget.pageSize,
        after: RecentCursor.after(_entries.last.interaction),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries.addAll(page);
        _hasMore = page.length == widget.pageSize;
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _reload, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_entries.isEmpty) {
      return const Center(
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
      );
    }
    final format = AppDateFormat.of(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 600) _loadMore();
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _entries.length + (_hasMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          if (index == _entries.length) {
            // Also covers a first page too short to scroll.
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final entry = _entries[index];
          return Card(
            child: ListTile(
              selected: entry.interaction.id == widget.selectedId,
              leading: CircleAvatar(child: Icon(entry.interaction.method.icon)),
              onTap: () => widget.onOpen(entry),
              // The locale date can be long ("Thu, Nov 12 10:30 AM"), so it
              // shares the title row instead of squeezing the text column.
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.party.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    format.dateTime(entry.interaction.timestamp),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              subtitle: Text(
                entry.interaction.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      ),
    );
  }
}
