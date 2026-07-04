import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/navigation/app_router.dart';
import '../../infrastructure/background/background_service_manager.dart';
import '../../infrastructure/logging/app_logger.dart';
import '../../infrastructure/notifications/notification_service.dart';
import '../providers/database_provider.dart';
import '../providers/location_providers.dart';
import '../providers/settings_providers.dart';
import '../providers/voice_providers.dart';

// Widget que inicializa serviços assíncronos dentro do ProviderScope.
// Deve ser o primeiro widget construído depois do ProviderScope para que o
// NotificationService seja configurado antes da primeira tela ser exibida.
//
// Sequência de _init():
//   1. Inicializa o AppLogger (gera/recupera o device UUID).
//   2. Registra o callback de toque em notificação (antes de initialize()).
//   3. Inicializa o plugin de notificações e cria os canais Android.
//   4. Verifica cold start (app aberto por toque numa notificação).
//   5. Detecta SharedPreferences obsoletas (OEM Auto Backup):
//      Se onboarding_done=true mas banco vazio → reseta flags e encerra early.
//   6. Restaura as preferências do usuário das Configurações.
//   7. Inicia o foreground service se o onboarding já foi concluído.
//   8. Loga o evento app_start.
class AppInitializer extends ConsumerStatefulWidget {
  final Widget child;

  const AppInitializer({super.key, required this.child});

  @override
  ConsumerState<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends ConsumerState<AppInitializer> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 1. Inicializa o logger — gera o device ID se for a primeira execução
    await AppLogger.init();

    // 2. Registra o callback de toque ANTES de initialize() para que notificações
    //    pendentes (ex: do último foreground service) sejam capturadas.
    NotificationService.setOnTapCallback(_openEnvironment);

    // 3. Cria os canais Android e registra os handlers do plugin.
    final notifications = ref.read(notificationServiceProvider);
    await notifications.initialize();

