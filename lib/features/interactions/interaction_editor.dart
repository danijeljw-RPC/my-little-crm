import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/crm_service.dart';
import 'communication_method_icon.dart';

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
  final _partyFocus = FocusNode();
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
  bool reopeningFollowUp = false;
  bool saving = false;
  String? error;
  List<Party> _parties = const [];
  @override
  void initState() {
    super.initState();
    _loadParties();
  }

  Future<void> _loadParties() async {
    try {
      final values = await widget.service.parties.list();
      if (mounted) setState(() => _parties = values);
    } catch (_) {
      // A failed suggestion lookup must not prevent manual entry or saving.
    }
  }

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
    _partyFocus.dispose();
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
      final followUp = due == null
          ? null
          : FollowUp(
              dueAt: due!.toUtc(),
              status:
                  existing?.followUp?.status == FollowUpStatus.completed &&
                      !reopeningFollowUp
                  ? FollowUpStatus.completed
                  : FollowUpStatus.open,
            );
      final referenceNumbers = references.text.split(',');
      if (existing == null) {
        await widget.service.createInteraction(
          CreateInteractionCommand(
            partyName: party.text,
            summary: summary.text,
            timestamp: timestamp.toUtc(),
            method: method,
            contactName: contact.text,
            referenceNumbers: referenceNumbers,
            commitment: commitment.text,
            followUpDueAt: followUp?.dueAt,
          ),
        );
      } else {
        await widget.service.updateInteraction(
          UpdateInteractionCommand(
            summary: summary.text,
            interaction: Interaction(
              id: existing.id,
              partyId: existing.partyId,
              createdAt: existing.createdAt,
              timestamp: timestamp.toUtc(),
              summary: summary.text,
              method: method,
              contactName: contact.text,
              referenceNumbers: referenceNumbers,
              commitment: commitment.text,
              followUp: followUp,
            ),
          ),
        );
      }
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
            RawAutocomplete<Party>(
              textEditingController: party,
              focusNode: _partyFocus,
              displayStringForOption: (value) => value.name,
              optionsBuilder: (value) =>
                  widget.existing != null || value.text.trim().isEmpty
                  ? const Iterable<Party>.empty()
                  : _parties.where(
                      (p) => p.name.toLowerCase().contains(
                        value.text.trim().toLowerCase(),
                      ),
                    ),
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
                  TextFormField(
                    key: const Key('party-name'),
                    controller: controller,
                    focusNode: focusNode,
                    readOnly: widget.existing != null,
                    decoration: const InputDecoration(
                      labelText: 'Company or person',
                    ),
                    validator: (s) => s == null || s.trim().isEmpty
                        ? 'Enter a company or person'
                        : null,
                  ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  child: SizedBox(
                    width: 300,
                    height: 160,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final option in options)
                          ListTile(
                            title: Text(option.name),
                            onTap: () => onSelected(option),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
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
                  DropdownMenuItem(
                    value: value,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(value.icon, size: 20),
                        const SizedBox(width: 12),
                        Text(value.name),
                      ],
                    ),
                  ),
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
                final value = await date(
                  due ?? widget.service.clock.now().toLocal(),
                );
                if (value != null && mounted) {
                  setState(() {
                    due = value;
                    reopeningFollowUp = true;
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
                  reopeningFollowUp = true;
                }),
                child: const Text('Remove follow-up'),
              ),
            if (widget.existing?.followUp?.status == FollowUpStatus.completed &&
                !reopeningFollowUp)
              const Text(
                'This follow-up is completed. Choose a date to reopen it.',
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
