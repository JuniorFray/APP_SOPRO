import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../infrastructure/auth/auth_service.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/sopro_primary_button.dart';
import '../../widgets/sopro_text_field.dart';

// Tela única de Conta (Fase 1 — Supabase Auth).
//
// Deslogado → formulário e-mail/senha com alternância login/cadastro e
// "esqueci minha senha". Logado → e-mail + botão Sair. A troca de UI é reativa
// (observa authSessionProvider) — sem setState de sessão, só do formulário local.
//
// Escopo Fase 1: só autenticação. Nenhum dado depende disto ainda (ambientes/
// gatilhos/lembretes continuam locais). Login é OPCIONAL — o resto do app
// funciona sem conta.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _signupMode = false; // false = login, true = cadastro
  bool _busy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: const Text(AppStrings.accountScreenTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: const GlassSurface(
          borderRadius: BorderRadius.zero,
          edges: GlassEdges.bottom,
          child: SizedBox.expand(),
        ),
      ),
      body: SafeArea(
        child: session != null ? _buildLoggedIn(session) : _buildForm(),
      ),
    );
  }

  // ── Estado LOGADO ──────────────────────────────────────────────────────────
  Widget _buildLoggedIn(AuthSession session) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SizedBox(height: AppSpacing.lg),
        const Icon(LucideIcons.userCheck, color: AppColors.success, size: 48),
        const SizedBox(height: AppSpacing.md),
        Text(
          AppStrings.accountSignedInDesc,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          session.email,
          textAlign: TextAlign.center,
          style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xxl),
        SoproPrimaryButton(
          label: AppStrings.authLogout,
          loading: _busy,
          onPressed: _busy ? null : _confirmLogout,
        ),
        // Validação Fase 1 (só em debug): força expiração e testa o refresh
        // nativo do Overlay via MethodChannel. Não vai para produção.
        if (kDebugMode) ...[
          const SizedBox(height: AppSpacing.lg),
          TextButton(
            onPressed: _busy ? null : _testOverlayRefresh,
            child: Text(
              'Debug: testar refresh do overlay',
              style: AppTypography.caption.copyWith(color: AppColors.textDisabled),
            ),
          ),
        ],
      ],
    );
  }

  // Canal de teste do refresh nativo (só debug). Simula token vencido → refresh →
  // lê o estado resultante e mostra num snackbar.
  static const _authChannel = MethodChannel('com.sopro.sopro/auth');
  Future<void> _testOverlayRefresh() async {
    setState(() => _busy = true);
    try {
      await _authChannel.invokeMethod('simulateExpiry');
      final ok = await _authChannel.invokeMethod<bool>('refresh') ?? false;
      final info = await _authChannel.invokeMethod<Map<dynamic, dynamic>>('tokenInfo');
      if (!mounted) return;
      _snack('refresh=$ok · expired=${info?['isExpired']} · exp=${info?['expiresAt']}');
    } catch (e) {
      if (mounted) _snack('Falha no teste: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Estado DESLOGADO — formulário ───────────────────────────────────────────
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const SizedBox(height: AppSpacing.md),
          Text(
            _signupMode ? AppStrings.authSignupTitle : AppStrings.authLoginTitle,
            style: AppTypography.titleLarge.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.lg),
          SoproTextField(
            controller: _emailCtrl,
            label: AppStrings.authEmailLabel,
            hint: AppStrings.authEmailHint,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            prefixIcon: const Icon(LucideIcons.mail, size: 18),
            validator: _validateEmail,
          ),
          const SizedBox(height: AppSpacing.md),
          SoproTextField(
            controller: _passwordCtrl,
            label: AppStrings.authPasswordLabel,
            hint: AppStrings.authPasswordHint,
            obscureText: true,
            textInputAction: TextInputAction.done,
            prefixIcon: const Icon(LucideIcons.lock, size: 18),
            validator: _validatePassword,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.lg),
          SoproPrimaryButton(
            label: _signupMode ? AppStrings.authSignupCta : AppStrings.authLoginCta,
            loading: _busy,
            onPressed: _busy ? null : _submit,
          ),
          const SizedBox(height: AppSpacing.md),
          // Alternância login <-> cadastro
          TextButton(
            onPressed: _busy ? null : () => setState(() => _signupMode = !_signupMode),
            child: Text(
              _signupMode ? AppStrings.authToggleToLogin : AppStrings.authToggleToSignup,
              style: AppTypography.bodySmall.copyWith(color: AppColors.accentPurple),
            ),
          ),
          // "Esqueci minha senha" — só no modo login
          if (!_signupMode)
            TextButton(
              onPressed: _busy ? null : _showRecoverDialog,
              child: Text(
                AppStrings.authForgotPassword,
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  // ── Validação ───────────────────────────────────────────────────────────────
  String? _validateEmail(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return AppStrings.authEmailRequired;
    // Regex simples: algo@algo.algo — suficiente para UX (o servidor valida de fato).
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
      return AppStrings.authEmailInvalid;
    }
    return null;
  }

  String? _validatePassword(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return AppStrings.authPasswordRequired;
    if (s.length < 6) return AppStrings.authPasswordTooShort;
    return null;
  }

  // ── Ações ────────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final service = ref.read(authServiceProvider);
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final result = _signupMode
        ? await service.signUp(email, password)
        : await service.signIn(email, password);

    if (!mounted) return;
    setState(() => _busy = false);

    if (result.success) {
      if (result.needsEmailConfirm) {
        // Cadastro OK mas o projeto exige confirmação de e-mail: volta ao login.
        setState(() => _signupMode = false);
        _snack(AppStrings.authConfirmEmailSent);
      } else {
        // Sessão ativa: o provider já atualizou e a tela troca para "logado".
        _snack(_signupMode ? AppStrings.authSignupSuccess : AppStrings.authLoginSuccess);
      }
    } else {
      _snack(_errorText(result.errorCode));
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundElevated,
        content: Text(AppStrings.authLogoutConfirm,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppStrings.authLogout,
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await ref.read(authServiceProvider).signOut();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _showRecoverDialog() async {
    final ctrl = TextEditingController(text: _emailCtrl.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundElevated,
        title: Text(AppStrings.authRecoverTitle,
            style: AppTypography.titleSmall.copyWith(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.authRecoverBody,
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.md),
            SoproTextField(
              controller: ctrl,
              label: AppStrings.authEmailLabel,
              hint: AppStrings.authEmailHint,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: const Icon(LucideIcons.mail, size: 18),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text(AppStrings.authRecoverCta),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    await ref.read(authServiceProvider).recoverPassword(email);
    if (!mounted) return;
    // Mensagem neutra sempre (não revela existência de conta).
    _snack(AppStrings.authRecoverSent);
  }

  // Traduz o errorCode do AuthService para a string amigável.
  String _errorText(String? code) {
    switch (code) {
      case 'invalid_credentials':
        return AppStrings.authInvalidCredentials;
      case 'email_taken':
        return AppStrings.authEmailTaken;
      case 'no_internet':
        return AppStrings.authNoInternet;
      case 'unavailable':
        return AppStrings.authUnavailable;
      default:
        return AppStrings.authGenericError;
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }
}
