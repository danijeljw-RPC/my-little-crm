import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../domain/crm_service.dart';
import '../../domain/models.dart';
import '../interactions/interaction_editor.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.service});
  final CrmService service;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  List<Interaction> _results = const [];
  int _generation = 0;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    // Re-run the query after any edit, move, delete or undo.
    widget.service.revision.addListener(_rerun);
  }

  @override
  void dispose() {
    widget.service.revision.removeListener(_rerun);
    super.dispose();
  }

  void _rerun() => _search(_query);

  Future<void> _search(String value) async {
    _query = value;
    final generation = ++_generation;
    try {
      final results = value.trim().isEmpty
          ? <Interaction>[]
          : await widget.service.searchInteractions(value);
      if (mounted && generation == _generation) {
        setState(() {
          _results = results;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _results = const [];
          _error = 'Could not search. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          autofocus: true,
          onChanged: _search,
          decoration: const InputDecoration(
            labelText: 'Search conversations',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
      ),
      if (_error != null) Text(_error!),
      Expanded(
        child: ListView(
          children: [
            for (final item in _results)
              _Result(
                key: ValueKey('${item.id}/${item.partyId}'),
                item: item,
                service: widget.service,
              ),
          ],
        ),
      ),
    ],
  );
}

class _Result extends StatelessWidget {
  const _Result({super.key, required this.item, required this.service});
  final Interaction item;
  final CrmService service;
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
            '${AppDateFormat.of(context).dateTime(item.timestamp)} · '
            '${item.method.name}',
          ),
        ],
      ),
      onTap: snapshot.data == null
          ? null
          : () => editInteraction(
              context,
              service,
              existing: item,
              partyName: snapshot.data!.name,
            ),
    ),
  );
}
