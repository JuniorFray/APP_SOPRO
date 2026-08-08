import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/database/sopro_database.dart';
import '../../../domain/models/calendar_event.dart';
import '../../providers/agenda_providers.dart';
import '../../providers/database_provider.dart';

class AgendaEventDialog extends ConsumerStatefulWidget {
  final DateTime initialDate;

  // Evento a editar. Null = criação de um novo evento. Quando preenchido, o
  // formulário é pré-populado e o salvar faz UPDATE (mesmo id) em vez de INSERT.
  final CalendarEvent? existingEvent;

  const AgendaEventDialog({super.key, required this.initialDate, this.existingEvent});

  @override
  ConsumerState<AgendaEventDialog> createState() => _AgendaEventDialogState();
}

class _AgendaEventDialogState extends ConsumerState<AgendaEventDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  String _category = 'Pessoal';

  @override
  void initState() {
    super.initState();
    final e = widget.existingEvent;
    _titleController = TextEditingController(text: e?.title ?? '');
    _descriptionController = TextEditingController(text: e?.description ?? '');
    if (e != null) {
      // Modo edição: pré-popula horários e categoria do evento existente.
      _startTime = TimeOfDay.fromDateTime(e.startTime);
      _endTime = TimeOfDay.fromDateTime(e.endTime);
      if (e.category != null) _category = e.category!;
    } else {
      _startTime = TimeOfDay.now();
      _endTime = TimeOfDay(hour: (_startTime.hour + 1) % 24, minute: _startTime.minute);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    final startDateTime = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
      _startTime.hour,
      _startTime.minute,
    );

    final endDateTime = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
      _endTime.hour,
      _endTime.minute,
    );

    // Validação: fim precisa ser posterior ao início (mesmo dia).
    if (!endDateTime.isAfter(startDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O horário de término deve ser depois do início.')),
      );
      return;
    }

    // Datas em SEGUNDOS (convenção do banco).
    final startSec = startDateTime.millisecondsSinceEpoch ~/ 1000;
    final endSec = endDateTime.millisecondsSinceEpoch ~/ 1000;
    final desc = _descriptionController.text.trim();
    final descValue = Value(desc.isEmpty ? null : desc);

    final db = ref.read(databaseProvider);
    final dao = db.agendaEventDao;
    final existing = widget.existingEvent;

    if (existing != null) {
      // Edição: UPDATE no MESMO id — não gera duplicata. Preserva a origem
      // (sopro/ai_suggestion) do evento editado.
      final sourceStr = existing.source == EventSource.soproAi ? 'ai_suggestion' : 'sopro';
      await dao.updateEvent(
        AgendaEventTableCompanion(
          id: Value(existing.id),
          title: Value(_titleController.text.trim()),
          description: descValue,
          startTime: Value(startSec),
          endTime: Value(endSec),
          source: Value(sourceStr),
          category: Value(_category),
        ),
      );
    } else {
      // Criação: novo UUID.
      await dao.insertEvent(
        AgendaEventTableCompanion.insert(
          id: const Uuid().v4(),
          title: _titleController.text.trim(),
          description: descValue,
          startTime: startSec,
          endTime: endSec,
          source: const Value('sopro'),
          category: Value(_category),
        ),
      );
    }

    ref.read(agendaProvider.notifier).loadEventsForMonth(widget.initialDate);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(existing != null
            ? 'Evento atualizado!'
            : 'Evento adicionado à Agenda Sopro!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.backgroundSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.existingEvent != null ? 'Editar Evento' : 'Novo Evento Sopro',
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Título do Evento',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.backgroundCard,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  validator: (value) => value == null || value.isEmpty ? 'Informe o título' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Descrição (opcional)',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.backgroundCard,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        title: const Text('Início', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        subtitle: Text(_startTime.format(context), style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                        onTap: () async {
                          final picked = await showTimePicker(context: context, initialTime: _startTime);
                          if (picked != null) setState(() => _startTime = picked);
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        title: const Text('Fim', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        subtitle: Text(_endTime.format(context), style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                        onTap: () async {
                          final picked = await showTimePicker(context: context, initialTime: _endTime);
                          if (picked != null) setState(() => _endTime = picked);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _category,
                  dropdownColor: AppColors.backgroundCard,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Categoria',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.backgroundCard,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  items: ['Pessoal', 'Trabalho', 'Saúde', 'Sopro AI'].map((c) {
                    return DropdownMenuItem(value: c, child: Text(c));
                  }).toList(),
                  onChanged: (val) => setState(() => _category = val!),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _saveEvent,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Salvar Evento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
