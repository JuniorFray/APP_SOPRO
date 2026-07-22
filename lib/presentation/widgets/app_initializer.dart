import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/navigation/app_router.dart';
import '../../infrastructure/background/background_service_manager.dart';
import '../../infrastructure/overlay/floating_voice_service_manager.dart';
import '../../infrastructure/logging/app_logger.dart';
import '../../infrastructure/logging/core/logger.dart';
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
    } catch (e, st) {
      Logger.debug('db_warmup_failed', exception: e, stackTrace: st, feature: 'init', action: 'db_warmup');
    }

    // 5. Detecção de SharedPreferences obsoletas (OEM Auto Backup).
    //
    //    Motorola G52 e outros OEMs com Android Auto Backup podem restaurar
    //    O Android Auto Backup pode restaurar SharedPreferences sem restaurar
    //    o banco de dados local, deixando 'onboarding_done=true' mesmo numa
    //    instalação virgem.
    //
    //    Entretanto, banco vazio NÃO é mais evidência suficiente de
    //    inconsistência: o usuário pode ter apagado todos os ambientes, apagado
    //    seu perfil ou acabado de concluir o onboarding sem criar nada ainda.
    //
    //    A ausência de 'sopro_first_use_date' é usada como evidência de que
    //    aquela instalação nunca concluiu um onboarding válido neste dispositivo.
    //    Essa chave é gravada no momento exato em que o onboarding é concluído
    //    e nunca é removida por fluxos normais do aplicativo.
    //
    //    Reset ocorre SOMENTE quando TODAS as condições são verdadeiras:
    //      • onboarding_done == true
    //      • banco sem Environments
    //      • banco sem perfil ativo
    //      • sopro_first_use_date ausente (nunca houve onboarding válido aqui)
    //    Isso evita falsos positivos e protege usuários reais.
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    final firstUseDate = prefs.getString('sopro_first_use_date');

    if (onboardingDone) {
      final envs = await ref.read(environmentRepositoryProvider).getAll();
      final card = await ref.read(contextCardRepositoryProvider).getActive();

      if (onboardingDone && envs.isEmpty && card == null && firstUseDate == null) {
        // Prefs restauradas pelo Auto Backup sem banco correspondente:
        // Remove as prefs que controlam o estado de primeiro acesso.
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

        Logger.warn('stale_prefs_reset', payload: {
          'reason': 'onboarding_done=true but database is empty and no first_use_date',
        }, feature: 'init', action: 'stale_prefs_reset');
        // Não continua o _init() — HomeScreen detectará onboarding_done=false
        // e redirecionará para o OnboardingScreen normalmente.
        Logger.info('app_start', feature: 'init', action: 'startup');
        return;
      }
    }

    // 6. Restaura as preferências salvas pelo usuário nas Configurações.
    //    Os defaults já estão nos providers; só atualiza quando diferem.

    // Persiste a Gemini API key para o FloatingVoiceService (Kotlin sem Flutter Engine).
    // A chave é uma publishable key — não é segredo de servidor.
    final geminiKey = AppConstants.geminiApiKey;
    if (geminiKey.isNotEmpty) await prefs.setString('gemini_api_key', geminiKey);

    // Persiste a chave OpenWeatherMap para o WeatherNotificationReceiver (Kotlin
    // sem Flutter Engine) — nativo lê flutter.openweather_api_key.
    final owKey = AppConstants.openWeatherKey;
    if (owKey.isNotEmpty) await prefs.setString('openweather_api_key', owKey);

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
    // FloatingVoiceServiceManager valida overlay e RECORD_AUDIO antes de iniciar.
    try {
      final String? failure = await FloatingVoiceServiceManager.tryStart();
      if (failure == null) {
        ref.read(floatingVoiceEnabledProvider.notifier).state = true;
      } else if (failure != 'floating_voice_disabled') {
        // Pré-requisito perdido (overlay revogada, mic negado) — desativa nas prefs
        await prefs.setBool('floating_voice_enabled', false);
      }
    } catch (e, st) {
      Logger.debug('overlay_start_failed', exception: e, stackTrace: st,
          feature: 'init', action: 'overlay_start');
    }

    // 8. Loga a inicialização do app após tudo estar configurado
    Logger.info('app_start', feature: 'init', action: 'startup');
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
