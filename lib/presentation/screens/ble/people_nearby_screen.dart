import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/ble_encounter_entity.dart';
import '../../../domain/entities/context_card_entity.dart';
import '../../../infrastructure/ble/discovered_sopro_user.dart';
import '../../providers/ble_providers.dart';
import '../../providers/database_provider.dart';
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

    // 3. Ativa advertising se o usuário tem perfil E quer ser visível (preferência do Perfil)
    if (ref.read(bleVisibleProvider)) {
      try {
        final card = await ref.read(contextCardRepositoryProvider).getActive();
        if (card != null) {
          final advertised = await service.startAdvertising(card);
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
      _showCardSheet(user.card!);
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
            SizedBox(width: 16),
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
      _showCardSheet(updated.card!);
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
              deviceId:     deviceId,
              displayName:  card.displayName,
              role:         card.role,
              company:      card.company,
              bio:          card.bio,
              tags:         card.tags,
              encounteredAt: DateTime.now(),
            ),
          );
    } catch (e) {
      debugPrint('[PeopleNearby] Falha ao salvar encontro: $e');
    }
  }

  void _showCardSheet(ContextCardEntity card) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.backgroundSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ContextCardSheet(card: card),
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
        backgroundColor: AppTheme.backgroundSurface,
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
            padding: const EdgeInsets.only(right: 8),
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
            SizedBox(height: 16),
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
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.accent,
            ),
          ),
          SizedBox(width: 10),
          Text(
            AppStrings.bleScanning,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isAdvertising
            ? AppTheme.accent.withOpacity(0.15) // ignore: deprecated_member_use
            : Colors.grey.withOpacity(0.15),    // ignore: deprecated_member_use
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAdvertising ? Icons.wifi_tethering : Icons.wifi_tethering_off,
            size: 14,
            color: isAdvertising ? AppTheme.accent : AppTheme.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            isAdvertising
                ? AppStrings.bleAdvertising
                : AppStrings.bleNotAdvertising,
            style: TextStyle(
              fontSize: 12,
              color: isAdvertising ? AppTheme.accent : AppTheme.textSecondary,
            ),
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
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              )
            : const Text(
                AppStrings.bleViewCard,
                style: TextStyle(color: AppTheme.accent, fontSize: 13),
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
        Text(label, style: TextStyle(color: color, fontSize: 10)),
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
          SizedBox(height: 20),
          Text(
            AppStrings.bleNoUsers,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 20),
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

// Bottom sheet com o ContextCard completo de um usuário detectado
class _ContextCardSheet extends StatelessWidget {
  final ContextCardEntity card;
  const _ContextCardSheet({required this.card});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle visual
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withOpacity(0.3), // ignore: deprecated_member_use
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Avatar + nome
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppTheme.accent.withOpacity(0.15), // ignore: deprecated_member_use
                child: Text(
                  card.displayName.isNotEmpty
                      ? card.displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
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
                    // Mostra cargo/empresa se disponíveis; caso contrário, tags
                    if (card.occupationLine.isNotEmpty)
                      Text(
                        card.occupationLine,
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 13,
                        ),
                      )
                    else if (card.tags.isNotEmpty)
                      Text(
                        card.tags,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          if (card.bio.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: AppTheme.backgroundSurface),
            const SizedBox(height: 12),
            Text(
              card.bio,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: const BorderSide(color: AppTheme.accent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(AppStrings.bleClose),
            ),
          ),
        ],
      ),
    );
  }
}
