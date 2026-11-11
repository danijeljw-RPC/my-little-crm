import 'package:flutter/material.dart';

import '../../domain/crm_service.dart';
import '../../domain/models.dart';
import '../parties/party_history_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.service, this.revision = 0});
  final CrmService service;
  final int revision;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  List<Interaction> _results = const [];
  int _generation = 0;
  String _query = '';
  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _search(_query);
    }
  }

  Future<void> _search(String value) async {
    _query = value;
    final generation = ++_generation;
    final results = value.trim().isEmpty
        ? <Interaction>[]
        : await widget.service.searchInteractions(value);
    if (mounted && generation == _generation) {
      setState(() {
        _results = results;
      });
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
      Expanded(
        child: ListView(
          children: [
            for (final item in _results)
              _Result(
                item: item,
                service: widget.service,
                onReturn: () => _search(_query),
              ),
          ],
        ),
      ),
    ],
  );
}

class _Result extends StatelessWidget {
  const _Result({
    required this.item,
    required this.service,
    required this.onReturn,
  });
  final Future<void> Function() onReturn;
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
          Text('${item.timestamp.toLocal()} · ${item.method.name}'),
        ],
      ),
      onTap: snapshot.data == null
          ? null
          : () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PartyHistoryScreen(
                    service: service,
                    party: snapshot.data!,
                  ),
                ),
              );
              await onReturn();
            },
    ),
  );
}
