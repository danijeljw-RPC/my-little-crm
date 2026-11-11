import 'package:flutter/material.dart';
import '../../domain/crm_service.dart';
import '../../domain/models.dart';

class SearchScreen extends StatefulWidget { const SearchScreen({super.key, required this.service}); final CrmService service; @override State<SearchScreen> createState() => _SearchScreenState(); }
class _SearchScreenState extends State<SearchScreen> {
  List<Interaction> _results = const [];
  Future<void> _search(String value) async { final results = await widget.service.searchInteractions(value); if (mounted) setState(() { _results = results; }); }
  @override Widget build(BuildContext context) => Column(children: [Padding(padding: const EdgeInsets.all(16), child: TextField(autofocus: true, onChanged: _search, decoration: const InputDecoration(labelText: 'Search conversations', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()))), Expanded(child: ListView(children: [for (final item in _results) _Result(item: item, service: widget.service)]))]);
}
class _Result extends StatelessWidget { const _Result({required this.item, required this.service}); final Interaction item; final CrmService service; @override Widget build(BuildContext context) => FutureBuilder<Party?>(future: service.parties.get(item.partyId), builder: (context, snapshot) => ListTile(title: Text(snapshot.data?.name ?? 'Unknown party'), subtitle: Text(item.summary))); }
