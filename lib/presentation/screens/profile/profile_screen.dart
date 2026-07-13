// ProfileScreen — Editor do ContextCard do usuário.
//
// Permite criar ou editar o perfil público trocado via BLE com outros
// usuários Sopro próximos. Campos:
//   - Foto (opcional, armazenada localmente — nunca enviada para BLE ou servidor)
//   - Nome (displayName) — obrigatório
//   - Cargo (role)
//   - Empresa (company)
//   - Interesses (tags, separadas por vírgula)
//   - Nota pessoal (bio, texto livre)
//   - Telefone/WhatsApp (phone, opcional — compartilhado via BLE)
//   - Toggle: Visível para outros (bleVisibleProvider)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/entities/context_card_entity.dart';
import '../../providers/ble_providers.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/sopro_primary_button.dart';
import '../../widgets/sopro_text_field.dart';

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
  final _phoneCtrl   = TextEditingController();

  final _formKey     = GlobalKey<FormState>();

  ContextCardEntity? _existingCard; // preenchido ao carregar o card ativo do banco
  File? _photoFile;                 // foto do perfil (só local, nunca enviada via BLE)
  bool _loaded  = false;            // true após carregar dados do banco
  bool _saving  = false;            // true enquanto persiste no banco

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _loadCard();
  }

  // Carrega o ContextCard ativo do banco e pré-preenche os campos.
  // Também restaura a foto do perfil salva no SharedPreferences.
  Future<void> _loadCard() async {
    final card  = await ref.read(contextCardRepositoryProvider).getActive();
    final prefs = await SharedPreferences.getInstance();
    final photoPath = prefs.getString('profile_photo_path');

    if (!mounted) return;
    _existingCard = card;

    if (card != null) {
      _nameCtrl.text    = card.displayName;
      _roleCtrl.text    = card.role;
      _companyCtrl.text = card.company;
      _tagsCtrl.text    = card.tags;
      _bioCtrl.text     = card.bio;
      _phoneCtrl.text   = card.phone;
    }

    // Verifica se a foto ainda existe no disco antes de exibir
    if (photoPath != null && File(photoPath).existsSync()) {
      _photoFile = File(photoPath);
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
    _phoneCtrl.dispose();
    super.dispose();
  }

  // Exibe um bottom sheet com opções de fonte da foto (câmera ou galeria).
  // A escolha do usuário chama _pickPhotoFrom() com a fonte selecionada.
  Future<void> _showPhotoOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.backgroundSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Alça visual do bottom sheet
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppTheme.textDisabled,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                AppStrings.profilePhotoOptions,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.accent),
              title: const Text(
                AppStrings.profilePhotoCamera,
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhotoFrom(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppTheme.accent),
              title: const Text(
                AppStrings.profilePhotoGallery,
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhotoFrom(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: AppTheme.textSecondary),
              title: const Text(
                AppStrings.cancel,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
  }

  // Captura ou seleciona uma foto de acordo com a [source] escolhida no bottom sheet.
  // A foto é copiada para o diretório de documentos do app e o caminho
  // é salvo no SharedPreferences. A foto NÃO é enviada via BLE nem Supabase.
  Future<void> _pickPhotoFrom(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,   // reduz tamanho do arquivo sem perda visível
      maxWidth:  512,
      maxHeight: 512,
    );
    if (picked == null) return; // usuário cancelou

    // Copia para diretório estável do app (evita que o path temporário expire)
    final appDir   = await getApplicationDocumentsDirectory();
    final destPath = '${appDir.path}/profile_photo.jpg';
    await File(picked.path).copy(destPath);

    // Persiste o caminho para restaurar na próxima sessão
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_photo_path', destPath);

    if (!mounted) return;
    setState(() => _photoFile = File(destPath));
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
        phone: _phoneCtrl.text.trim(),
        createdAt: _existingCard?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
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
    final isVisible    = ref.watch(bleVisibleProvider);
    final shareWhatsApp = ref.watch(shareWhatsAppProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: const Text(AppStrings.profileTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Liquid Glass — delega ao primitivo central GlassSurface.
        flexibleSpace: const GlassSurface(
          borderRadius: BorderRadius.zero,
          edges: GlassEdges.bottom,
          child: SizedBox.expand(),
        ),
      ),
      body: _loaded ? _buildForm(isVisible, shareWhatsApp) : _buildLoading(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: AppTheme.accent),
    );
  }

  Widget _buildForm(bool isVisible, bool shareWhatsApp) {
    // Inicial do nome para o avatar quando não há foto
    final initial = _nameCtrl.text.isNotEmpty
        ? _nameCtrl.text[0].toUpperCase()
        : '?';

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        children: [
          // ── Avatar com suporte a foto ────────────────────────────────────
          Center(
            child: Tooltip(
              message: AppStrings.profilePhotoTooltip,
              child: GestureDetector(
                onTap: _showPhotoOptions,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundImage:
                          _photoFile != null ? FileImage(_photoFile!) : null,
                      // ignore: deprecated_member_use
                      backgroundColor: AppTheme.accent.withOpacity(0.15),
                      // Exibe inicial apenas quando não há foto
                      child: _photoFile == null
                          ? Text(
                              initial,
                              style: const TextStyle(
                                color: AppTheme.accent,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    // Ícone de câmera indica que o avatar é clicável
                    Container(
                      decoration: const BoxDecoration(
                        color: AppTheme.accent,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(5),
                      child: const Icon(
                        Icons.camera_alt,
                        color: AppColors.textPrimary,
                        size: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // ── Seção: Identidade ───────────────────────────────────────────
          const _SectionLabel(label: AppStrings.profileSectionIdentity),
          const SizedBox(height: AppSpacing.sm),

          SoproTextField(
            controller: _nameCtrl,
            label: AppStrings.profileName,
            hint: AppStrings.profileNameHint,
            textCapitalization: TextCapitalization.words,
            maxLength: 50,
            onChanged: (_) => setState(() {}), // atualiza avatar em tempo real
            validator: (v) => (v == null || v.trim().isEmpty)
                ? AppStrings.profileNameRequired
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),

          SoproTextField(
            controller: _roleCtrl,
            label: AppStrings.profileRole,
            hint: AppStrings.profileRoleHint,
            textCapitalization: TextCapitalization.words,
            maxLength: 60,
          ),
          const SizedBox(height: AppSpacing.sm),

          SoproTextField(
            controller: _companyCtrl,
            label: AppStrings.profileCompany,
            hint: AppStrings.profileCompanyHint,
            textCapitalization: TextCapitalization.words,
            maxLength: 60,
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Seção: Contexto ─────────────────────────────────────────────
          const _SectionLabel(label: AppStrings.profileSectionContext),
          const SizedBox(height: AppSpacing.sm),

          SoproTextField(
            controller: _tagsCtrl,
            label: AppStrings.profileInterests,
            hint: AppStrings.profileInterestsHint,
            maxLength: 120,
          ),
          const SizedBox(height: AppSpacing.sm),

          SoproTextField(
            controller: _bioCtrl,
            label: AppStrings.profileNote,
            hint: AppStrings.profileNoteHint,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 4,
            maxLength: 500,
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Seção: Contato ──────────────────────────────────────────────
          const _SectionLabel(label: AppStrings.profileSectionContact),
          const SizedBox(height: AppSpacing.xs),

          // Campo de WhatsApp/telefone — compartilhado via BLE se preenchido.
          // Só dígitos; o app monta o link wa.me/55<número> ao exibir o cartão.
          SoproTextField(
            controller: _phoneCtrl,
            label: AppStrings.profilePhone,
            hint: AppStrings.profilePhoneHint,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            prefixIcon: const Icon(
              Icons.chat_bubble_outline,
              color: AppTheme.textSecondary,
              size: 20,
            ),
            helperText: shareWhatsApp
                ? AppStrings.profilePhoneHelperOn
                : AppStrings.profilePhoneHelperOff,
            helperStyle: AppTypography.caption.copyWith(
              color: shareWhatsApp ? AppTheme.accent : AppTheme.textDisabled,
            ),
            maxLength: 13,
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Seção: Privacidade ──────────────────────────────────────────
          const _SectionLabel(label: AppStrings.profileSectionPrivacy),
          const SizedBox(height: AppSpacing.xs),

          Container(
            decoration: BoxDecoration(
              color: AppTheme.backgroundSurface,
              borderRadius: BorderRadius.circular(AppRadius.icon),
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
          const SizedBox(height: AppSpacing.xs),

          // Toggle independente: compartilha o telefone no cartão BLE ou não.
          // O número continua salvo no perfil mas é omitido do payload se desligado.
          Container(
            decoration: BoxDecoration(
              color: AppTheme.backgroundSurface,
              borderRadius: BorderRadius.circular(AppRadius.icon),
            ),
            child: SwitchListTile(
              value: shareWhatsApp,
              onChanged: (v) async {
                ref.read(shareWhatsAppProvider.notifier).state = v;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('share_whatsapp', v);
              },
              activeColor: AppTheme.accent,
              title: const Text(
                AppStrings.profileShareWhatsApp,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: const Text(
                AppStrings.profileShareWhatsAppDesc,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          SoproPrimaryButton(
            label: AppStrings.profileSave,
            onPressed: _saving ? null : _save,
            loading: _saving,
          ),
        ],
      ),
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
