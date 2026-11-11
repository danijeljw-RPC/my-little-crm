import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/crm_service.dart';

import 'package:uuid/uuid.dart';

Future<void> editInteraction(
  BuildContext context,
  CrmService service, {
  Interaction? existing,
  String? partyName,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => InteractionEditor(
      service: service,
      existing: existing,
      partyName: partyName,
    ),
  );
}

class InteractionEditor extends StatefulWidget {
  const InteractionEditor({
    super.key,
    required this.service,
    this.existing,
    this.partyName,
  });
  final CrmService service;
  final Interaction? existing;
  final String? partyName;
  @override
  State<InteractionEditor> createState() => _InteractionEditorState();
}

class _InteractionEditorState extends State<InteractionEditor> {
  final form = GlobalKey<FormState>();
  late final party = TextEditingController(text: widget.partyName);
  late final summary = TextEditingController(text: widget.existing?.summary);
  late final contact = TextEditingController(
    text: widget.existing?.contactName,
  );
  late final references = TextEditingController(
    text: widget.existing?.referenceNumbers.join(', '),
  );
  late final commitment = TextEditingController(
    text: widget.existing?.commitment,
  );
  late DateTime timestamp =
      widget.existing?.timestamp.toLocal() ??
      widget.service.clock.now().toLocal();
  late DateTime? due = widget.existing?.followUp?.dueAt.toLocal();
  late CommunicationMethod method =
      widget.existing?.method ?? CommunicationMethod.phone;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    for (final controller in [
      party,
      summary,
      contact,
      references,
      commitment,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final existing = widget.existing;
      final selectedParty = existing == null
          ? await widget.service.parties.findOrCreate(party.text.trim())
          : await widget.service.parties.get(existing.partyId);
      if (selectedParty == null) throw StateError('Party no longer exists');
      final base =
          widget.existing ??
          Interaction(
            id: const Uuid().v4(),
            partyId: selectedParty.id,
            summary: summary.text.trim(),
            timestamp: timestamp.toUtc(),
            createdAt: widget.service.clock.now().toUtc(),
          );
      await widget.service.interactions.save(
        Interaction(
          id: base.id,
          partyId: base.partyId,
          summary: summary.text.trim(),
          timestamp: timestamp.toUtc(),
          createdAt: base.createdAt,
          method: method,
          contactName: contact.text.trim().isEmpty ? null : contact.text.trim(),
          referenceNumbers: references.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList(),
          commitment: commitment.text.trim().isEmpty
              ? null
              : commitment.text.trim(),
          followUp: due == null
              ? null
              : FollowUp(
                  dueAt: due!.toUtc(),
                  status:
                      widget.existing?.followUp?.status ?? FollowUpStatus.open,
                ),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not save. Please try again.';
        });
      }
    }
  }

  Future<DateTime?> date(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(1900),
    lastDate: DateTime(2200),
  );
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Form(
      key: form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'New interaction' : 'Edit interaction',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            TextFormField(
              key: const Key('party-name'),
              controller: party,
              readOnly: widget.existing != null,
              decoration: const InputDecoration(labelText: 'Company or person'),
              validator: (s) => s == null || s.trim().isEmpty
                  ? 'Enter a company or person'
                  : null,
            ),
            TextFormField(
              key: const Key('summary'),
              controller: summary,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'What was discussed?',
              ),
              validator: (s) => s == null || s.trim().isEmpty
                  ? 'Enter a discussion summary'
                  : null,
            ),
            DropdownButtonFormField<CommunicationMethod>(
              initialValue: method,
              decoration: const InputDecoration(labelText: 'Method'),
              items: [
                for (final value in CommunicationMethod.values)
                  DropdownMenuItem(value: value, child: Text(value.name)),
              ],
              onChanged: (v) => setState(() {
                method = v!;
              }),
            ),
            TextFormField(
              controller: contact,
              decoration: const InputDecoration(
                labelText: 'Contact name (optional)',
              ),
            ),
            TextFormField(
              controller: references,
              decoration: const InputDecoration(
                labelText: 'Reference numbers (comma separated)',
              ),
            ),
            TextFormField(
              controller: commitment,
              decoration: const InputDecoration(
                labelText: 'Agreement or promise (optional)',
              ),
            ),
            TextButton(
              onPressed: () async {
                final value = await date(timestamp);
                if (value != null && context.mounted) {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(timestamp),
                  );
                  if (time != null && mounted) {
                    setState(() {
                      timestamp = DateTime(
                        value.year,
                        value.month,
                        value.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  }
                }
              },
              child: Text('Occurred: $timestamp'),
            ),
            TextButton(
              onPressed: () async {
                final value = await date(due ?? DateTime.now());
                if (value != null) {
                  setState(() {
                    due = value;
                  });
                }
              },
              child: Text(
                due == null
                    ? 'Add follow-up date'
                    : 'Follow-up: ${due!.toLocal()}',
              ),
            ),
            if (due != null)
              TextButton(
                onPressed: () => setState(() {
                  due = null;
                }),
                child: const Text('Remove follow-up'),
              ),
            if (error != null) Text(error!),
            FilledButton(
              onPressed: saving ? null : save,
              child: const Text('Save interaction'),
            ),
          ],
        ),
      ),
    ),
  );
}
