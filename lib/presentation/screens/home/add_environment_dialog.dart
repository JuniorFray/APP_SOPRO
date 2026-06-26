import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/environment_entity.dart';
import '../../providers/database_provider.dart';

// Dialog para criar um novo Environment.
// Usa ConsumerStatefulWidget para acessar o repositório e manter estado do form.
class AddEnvironmentDialog extends ConsumerStatefulWidget {
  const AddEnvironmentDialog({super.key});

  @override
  ConsumerState<AddEnvironmentDialog> createState() =>
      _AddEnvironmentDialogState();
}

class _AddEnvironmentDialogState extends ConsumerState<AddEnvironmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _radiusController =
      TextEditingController(text: AppStrings.radiusDefault);

  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.backgroundElevated,
      title: const Text(
        AppStrings.addEnvironmentTitle,
        style: TextStyle(color: AppTheme.textPrimary),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Field(
                controller: _nameController,
                label: AppStrings.environmentNameLabel,
                hint: AppStrings.environmentNameHint,
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? AppStrings.environmentNameRequired
                        : null,
              ),
              const SizedBox(height: 12),
              _Field(
                controller: _latController,
                label: AppStrings.latitudeLabel,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  return (n == null || n < -90 || n > 90)
                      ? AppStrings.latitudeInvalid
                      : null;
                },
              ),
              const SizedBox(height: 12),
              _Field(
                controller: _lngController,
                label: AppStrings.longitudeLabel,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  return (n == null || n < -180 || n > 180)
                      ? AppStrings.longitudeInvalid
                      : null;
                },
              ),
              const SizedBox(height: 12),
              _Field(
                controller: _radiusController,
                label: AppStrings.radiusLabel,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  return (n == null || n <= 0) ? AppStrings.radiusInvalid : null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text(
            AppStrings.cancel,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        TextButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent,
                  ),
                )
              : const Text(
                  AppStrings.save,
                  style: TextStyle(color: AppTheme.accent),
                ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final entity = EnvironmentEntity(
      id: '', // repositório gera o UUID
      name: _nameController.text.trim(),
      latitude: double.parse(_latController.text),
      longitude: double.parse(_lngController.text),
      radiusMeters: double.parse(_radiusController.text),
      createdAt: DateTime.now(),
    );

    await ref.read(environmentRepositoryProvider).save(entity);

    if (mounted) Navigator.pop(context);
  }
}

// Campo de texto estilizado para o dialog
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppTheme.textPrimary),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppTheme.textSecondary),
        hintStyle: const TextStyle(color: AppTheme.textDisabled),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.backgroundSurface),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.accent),
        ),
        errorBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.red),
        ),
        filled: true,
        fillColor: AppTheme.backgroundSurface,
      ),
    );
  }
}
