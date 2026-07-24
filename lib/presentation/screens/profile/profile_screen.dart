// ProfileScreen — Editor do ContextCard do usuário.
//
// Permite criar ou editar o perfil público trocado via BLE com outros
// usuários Sopro próximos. Campos:
//   - Foto (opcional, armazenada localmente — nunca enviada para BLE ou servidor)
//   - Nome (displayName) — obrigatório
//   - Empresa (company)
//   - Interesses (tags, separadas por vírgula)
//   - Nota pessoal (bio, texto livre)
//   - Telefone/WhatsApp (phone, opcional — compartilhado via BLE)
//   - Toggle: Compartilhar WhatsApp (shareWhatsAppProvider)
//
// O campo Cargo (role) foi removido da UI, mas a coluna/campo permanece no
// banco e no modelo. Valor antigo é preservado silenciosamente no save.
//
// O toggle "Visível para outros" vive apenas em Configurações (bleVisibleProvider),
// não é duplicado aqui.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/entities/context_card_entity.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/sopro_card.dart';
import '../../widgets/sopro_primary_button.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  // showBackButton: true no push normal ('/profile', ícone da Home) — mostra a
  // seta de voltar. false quando embutida como aba do MainShellScreen (não há
  // "voltar" de uma aba), escondendo o leading do AppBar.
  final bool showBackButton;

  const ProfileScreen({super.key, this.showBackButton = true});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Controladores dos campos de texto (Cargo não é mais exibido)
  final _nameCtrl    = TextEditingController();
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
        // Cargo saiu da UI, mas o valor antigo é preservado silenciosamente.
        role: _existingCard?.role ?? '',
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
    final shareWhatsApp = ref.watch(shareWhatsAppProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: const Text(AppStrings.profileTitle),
        // Sem seta de voltar quando renderizada como aba do shell.
        automaticallyImplyLeading: widget.showBackButton,
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
      body: _loaded ? _buildForm(shareWhatsApp) : _buildLoading(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: AppTheme.accent),
    );
  }

  // Padding interno dos cards de seção: horizontal folgado (iOS Settings),
  // vertical mínimo — o ritmo vertical nasce de cada _ProfileField.
  static const _cardPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.xxs,
  );

  // Divisor fino entre campos "nus" (branco 8%, alinhado ao texto).
  static const _fieldDivider = Divider(
    height: 1,
    thickness: 1,
    color: AppColors.border,
  );

  Widget _buildForm(bool shareWhatsApp) {
    // Inicial do nome para o avatar quando não há foto
    final initial = _nameCtrl.text.isNotEmpty
        ? _nameCtrl.text[0].toUpperCase()
        : '?';

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        children: [
          // ── Avatar herói + nome/empresa ──────────────────────────────────
          Center(child: _buildAvatar(initial)),
          const SizedBox(height: AppSpacing.md),

          // Nome grande: protagonista do topo. Cai no placeholder enquanto vazio.
          Text(
            _nameCtrl.text.trim().isEmpty
                ? AppStrings.profileNameHint
                : _nameCtrl.text.trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          // Empresa/organização, se preenchida — cinza discreto abaixo do nome.
          if (_companyCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              _companyCtrl.text.trim(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDisabled,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.section),

          // ── Seção: Identidade ───────────────────────────────────────────
          const _SectionLabel(
            label: AppStrings.profileSectionIdentity,
            icon: LucideIcons.user,
          ),
          const SizedBox(height: AppSpacing.titleGap),
          SoproCard(
            glass: true,
            padding: _cardPadding,
            child: Column(
              children: [
                _ProfileField(
                  controller: _nameCtrl,
                  label: AppStrings.profileName,
                  hint: AppStrings.profileNameHint,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 50,
                  onChanged: (_) => setState(() {}), // atualiza herói em tempo real
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? AppStrings.profileNameRequired
                      : null,
                ),
                _fieldDivider,
                _ProfileField(
                  controller: _companyCtrl,
                  label: AppStrings.profileCompany,
                  hint: AppStrings.profileCompanyHint,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 60,
                  onChanged: (_) => setState(() {}), // atualiza herói em tempo real
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.section),

          // ── Seção: Contexto ─────────────────────────────────────────────
          const _SectionLabel(
            label: AppStrings.profileSectionContext,
            icon: LucideIcons.sparkles,
          ),
          const SizedBox(height: AppSpacing.titleGap),
          SoproCard(
            glass: true,
            padding: _cardPadding,
            child: Column(
              children: [
                _ProfileField(
                  controller: _tagsCtrl,
                  label: AppStrings.profileInterests,
                  hint: AppStrings.profileInterestsHint,
                  maxLength: 120,
                ),
                _fieldDivider,
                _ProfileField(
                  controller: _bioCtrl,
                  label: AppStrings.profileNote,
                  hint: AppStrings.profileNoteHint,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 3,
                  maxLines: null, // cresce conforme o texto
                  maxLength: 500,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.section),

          // ── Seção: Contato (campo + toggle juntos) ──────────────────────
          const _SectionLabel(
            label: AppStrings.profileSectionContact,
            icon: LucideIcons.mail,
          ),
          const SizedBox(height: AppSpacing.titleGap),
          SoproCard(
            glass: true,
            padding: _cardPadding,
            child: Column(
              children: [
                // WhatsApp/telefone — compartilhado via BLE se preenchido.
                // Só dígitos; o app monta o link wa.me/55<número> ao exibir o cartão.
                _ProfileField(
                  controller: _phoneCtrl,
                  label: AppStrings.profilePhone,
                  hint: AppStrings.profilePhoneHint,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 13,
                  prefix: const Icon(
                    LucideIcons.messageCircle,
                    color: AppColors.textDisabled,
                    size: 18,
                  ),
                  helper: Text(
                    shareWhatsApp
                        ? AppStrings.profilePhoneHelperOn
                        : AppStrings.profilePhoneHelperOff,
                    style: AppTypography.caption.copyWith(
                      color: shareWhatsApp
                          ? AppColors.accent
                          : AppColors.textDisabled,
                    ),
                  ),
                ),
                _fieldDivider,
                // Toggle: compartilha o telefone no cartão BLE ou não.
                // O número continua salvo no perfil mas é omitido do payload se desligado.
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
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
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          SoproPrimaryButton(
            label: AppStrings.profileSave,
            onPressed: _saving ? null : _save,
            loading: _saving,
          ),
          const SizedBox(height: AppSpacing.sm),

          // Botão secundário: descarta e volta sem salvar.
          SizedBox(
            height: 52,
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.backgroundCard,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              child: Text(
                AppStrings.cancel,
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Avatar de ~96px com anel coral fino (2px) e gap de 3px até o círculo.
  // Botão de câmera fixado na borda inferior-direita.
  Widget _buildAvatar(String initial) {
    return Tooltip(
      message: AppStrings.profilePhotoTooltip,
      child: GestureDetector(
        onTap: _showPhotoOptions,
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            // Anel: borda 2px accent + padding 3px (gap) + círculo 96px.
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: AppColors.accent, width: 2),
                ),
              ),
              child: CircleAvatar(
                radius: 48,
                backgroundImage:
                    _photoFile != null ? FileImage(_photoFile!) : null,
                // ignore: deprecated_member_use
                backgroundColor: AppColors.accent.withOpacity(0.15),
                // Exibe inicial apenas quando não há foto
                child: _photoFile == null
                    ? Text(
                        initial,
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
            ),
            // Ícone de câmera indica que o avatar é clicável
            Container(
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(6),
              child: const Icon(
                Icons.camera_alt,
                color: AppColors.textPrimary,
                size: 17,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Rótulo de seção com ícone Lucide à esquerda (UPPERCASE 12px, tracking 1.2).
class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textDisabled),
        const SizedBox(width: AppSpacing.gap6),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textDisabled,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// Campo "nu" estilo iOS Settings: sem fundo, sem borda própria.
// Label 12px cinza acima (fica accent quando focado), valor branco 16px como
// protagonista, contador X/Y visível só quando focado ou acima de 80% do limite.
class _ProfileField extends StatefulWidget {
  const _ProfileField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.onChanged,
    this.prefix,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int? maxLength;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final Widget? prefix; // ícone à esquerda (ex.: WhatsApp)
  final Widget? helper; // linha de apoio abaixo (ex.: status de compartilhamento)

  @override
  State<_ProfileField> createState() => _ProfileFieldState();
}

class _ProfileFieldState extends State<_ProfileField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    // Foco destaca a label (accent) em vez de acender uma caixa no campo.
    _focusNode.addListener(() {
      if (_focused != _focusNode.hasFocus) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = _focused ? AppColors.accent : AppColors.textDisabled;
    final len = widget.controller.text.characters.length;
    // Contador só aparece com foco ou quando passa de 80% do limite.
    final showCounter = widget.maxLength != null &&
        (_focused || len > widget.maxLength! * 0.8);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (showCounter)
                Text(
                  '$len/${widget.maxLength}',
                  style: const TextStyle(
                    color: AppColors.textDisabled,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.prefix != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: widget.prefix,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: TextFormField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  keyboardType: widget.keyboardType,
                  maxLines: widget.maxLines,
                  minLines: widget.minLines,
                  maxLength: widget.maxLength,
                  validator: widget.validator,
                  inputFormatters: widget.inputFormatters,
                  textCapitalization: widget.textCapitalization,
                  cursorColor: AppColors.accent,
                  onChanged: (v) {
                    setState(() {}); // atualiza contador em tempo real
                    widget.onChanged?.call(v);
                  },
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '', // contador próprio suprime o padrão
                    hintText: widget.hint,
                    hintStyle: const TextStyle(
                      color: AppColors.textDisabled,
                      fontSize: 15,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    errorStyle: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (widget.helper != null) ...[
            const SizedBox(height: 4),
            widget.helper!,
          ],
        ],
      ),
    );
  }
}
