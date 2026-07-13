import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/entities/ble_encounter_entity.dart';
import '../../../domain/entities/context_card_entity.dart';
import '../../../infrastructure/ble/discovered_sopro_user.dart';
import '../../providers/ble_providers.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/glass_surface.dart';
import '../encounters/encounters_screen.dart';

// PeopleNearbyScreen — "Pessoas Aqui"
//
// Escaneia BLE em busca de outros usuários Sopro (SERVICE_UUID Sopro) e
// permite trocar ContextCards via GATT ao tocar em um usuário encontrado.
//
// Ciclo de vida:
//   onMount  → checa/solicita permissões BLE → inicia scan + advertising
//   onUnmount → para scan + para advertising
class PeopleNearbyScreen extends ConsumerStatefulWidget {
  const PeopleNearbyScreen({super.key});

  @override
  ConsumerState<PeopleNearbyScreen> createState() => _PeopleNearbyScreenState();
}

class _PeopleNearbyScreenState extends ConsumerState<PeopleNearbyScreen> {
  bool _isStarting = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startBle());
  }

  @override
  void dispose() {
    final service = ref.read(bleServiceProvider);
    service.stopScan();
    service.stopAdvertising();
    // Garante que o estado de advertising é resetado na saída da tela
    ref.read(bleAdvertisingProvider.notifier).state = false;
    super.dispose();
  }

  // Inicia permissões, scan e (se houver perfil) advertising
  Future<void> _startBle() async {
    setState(() { _isStarting = true; _errorMessage = null; });
    final service = ref.read(bleServiceProvider);

    // 1. Verifica e solicita permissões BLE
    bool hasPerms = await service.checkPermissions();
    if (!hasPerms) {
      hasPerms = await service.requestPermissions();
    }
    if (!hasPerms) {
      if (mounted) {
        setState(() {
          _isStarting = false;
          _errorMessage = AppStrings.blePermissionDenied;
        });
      }
      return;
    }

    // 2. Verifica se o Bluetooth está ligado via MethodChannel nativo
    final isBtOn = await service.isBluetoothOn();
    if (!isBtOn) {
      if (mounted) {
        setState(() {
          _isStarting = false;
          _errorMessage = AppStrings.bleNotSupported;
        });
      }
      return;
    }

    // 3. Ativa advertising se o usuário tem perfil E quer ser visível.
    //    Usa o nível de potência BLE configurado pelo usuário nas Configurações.
    if (ref.read(bleVisibleProvider)) {
      try {
        final card = await ref.read(contextCardRepositoryProvider).getActive();
        if (card != null) {
          final txPower    = ref.read(bleTxPowerProvider);
          final sharePhone = ref.read(shareWhatsAppProvider);
          final advertised = await service.startAdvertising(
            card,
            txPower: txPower,
            sharePhone: sharePhone,
          );
          if (mounted) {
            ref.read(bleAdvertisingProvider.notifier).state = advertised;
          }
        }
      } catch (e) {
        // Advertising é desejável mas não bloqueador — scan continua sem ele
        debugPrint('[PeopleNearby] Advertising falhou: $e');
      }
    }

    // 4. Inicia o scan BLE filtrado pelo SERVICE_UUID Sopro
    try {
      await service.startScan();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isStarting = false;
          _errorMessage = AppStrings.bleNotSupported;
        });
      }
      return;
    }

    if (mounted) setState(() => _isStarting = false);
  }

  // Conecta ao dispositivo via GATT e exibe o ContextCard recebido
  Future<void> _onUserTapped(DiscoveredSoproUser user) async {
    if (user.card != null) {
      _showCardSheet(user.card!, user.lastSeen);
      return;
    }

    // Mostra loading enquanto carrega o card via GATT
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: AppTheme.backgroundSurface,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accent,
              ),
            ),
            SizedBox(width: AppSpacing.md),
            Text(
              AppStrings.bleCardLoading,
              style: TextStyle(color: AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );

    final service = ref.read(bleServiceProvider);
    final updated = await service.fetchContextCard(user);

    if (mounted) Navigator.of(context).pop(); // fecha loading

    if (updated.card != null) {
      _showCardSheet(updated.card!, updated.lastSeen);
      // Persiste o encontro no banco (upsert por deviceId)
      _saveEncounter(user.deviceId, updated.card!);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.bleCardError)),
        );
      }
    }
  }

  // Persiste o encontro no banco de forma silenciosa (não bloqueia a UI)
  Future<void> _saveEncounter(String deviceId, ContextCardEntity card) async {
    try {
      await ref.read(bleEncounterRepositoryProvider).save(
            BleEncounterEntity(
              deviceId:      deviceId,
              displayName:   card.displayName,
              role:          card.role,
              company:       card.company,
              bio:           card.bio,
              tags:          card.tags,
              phone:         card.phone,
              encounteredAt: DateTime.now(),
            ),
          );
    } catch (e) {
      debugPrint('[PeopleNearby] Falha ao salvar encontro: $e');
    }
  }

  void _showCardSheet(ContextCardEntity card, DateTime lastSeen) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.button)),
      ),
      builder: (_) => _ContextCardSheet(card: card, lastSeen: lastSeen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(nearbyUsersProvider);
    final isAdvertising = ref.watch(bleAdvertisingProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: const Text(AppStrings.peopleNearby),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Liquid Glass — delega ao primitivo central GlassSurface.
        flexibleSpace: const GlassSurface(
          borderRadius: BorderRadius.zero,
          edges: GlassEdges.bottom,
          child: SizedBox.expand(),
        ),
        actions: [
          // Histórico de encontros BLE
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EncountersScreen()),
            ),
            icon: const Icon(Icons.history),
            tooltip: AppStrings.encountersTitle,
          ),
          // Indicador de visibilidade (advertising ativo ou não)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: _AdvertisingChip(isAdvertising: isAdvertising),
          ),
        ],
      ),
      body: _buildBody(usersAsync),
    );
  }

  Widget _buildBody(AsyncValue<List<DiscoveredSoproUser>> usersAsync) {
    // Estado de erro de permissão ou Bluetooth desligado
    if (_errorMessage != null) {
      return _ErrorState(message: _errorMessage!);
    }

    // Iniciando scan/advertising
    if (_isStarting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.accent),
            SizedBox(height: AppSpacing.md),
            Text(
              AppStrings.bleScanning,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return usersAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      ),
      error: (e, _) => const _ErrorState(message: AppStrings.bleNotSupported),
      data: (users) {
        if (users.isEmpty) {
          return const _EmptyState();
        }
        return Column(
          children: [
            // Banner de scan ativo
            const _ScanningBanner(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: AppSpacing.md),
                itemCount: users.length,
                itemBuilder: (_, i) => _UserTile(
                  user: users[i],
                  onTap: () => _onUserTapped(users[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets auxiliares
// ─────────────────────────────────────────────────────────────────────────────

// Banner discreto indicando que o scan está ativo
class _ScanningBanner extends StatelessWidget {
  const _ScanningBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.accent.withOpacity(0.1), // ignore: deprecated_member_use
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(width: AppSpacing.gap10),
          Text(
            AppStrings.bleScanning,
            style: AppTypography.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// Chip no AppBar indicando se o usuário está visível via advertising
class _AdvertisingChip extends StatelessWidget {
  final bool isAdvertising;
  const _AdvertisingChip({required this.isAdvertising});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gap10, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: isAdvertising
            ? AppTheme.accent.withOpacity(0.15) // ignore: deprecated_member_use
            : Colors.grey.withOpacity(0.15),    // ignore: deprecated_member_use
        borderRadius: BorderRadius.circular(AppRadius.icon),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAdvertising ? Icons.wifi_tethering : Icons.wifi_tethering_off,
            size: 14,
            color: isAdvertising ? AppTheme.accent : AppTheme.textSecondary,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            isAdvertising
                ? AppStrings.bleAdvertising
                : AppStrings.bleNotAdvertising,
            style: AppTypography.bodySmall.copyWith(color: isAdvertising ? AppTheme.accent : AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// Card de um usuário Sopro detectado
class _UserTile extends StatelessWidget {
  final DiscoveredSoproUser user;
  final VoidCallback onTap;

  const _UserTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.backgroundSurface,
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.icon)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        leading: CircleAvatar(
          backgroundColor: AppTheme.accent.withOpacity(0.15), // ignore: deprecated_member_use
          child: Text(
            user.deviceName.isNotEmpty ? user.deviceName[0].toUpperCase() : '?',
            style: const TextStyle(
              color: AppTheme.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          user.card?.displayName ?? user.deviceName,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: user.card != null
            ? Text(
                user.card!.bio.isNotEmpty ? user.card!.bio : user.card!.tags,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(color: AppTheme.textSecondary),
              )
            : Text(
                AppStrings.bleViewCard,
                style: AppTypography.bodyMedium.copyWith(color: AppTheme.accent),
              ),
        trailing: _RssiIndicator(level: user.rssiLevel),
      ),
    );
  }
}

// Indicador visual da intensidade do sinal BLE
class _RssiIndicator extends StatelessWidget {
  final RssiLevel level;
  const _RssiIndicator({required this.level});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (level) {
      RssiLevel.strong => (Icons.signal_cellular_alt,     AppStrings.bleSignalStrong, AppTheme.accent),
      RssiLevel.medium => (Icons.signal_cellular_alt_2_bar, AppStrings.bleSignalMedium, Colors.orange),
      RssiLevel.weak   => (Icons.signal_cellular_alt_1_bar, AppStrings.bleSignalWeak,   Colors.grey),
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 20),
        Text(label, style: AppTypography.labelSmall.copyWith(color: color)),
      ],
    );
  }
}

// Estado vazio: nenhum usuário encontrado ainda
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_searching, size: 72, color: AppTheme.accent),
          SizedBox(height: AppSpacing.lg),
          Text(
            AppStrings.bleNoUsers,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            AppStrings.bleNoUsersHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// Estado de erro (permissão negada ou BT indisponível)
class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// Bottom sheet com o ContextCard completo de um usuário detectado.
// Mostra todos os campos preenchidos; omite silenciosamente campos vazios.
// Exibe botão WhatsApp apenas se o contato optou por compartilhar o telefone.
class _ContextCardSheet extends StatelessWidget {
  final ContextCardEntity card;
  final DateTime lastSeen;

  const _ContextCardSheet({required this.card, required this.lastSeen});

  // "Cargo na Empresa", "Cargo" ou "Empresa" conforme preenchimento
  String get _occupationLine {
    if (card.role.isNotEmpty && card.company.isNotEmpty) {
      return '${card.role} na ${card.company}';
    }
    if (card.role.isNotEmpty) return card.role;
    if (card.company.isNotEmpty) return card.company;
    return '';
  }

  // Tags separadas por vírgula → lista filtrada de strings não-vazias
  List<String> get _tags => card.tags.isEmpty
      ? []
      : card.tags
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

  // Tempo relativo desde o último avistamento BLE
  String _formatLastSeen() {
    final diff = DateTime.now().difference(lastSeen);
    if (diff.inSeconds < 60) return 'Agora mesmo';
    if (diff.inMinutes < 60) return 'Há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Há ${diff.inHours}h';
    return 'Há ${diff.inDays} dia${diff.inDays > 1 ? "s" : ""}';
  }

  @override
  Widget build(BuildContext context) {
    final tags = _tags;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle visual
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withOpacity(0.3), // ignore: deprecated_member_use
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Avatar + nome + ocupação ───────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.accent.withOpacity(0.15), // ignore: deprecated_member_use
                  child: Text(
                    card.initial,
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.displayName,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_occupationLine.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _occupationLine,
                          style: AppTypography.bodyMedium.copyWith(color: AppTheme.accent),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // ── Interesses (chips) ─────────────────────────────────────────
            if (tags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.gap14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: tags.map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gap10, vertical: AppSpacing.xxs),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.10), // ignore: deprecated_member_use
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    border: Border.all(
                      color: AppTheme.accent.withOpacity(0.25), // ignore: deprecated_member_use
                    ),
                  ),
                  child: Text(
                    tag,
                    style: AppTypography.bodySmall.copyWith(color: AppTheme.accent),
                  ),
                )).toList(),
              ),
            ],

            // ── Nota pessoal / bio ─────────────────────────────────────────
            if (card.bio.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.gap14),
              const Divider(color: AppTheme.backgroundElevated),
              const SizedBox(height: AppSpacing.gap10),
              Text(
                card.bio,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],

            // ── Última vez visto ───────────────────────────────────────────
            const SizedBox(height: AppSpacing.gap14),
            Row(
              children: [
                const Icon(
                  Icons.access_time_rounded,
                  size: 14,
                  color: AppTheme.textDisabled,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  _formatLastSeen(),
                  style: AppTypography.bodySmall.copyWith(color: AppTheme.textDisabled),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Botão WhatsApp — só se o contato compartilhou o telefone ───
            if (card.phone.isNotEmpty) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _launchWhatsApp(context, card.phone),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text(AppStrings.bleWhatsApp),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.icon),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],

            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  side: const BorderSide(color: AppTheme.accent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.icon),
                  ),
                ),
                child: const Text(AppStrings.bleClose),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Abre o WhatsApp com o número informado no cartão.
  // Remove formatação e prefixa o DDI do Brasil (55) se necessário.
  Future<void> _launchWhatsApp(BuildContext context, String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final number = digits.startsWith('55') ? digits : '55$digits';
    final url = Uri.parse('https://wa.me/$number');

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.bleWhatsAppError)),
        );
      }
    }
  }
}
