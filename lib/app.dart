import 'package:flutter/material.dart';

class MyLittleCrmApp extends StatelessWidget {
  const MyLittleCrmApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'My Little CRM',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff315dce)), useMaterial3: true),
    home: const InteractionHome(),
  );
}

class InteractionHome extends StatefulWidget { const InteractionHome({super.key}); @override State<InteractionHome> createState()=>_InteractionHomeState(); }
class _InteractionHomeState extends State<InteractionHome> {
  final List<_Entry> entries=[];
  Future<void> _add() async { final result=await showModalBottomSheet<_Entry>(context:context,isScrollControlled:true,builder:(_)=>const _EntryForm()); if(result!=null)setState(()=>entries.insert(0,result)); }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('My Little CRM')),
    floatingActionButton:FloatingActionButton.extended(onPressed:_add,icon:const Icon(Icons.add),label:const Text('Add interaction')),
    body: entries.isEmpty ? const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.forum_outlined,size:52),SizedBox(height:12),Text('Interactions'),SizedBox(height:6),Text('No interactions yet'),Text('Record a conversation, promise, or follow-up.')])) : ListView.separated(padding:const EdgeInsets.all(20),itemCount:entries.length,separatorBuilder:(context,index)=>const SizedBox(height:10),itemBuilder:(_,i){final e=entries[i];return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.phone_outlined)),title:Text(e.party),subtitle:Text(e.summary),trailing:Text('Today',style:Theme.of(context).textTheme.labelSmall)));}),
  );
}
class _Entry { const _Entry(this.party,this.summary); final String party; final String summary; }
class _EntryForm extends StatefulWidget { const _EntryForm(); @override State<_EntryForm> createState()=>_EntryFormState(); }
class _EntryFormState extends State<_EntryForm> { final party=TextEditingController(); final summary=TextEditingController(); @override void dispose(){party.dispose();summary.dispose();super.dispose();} @override Widget build(BuildContext context)=>Padding(padding:EdgeInsets.fromLTRB(24,24,24,24+MediaQuery.viewInsetsOf(context).bottom),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text('New interaction',style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:16),TextField(key:const Key('party-name'),controller:party,decoration:const InputDecoration(labelText:'Company or person',border:OutlineInputBorder())),const SizedBox(height:12),TextField(key:const Key('summary'),controller:summary,maxLines:3,decoration:const InputDecoration(labelText:'What was discussed?',border:OutlineInputBorder())),const SizedBox(height:16),FilledButton(onPressed:()=>Navigator.pop(context,_Entry(party.text.trim(),summary.text.trim())),child:const Text('Save interaction'))])); }