    // 4. Verifica cold start: app aberto pelo toque numa notificação.
    final coldPayload = await notifications.checkLaunchFromNotification();
    if (coldPayload != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openEnvironment(coldPayload);
      });
    }

    final prefs = await SharedPreferences.getInstance();

    // Persiste o caminho real do banco para uso pelo FloatingVoiceService (Kotlin).
    // drift_flutter usa getApplicationDocumentsDirectory() — sem esse valor o Kotlin
    // teria que adivinhar o caminho entre múltiplos candidatos.
    final dbFolder = await getApplicationDocumentsDirectory();
    final dbPath = '${dbFolder.path}/sopro.db';
    await prefs.setString('sopro_db_path', dbPath);

    // Força o Drift a criar o arquivo sopro.db em disco agora.
    // Sem isso o arquivo não existe até a primeira query real,
    // e o FloatingVoiceService encontraria db_file_not_found.
    try {
      final db = ref.read(databaseProvider);
      await db.select(db.environments).get();
    } catch (_) {}

    // 5. Detecção de SharedPreferences obsoletas (OEM Auto Backup).
    //
    //    Motorola G52 e outros OEMs com Android Auto Backup podem restaurar
    //    SharedPreferences após reinstalação SEM restaurar o banco de dados.
    //    Isso faz com que 'onboarding_done=true' e as permissões não sejam
    //    re-solicitadas, mesmo que o banco esteja completamente vazio.
    //
    //    Diagnóstico: onboarding_done=true + banco sem Environments E sem perfil.
    //    Ação: remove todas as prefs que controlam o estado de primeiro acesso
    //    e restaura os providers para os valores padrão antes de carregá-los
    //    das prefs (evita duplo-set de estado).
    if (prefs.getBool('onboarding_done') ?? false) {
      final envs = await ref.read(environmentRepositoryProvider).getAll();
      final card = await ref.read(contextCardRepositoryProvider).getActive();

      if (envs.isEmpty && card == null) {
        // Banco vazio mas prefs dizem que onboarding foi concluído:
        // Remove as prefs que podem estar em estado inconsistente.
        await Future.wait([
          prefs.remove('onboarding_done'),
          prefs.remove('notifications_enabled'),
          prefs.remove('notification_sound_enabled'),
          prefs.remove('notification_cooldown_minutes'),
        ]);

        // Providers já têm os defaults corretos na inicialização; garantimos
        // explicitamente que não sofreram alteração antes deste reset.
        ref.read(notificationsEnabledProvider.notifier).state = true;
        ref.read(notificationSoundProvider.notifier).state = true;
        ref.read(notificationCooldownMinutesProvider.notifier).state = 0;

        AppLogger.log('stale_prefs_reset', {
          'reason': 'onboarding_done=true but database is empty',
        });
        // Não continua o _init() — HomeScreen detectará onboarding_done=false
        // e redirecionará para o OnboardingScreen normalmente.
        AppLogger.log('app_start');
        return;
      }
    }

    // 6. Restaura as preferências salvas pelo usuário nas Configurações.
    //    Os defaults já estão nos providers; só atualiza quando diferem.

    // Persiste a Gemini API key para o FloatingVoiceService (Kotlin sem Flutter Engine).
    // A chave é uma publishable key — não é segredo de servidor.
    final geminiKey = AppConstants.geminiApiKey;
    if (geminiKey.isNotEmpty) await prefs.setString('gemini_api_key', geminiKey);

    final notifEnabled = prefs.getBool('notifications_enabled') ?? true;
    if (!notifEnabled) {
      ref.read(notificationsEnabledProvider.notifier).state = false;
    }

    final soundEnabled = prefs.getBool('notification_sound_enabled') ?? true;
    if (!soundEnabled) {
      ref.read(notificationSoundProvider.notifier).state = false;
    }

    final cooldownMinutes = prefs.getInt('notification_cooldown_minutes') ?? 0;
    if (cooldownMinutes != 0) {
      ref.read(notificationCooldownMinutesProvider.notifier).state =
          cooldownMinutes;
    }

    final txPower = prefs.getInt('ble_tx_power') ?? 1;
    if (txPower != 1) {
      ref.read(bleTxPowerProvider.notifier).state = txPower;
    }

    final shareWhatsApp = prefs.getBool('share_whatsapp') ?? true;
    if (!shareWhatsApp) {
      ref.read(shareWhatsAppProvider.notifier).state = false;
    }

    // Restaura preferências de voz (Sprint V2-Voz)
    final voiceAudio = prefs.getBool('voice_audio_response') ?? true;
    if (!voiceAudio) {
      ref.read(voiceAudioResponseProvider.notifier).state = false;
    }

    final voiceText = prefs.getBool('voice_text_response') ?? true;
    if (!voiceText) {
      ref.read(voiceTextResponseProvider.notifier).state = false;
    }

    final voiceRate = prefs.getDouble('voice_speech_rate') ?? 0.5;
    if (voiceRate != 0.5) {
      ref.read(voiceSpeechRateProvider.notifier).state = voiceRate;
    }

    // 7. Inicia o foreground service apenas se o onboarding já foi concluído.
    //    Evita exibir "Sopro ativo" antes de o usuário configurar o app.
    if (prefs.getBool('onboarding_done') ?? false) {
      await BackgroundServiceManager.start();
    }

    // Restaura o botão flutuante de voz se estava ativo na sessão anterior.
    // Verifica se a permissão SYSTEM_ALERT_WINDOW ainda é válida antes de iniciar.
    const overlayChannel = MethodChannel('com.sopro.sopro/overlay');
    final floatingEnabled = prefs.getBool('floating_voice_enabled') ?? false;
    if (floatingEnabled) {
      try {
        final hasPerm = await overlayChannel.invokeMethod<bool>(
              'hasOverlayPermission') ??
            false;
        if (hasPerm) {
          ref.read(floatingVoiceEnabledProvider.notifier).state = true;
          await overlayChannel.invokeMethod<void>('startFloatingVoiceService');
        } else {
          // Permissão foi revogada → desativa nas prefs sem atualizar o toggle
          await prefs.setBool('floating_voice_enabled', false);
        }
      } catch (_) {
        // Canal ainda não disponível no startup — ignorar
      }
    }

    // 8. Loga a inicialização do app após tudo estar configurado
    AppLogger.log('app_start');
  }

  // Navega para a tela do ambiente identificado por [environmentId].
  // Usa o navigatorKey global para navegar de fora da árvore de widgets.
  void _openEnvironment(String environmentId) {
    navigatorKey.currentState?.pushNamed(
      '/environment',
      arguments: environmentId,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
