import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../domain/models.dart';
import '../../domain/crm_service.dart';
import 'communication_method_icon.dart';

/// Windows at least this wide use a dialog instead of a bottom sheet (#31).
const editorDialogMinWidth = 600.0;

Future<void> editInteraction(
  BuildContext context,
  CrmService service, {
  Interaction? existing,
  String? partyName,
}) async {
  if (MediaQuery.sizeOf(context).width >= editorDialogMinWidth) {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: InteractionEditor(
            service: service,
            existing: existing,
            partyName: partyName,
            inDialog: true,
          ),
        ),
      ),
    );
    return;
  }
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
    this.inDialog = false,
  });
  final CrmService service;
  final Interaction? existing;
  final String? partyName;

  /// A dialog already keeps clear of the keyboard and system bars.
  final bool inDialog;
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
  late bool dueHasTime = widget.existing?.followUp?.hasTime ?? false;
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
              hasTime: dueHasTime,
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
            followUpHasTime: dueHasTime,
          ),
        );
      } else {
        final partyText = party.text.trim();
        await widget.service.updateInteraction(
          UpdateInteractionCommand(
            summary: summary.text,
            // Changing the party of an existing record moves it (#33).
            targetPartyName: partyText == widget.partyName?.trim()
                ? null
                : partyText,
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

  Future<void> _delete() async {
    final existing = widget.existing!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this interaction?'),
        content: const Text(
          'It will be removed from the party history and from search.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final service = widget.service;
    try {
      final deleted = await service.deleteInteraction(existing.id);
      if (mounted) Navigator.pop(context);
      if (deleted == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Interaction deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await service.restoreInteraction(deleted);
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Could not restore the interaction.'),
                  ),
                );
              }
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not delete. Please try again.');
      }
    }
  }

  Future<void> _pickDueTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: dueHasTime
          ? TimeOfDay.fromDateTime(due!)
          : const TimeOfDay(hour: 9, minute: 0),
    );
    if (time != null && mounted) {
      setState(() {
        due = DateTime(due!.year, due!.month, due!.day, time.hour, time.minute);
        dueHasTime = true;
        reopeningFollowUp = true;
      });
    }
  }

  Future<DateTime?> date(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(1900),
    lastDate: DateTime(2200),
  );
  @override
  Widget build(BuildContext context) {
    final format = AppDateFormat.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        // Keep clear of the keyboard and, on edge-to-edge Android, the system
        // navigation bar (#22). When the keyboard is up it already covers the
        // nav bar, so take whichever is larger rather than summing them.
        24 +
            (widget.inDialog
                ? 0
                : math.max(
                    MediaQuery.viewInsetsOf(context).bottom,
                    MediaQuery.viewPaddingOf(context).bottom,
                  )),
      ),
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null
                    ? 'New interaction'
                    : 'Edit interaction',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              RawAutocomplete<Party>(
                textEditingController: party,
                focusNode: _partyFocus,
                displayStringForOption: (value) => value.name,
                optionsBuilder: (value) => value.text.trim().isEmpty
                    ? const Iterable<Party>.empty()
                    : _parties.where(
                        (p) => p.name.toLowerCase().contains(
                          value.text.trim().toLowerCase(),
                        ),
                      ),
                fieldViewBuilder:
                    (context, controller, focusNode, onSubmitted) =>
                        TextFormField(
                          key: const Key('party-name'),
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'Company or person',
                            helperText: widget.existing == null
                                ? null
                                : 'Change this to move the interaction '
                                      'to another party',
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
                child: Text('Occurred: ${format.dateTime(timestamp)}'),
              ),
              TextButton(
                onPressed: () async {
                  final value = await date(
                    due ?? widget.service.clock.now().toLocal(),
                  );
                  if (value != null && mounted) {
                    setState(() {
                      // Keep a chosen time when only the day changes.
                      due = dueHasTime
                          ? DateTime(
                              value.year,
                              value.month,
                              value.day,
                              due!.hour,
                              due!.minute,
                            )
                          : value;
                      reopeningFollowUp = true;
                    });
                  }
                },
                child: Text(
                  due == null
                      ? 'Add follow-up date'
                      : 'Follow-up: ${dueHasTime ? format.dateTime(due!) : format.date(due!)}',
                ),
              ),
              if (due != null)
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      key: const Key('follow-up-time'),
                      onPressed: _pickDueTime,
                      child: Text(
                        dueHasTime
                            ? 'Change due time'
                            : 'Add due time (optional)',
                      ),
                    ),
                    if (dueHasTime)
                      TextButton(
                        onPressed: () => setState(() {
                          due = DateTime(due!.year, due!.month, due!.day);
                          dueHasTime = false;
                          reopeningFollowUp = true;
                        }),
                        child: const Text('Remove time'),
                      ),
                    TextButton(
                      onPressed: () => setState(() {
                        due = null;
                        dueHasTime = false;
                        reopeningFollowUp = true;
                      }),
                      child: const Text('Remove follow-up'),
                    ),
                  ],
                ),
              if (due != null && !dueHasTime)
                Text(
                  'Without a time, it is due by the end of that day.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (widget.existing?.followUp?.status ==
                      FollowUpStatus.completed &&
                  !reopeningFollowUp)
                const Text(
                  'This follow-up is completed. Choose a date to reopen it.',
                ),
              if (error != null) Text(error!),
              FilledButton(
                onPressed: saving ? null : save,
                child: const Text('Save interaction'),
              ),
              if (widget.existing != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: saving ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete interaction'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
