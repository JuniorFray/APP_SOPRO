// ProfileScreen — Editor do ContextCard do usuário.
//
// Permite criar ou editar o perfil público trocado via BLE com outros
// usuários Sopro próximos. Campos:
//   - Nome (displayName) — obrigatório
//   - Cargo (role)
//   - Empresa (company)
//   - Interesses (tags, separadas por vírgula)
//   - Nota pessoal (bio, texto livre)
//   - Toggle: Visível para outros (bleVisibleProvider)
//
// Navegação: sempre acessado via pushNamed('/profile') do HomeScreen.
// Após salvar → Navigator.pop() retorna ao HomeScreen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/context_card_entity.dart';
import '../../providers/ble_providers.dart';
import '../../providers/database_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Controladores dos campos de texto
  final _nameCtrl    = TextEditingController();
  final _roleCtrl    = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _tagsCtrl    = TextEditingController();
  final _bioCtrl     = TextEditingController();

  final _formKey     = GlobalKey<FormState>();

  ContextCardEntity? _existingCard; // preenchido ao carregar o card ativo do banco
  bool _loaded  = false; // true após carregar dados do banco
  bool _saving  = false; // true enquanto persiste no banco

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _loadCard();
  }

  // Carrega o ContextCard ativo do banco e pré-preenche os campos
  Future<void> _loadCard() async {
    final card = await ref.read(contextCardRepositoryProvider).getActive();
    if (!mounted) return;
    _existingCard = card;
    if (card != null) {
      _nameCtrl.text    = card.displayName;
      _roleCtrl.text    = card.role;
      _companyCtrl.text = card.company;
      _tagsCtrl.text    = card.tags;
      _bioCtrl.text     = card.bio;
    }
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _companyCtrl.dispose();
    _tagsCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  // Salva o ContextCard no banco e gerencia a navegação pós-save
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    try {
      final entity = ContextCardEntity(
        id: _existingCard?.id ?? '',            // vazio → repositório gera UUID
        displayName: _nameCtrl.text.trim(),
        role: _roleCtrl.text.trim(),
        company: _companyCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
        tags: _tagsCtrl.text.trim(),
        createdAt: _existingCard?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),              // repositório sobrescreve com now()
      );

      await ref.read(contextCardRepositoryProvider).save(entity);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.profileSaved),
          backgroundColor: AppTheme.success,
          duration: Duration(seconds: 2),
        ),
      );

      // Volta ao HomeScreen (sempre empilhado abaixo via pushNamed)
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.errorGeneric),
            backgroundColor: AppTheme.accent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVisible = ref.watch(bleVisibleProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: const Text(AppStrings.profileTitle),
        backgroundColor: AppTheme.backgroundSurface,
      ),
      body: _loaded ? _buildForm(isVisible) : _buildLoading(),
    );
  }

  // Spinner exibido enquanto o banco carrega
  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: AppTheme.accent),
    );
  }

  Widget _buildForm(bool isVisible) {
    // Avatar com inicial do nome (atualizado em tempo real)
    final initial = _nameCtrl.text.isNotEmpty
        ? _nameCtrl.text[0].toUpperCase()
        : '?';

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        children: [
          // ── Avatar ──────────────────────────────────────────────────────
          Center(
            child: CircleAvatar(
              radius: 40,
              // ignore: deprecated_member_use
              backgroundColor: AppTheme.accent.withOpacity(0.15),
              child: Text(
                initial,
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // ── Seção: Identidade ───────────────────────────────────────────
          const _SectionLabel(label: AppStrings.profileSectionIdentity),
          const SizedBox(height: 12),

          // Nome (obrigatório)
          TextFormField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecoration(
              label: AppStrings.profileName,
              hint: AppStrings.profileNameHint,
            ),
            maxLength: 50,
            onChanged: (_) => setState(() {}), // atualiza avatar em tempo real
            validator: (v) => (v == null || v.trim().isEmpty)
                ? AppStrings.profileNameRequired
                : null,
          ),
          const SizedBox(height: 12),

          // Cargo
          TextFormField(
            controller: _roleCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecoration(
              label: AppStrings.profileRole,
              hint: AppStrings.profileRoleHint,
            ),
            maxLength: 60,
          ),
          const SizedBox(height: 12),

          // Empresa
          TextFormField(
            controller: _companyCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecoration(
              label: AppStrings.profileCompany,
              hint: AppStrings.profileCompanyHint,
            ),
            maxLength: 60,
          ),
          const SizedBox(height: 24),

          // ── Seção: Contexto ─────────────────────────────────────────────
          const _SectionLabel(label: AppStrings.profileSectionContext),
          const SizedBox(height: 12),

          // Interesses (tags comma-separated)
          TextFormField(
            controller: _tagsCtrl,
            textCapitalization: TextCapitalization.none,
            decoration: _inputDecoration(
              label: AppStrings.profileInterests,
              hint: AppStrings.profileInterestsHint,
            ),
            maxLength: 120,
          ),
          const SizedBox(height: 12),

          // Nota pessoal (bio, multiline)
          TextFormField(
            controller: _bioCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: _inputDecoration(
              label: AppStrings.profileNote,
              hint: AppStrings.profileNoteHint,
            ),
            maxLines: 4,
            maxLength: 500,
          ),
          const SizedBox(height: 24),

          // ── Seção: Privacidade ──────────────────────────────────────────
          const _SectionLabel(label: AppStrings.profileSectionPrivacy),
          const SizedBox(height: 8),

          // Toggle de visibilidade BLE
          Container(
            decoration: BoxDecoration(
              color: AppTheme.backgroundSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              value: isVisible,
              onChanged: (v) =>
                  ref.read(bleVisibleProvider.notifier).state = v,
              activeColor: AppTheme.accent,
              title: const Text(
                AppStrings.profileVisible,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: const Text(
                AppStrings.profileVisibleDesc,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // ── Botão de salvar ─────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(AppStrings.profileSave),
            ),
          ),
        ],
      ),
    );
  }

  // Helper para decoração consistente dos campos
  InputDecoration _inputDecoration({
    required String label,
    required String hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: AppTheme.textSecondary),
      hintStyle: const TextStyle(color: AppTheme.textDisabled),
      filled: true,
      fillColor: AppTheme.backgroundSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
      ),
      counterStyle: const TextStyle(color: AppTheme.textDisabled, fontSize: 11),
    );
  }
}

// Rótulo de seção com separador
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: AppTheme.textDisabled,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}
