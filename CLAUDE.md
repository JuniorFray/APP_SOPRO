# Sopro - Contexto do Projeto para Claude Code

## O Que E Este Projeto
Sopro e um app Flutter (Android-first, iOS-ready) de memoria fisica contextual.
Tagline: "O sussurro certo. No lugar certo."

O nome vem do "ponto" teatral: a pessoa que sussurra a fala esquecida ao ator
exatamente quando ele precisa. O app faz o mesmo com informacoes do dia a dia.

## Stack Tecnologico
- Framework: Flutter 3.x (Dart)
- State Management: Riverpod 2.x
- Banco local: Drift + SQLCipher (criptografado)
- Localizacao: GPS nativo via MethodChannel (FusedLocationProviderClient)
- BLE Social: MethodChannel + EventChannel nativos (sem pacote externo)
- ML On-Device: google_mlkit_text_recognition
- Notificacoes: flutter_local_notifications
- Background: flutter_background_service (foreground service ativo, Sprint 9)
- Backend (sync): Supabase (opcional)

## Arquitetura (Clean Architecture simplificada)
- presentation/  -> Telas, widgets, Riverpod providers
- domain/        -> Entidades puras, casos de uso, contratos
- data/          -> Banco, modelos, repositorios, servicos externos
- infrastructure/-> GPS, BLE, ML, notificacoes, background service

## Entidades Principais
- Trigger (Gatilho): intencao vinculada a um local
- Environment (Ambiente): local fisico com geofence
- ContextCard: perfil publico trocado via BLE com outros usuarios
- BLEEncounter: registro de encontro com outro usuario Sopro

## BLE UUID Sopro (FIXO - nao alterar)
SERVICE_UUID: 550e8400-e29b-41d4-a716-446655440000
CONTEXT_CARD_CHAR_UUID: 550e8401-e29b-41d4-a716-446655440000

## ContextCard Schema (schemaVersion = 3)
Campos ContextCards: id (UUID), displayName, role (cargo), company (empresa),
bio (nota pessoal), tags (interesses), createdAt, updatedAt.
Campos BleEncounters: deviceId (PK=MAC BLE), displayName, role, company,
bio, tags, encounteredAt. Upsert por deviceId (uma linha por dispositivo).
BLE JSON payload: {id, n=displayName, r=role, c=company, b=bio, t=tags}

## Regras Invioaveis
1. TODO codigo deve ter comentarios explicativos
2. Nenhum audio ou imagem bruta vai para servidor (tudo on-device)
3. Commits seguem Conventional Commits: feat:, fix:, docs:, refactor:, test:
4. Sem hardcode de strings visiveis - usar lib/core/constants/strings.dart
5. Sem setState em telas complexas - usar Riverpod
6. Privacidade antes de feature

## Sprint Anterior
Sprint: 9 - BLEEncounters DB + Background Service fix - CONCLUIDO
Entregue:
- Tabela BleEncounters no Drift (schemaVersion 2->3): upsert por deviceId
  (MAC BLE), campos displayName/role/company/bio/tags/encounteredAt.
  Migracao automatica em instalacoes existentes (createTable bleEncounters).
- BleEncountersDao + IBleEncounterRepository + BleEncounterRepository:
  watchAll() (stream), save() (upsert), delete(deviceId), deleteAll().
- bleEncounterRepositoryProvider em database_provider.dart.
- encountersStreamProvider (StreamProvider) em encounter_providers.dart.
- EncountersScreen: lista de encontros com swipe-to-delete, botao individual
  de remocao, "Limpar historico" no AppBar. Acessivel pelo icone history
  na AppBar da PeopleNearbyScreen.
- PeopleNearbyScreen: chama _saveEncounter() apos fetchContextCard com sucesso,
  persiste o encontro silenciosamente (nao bloqueia UI).
- Background Service fix: NotificationService.initialize() agora cria dois
  canais Android: 'sopro_triggers' (alta prioridade) e 'sopro_background'
  (baixa prioridade, sem som). O canal 'sopro_background' deve existir
  ANTES de BackgroundServiceManager.start() para evitar o erro
  "Bad notification for startForeground" no Android 8+.
- main.dart: BackgroundServiceManager.configure() ativado antes do runApp().
- AppInitializer: apos initialize(), inicia BackgroundServiceManager.start()
  apenas se onboarding_done=true (evita notificacao persistente no 1o acesso).
- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: 10 - Triggers em Segundo Plano - CONCLUIDO
Entregue:
- NotificationService: showTrigger() com payload (environmentId) para deep-link.
- NotificationService: static _onTap callback + checkLaunchFromNotification().
- FireTriggersUseCase: passa environmentId como payload em cada showTrigger().
- lib/core/navigation/app_router.dart: GlobalKey<NavigatorState> navigatorKey.
- Rota /environment em main.dart; EnvironmentLoaderScreen para deep-link.
- AppInitializer: sequencia _init() com setOnTapCallback -> initialize()
  -> checkLaunchFromNotification -> BackgroundServiceManager.start().
- Funciona com app minimizado (foreground service ativo).
- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: 11 - Configuracoes e UX Polish - CONCLUIDO
Entregue:
- SettingsScreen (lib/presentation/screens/settings/settings_screen.dart):
  toggle BLE visivel/invisivel (bleVisibleProvider), toggle notificacoes
  (notificationsEnabledProvider + SharedPreferences), navegacao para perfil
  e encontros BLE, secao "Sobre" com versao (0.1.0) e URL do repositorio.
- notificationsEnabledProvider (settings_providers.dart): StateProvider<bool>
  persistido em SharedPreferences 'notifications_enabled'.
- FireTriggersUseCase: aceita bool Function() _notificationsEnabled — callback
  avaliado no momento do disparo, respeitando o toggle sem recriar o provider.
- location_providers.dart: passa () => ref.read(notificationsEnabledProvider)
  ao FireTriggersUseCase; importa settings_providers.dart.
- AppInitializer: carrega 'notifications_enabled' de SharedPreferences no _init()
  e restaura notificationsEnabledProvider antes de iniciar o app.
- pushScreen<T>() em app_router.dart: navegacao com slide + fade (280 ms),
  substitui MaterialPageRoute em todas as telas.
- AddEnvironmentScreen: aceita EnvironmentEntity? environment — modo edicao com
  pre-preenchimento de campos e centralizacao do mapa na posicao existente.
- EnvironmentDetailScreen: botao de editar ambiente no AppBar (pushScreen para
  AddEnvironmentScreen com ambiente atual); observa environmentByIdProvider
  (stream) para refletir edicoes sem recarregar; _TriggerTile com botao de
  editar (pencil icon) + HapticFeedback.mediumImpact() ao ativar/desativar.
- _TriggerSheet (renomeado de _AddTriggerSheet): aceita TriggerEntity?
  existingTrigger para modo edicao com pre-preenchimento.
- environmentByIdProvider: atualizado de async* generator para stream.map()
  sobre watchAll() — atualiza automaticamente ao editar ambiente.
- HomeScreen: icone de configuracoes no AppBar; usa pushScreen para todas as
  navegacoes push; importa SettingsScreen.
- EnvironmentCard: usa pushScreen para navegar ao EnvironmentDetailScreen.
- main.dart: rota /settings adicionada (SettingsScreen).
- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: 12 - Logs Supabase + Correcoes pos-teste - CONCLUIDO
Entregue:
PARTE 1 — Sistema de logs no Supabase:
- AppLogger (lib/infrastructure/logging/app_logger.dart): classe estatica,
  device UUID gerado uma vez e salvo em SharedPreferences ('logger_device_id'),
  POST assincrono para Supabase REST (dart:io HttpClient, fire-and-forget).
  Eventos logados: app_start, geofence_enter, geofence_exit, trigger_fired,
  ble_error. Falhas de rede silenciosas — logging nunca impacta a UX.
- supabase/app_logs.sql: schema da tabela (id, device_id, event_type,
  payload jsonb, created_at).
- AppInitializer: chama AppLogger.init() no inicio de _init().
- GeofenceManager: loga geofence_enter e geofence_exit com distancia e accuracy.
- FireTriggersUseCase: loga trigger_fired com environment_id, trigger_id e sound.
- BleService: loga ble_error em scan_error e gatt_error.

PARTE 2 — Correcoes pos-teste:
- GPS 2 s: MainActivity.kt linha 197 mudou 5_000L para 2_000L.
- Raio com accuracy: NativeLocationService.getPositionStream() agora inclui
  accuracy. GeofenceManager usa meters <= radiusMeters + accuracy.clamp(0, 100).
- Nominatim search: AddEnvironmentScreen tem barra de busca flutuante no mapa
  (dart:io HttpClient, User-Agent identificado, resultados em lista clicavel).
- "Encontros BLE" renomeado para "Pessoas que encontrei" em strings.dart e
  SettingsScreen (settingsMyEncounters, encountersTitle).
- GitHub link removido das Configuracoes.
- Som nas notificacoes: notificationSoundProvider + canal 'sopro_triggers_silent'
  (sem som/vibracao). FireTriggersUseCase.showTrigger() passa useSoundChannel.
- Frequencia de notificacoes: notificationCooldownMinutesProvider + _CooldownTile
  com DropdownButton (Sempre / 5 / 15 / 30 / 60 min) nas Configuracoes.
  FireTriggersUseCase rastreia _lastNotifTime para aplicar o cooldown.
- Foto no perfil: image_picker ^1.1.2 adicionado. ProfileScreen com GestureDetector
  no CircleAvatar: pickImage -> copia para getApplicationDocumentsDirectory ->
  path em SharedPreferences 'profile_photo_path'. Foto nao enviada via BLE.
- Icone do app: flutter_launcher_icons ^0.14.4 (dev). Python gerou 512x512 PNG
  com 3 curvas de vento (#E94560) sobre fundo #1A1A2E. dart run flutter_launcher_icons
  gerou os mipmap-* do Android.
- AndroidManifest: READ_MEDIA_IMAGES + READ_EXTERNAL_STORAGE (maxSdkVersion=32).
- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: 13 - Correcoes de Notificacao + Robustez - CONCLUIDO (2026-06-29)

### O que funciona (confirmado em testes)
- Geofencing nativo (GeofencingClient): GeofenceReceiver.onReceive() dispara
  corretamente quando o dispositivo entra no raio do ambiente.
- Foreground Service: BackgroundService permanece ativo com app minimizado.
  Loopback de GPS a cada 2 s funciona (FusedLocationProviderClient).
- GeofenceManager: deteccao de entrada/saida via stream de GPS funciona em
  paralelo ao GeofencingClient (dupla cobertura).
- FireTriggersUseCase: callada corretamente, logs trigger_fired aparecem no
  Supabase confirmando que o codigo de disparo executa.
- BLE Social: scan, advertise e troca de ContextCard funcionam quando visivel.
- Banco de dados: Drift + SQLCipher, migracao automatica ate schemaVersion 3.
- Deep-link de notificacao: toque na notificacao abre EnvironmentDetailScreen.
- Configuracoes: toggles de notificacao, som e cooldown persistidos em prefs.

### O que NAO funciona (bug confirmado)
- NOTIFICACOES NAO APARECEM NA TELA (Motorola G52, Android 12):
  Supabase registra trigger_fired mas a notificacao heads-up nao aparece.
  Hipoteses descartadas: permissao POST_NOTIFICATIONS concedida, canal criado.
  Causa provavel: canal 'sopro_triggers' criado com Importance.high (4) em vez
  de Importance.max (5). OEMs restritivos (Motorola My UX) ignoram importance
  HIGH para apps em segundo plano — exigem MAX para garantir heads-up.

### Correcoes aplicadas neste sprint (2026-06-29)
PARTE 1 — Notificacoes (correcao principal):
- NotificationService: canal 'sopro_triggers' mudou para Importance.max.
  showTrigger() agora usa Priority.max + Importance.max no canal de som.
  Adicionados ticker (forca heads-up em OEMs) e visibility: public (lock screen).
- AndroidManifest: USE_FULL_SCREEN_INTENT adicionado (Android 14+ / API 34+).
- FireTriggersUseCase: log 'trigger_fired' movido para ANTES de showTrigger().
  Novo log 'notification_displayed' apos show() bem-sucedido.
  Novo log 'notification_error' se show() lancar excecao (diagnose silenciosa).
- GeofenceReceiver: canal criado com check null (idempotente), permissao
  verificada via areNotificationsEnabled(), fallback de nome, try/catch +
  logs de debug/error. CHANNEL_ID = 'sopro_triggers' identico ao Dart.

PARTE 2 — Onboarding, Perfil, Revisao Geral:
- OnboardingScreen: _requestNotifications() e _requestBle() agora capturam
  o bool retornado pela permissao. Se negada: exibe Container inline com
  mensagem de impacto (AnimatedSize) e substitui botao primario por
  "Continuar assim mesmo". Botao secundario oculto enquanto aviso visivel.
  _denialMessage limpo ao trocar de passo (onPageChanged).
- ProfileScreen: _pickPhoto() substituido por _showPhotoOptions() que abre
  bottom sheet com opcoes "Tirar foto" (camera) e "Escolher da galeria"
  (gallery). Logica de copia/persistencia extraida para _pickPhotoFrom().
- strings.dart: obContinueAnyway, obNotifDenied, obBleDenied, profilePhotoOptions,
  profilePhotoCamera, profilePhotoGallery, settingsNotifCooldownDesc adicionados.
- settings_screen.dart: string hardcoded 'Intervalo minimo entre notificacoes'
  substituida por AppStrings.settingsNotifCooldownDesc (regra de nao hardcode).
- flutter analyze lib/: No issues found. flutter build apk --release: success.

### Decisoes Tecnicas (historico)
- Dual geofencing: GeofencingClient (nativo, funciona com app morto) +
  GeofenceManager via stream GPS (funciona com foreground service). Mantidos
  os dois — redundancia intencional para maxima confiabilidade.
- Canal de notificacao: decidido NAO usar novo channelId para importance MAX
  porque exigiria migrar instalacoes existentes. Instalacoes novas ou com
  clear data recebem MAX corretamente. Instalacoes existentes: orientar usuario
  a limpar dados do app OU criar canal 'sopro_triggers_v2' se o problema persistir.
- USE_FULL_SCREEN_INTENT: adicionado preventivamente. Nao usado hoje (sem
  fullScreenIntent ativo), mas evita crash silencioso em Android 14+ se
  futuramente precisarmos de notificacao sobre lock screen.
- Supabase logging: fire-and-forget (ignore()), nunca bloqueia UI, falhas
  silenciosas em producao, log em debugPrint apenas em kDebugMode.
- Onboarding permissoes: NAO bloqueamos avanco quando permissao negada — app
  funciona sem BLE (so perde "Pessoas aqui") e sem notificacoes (perde sussurros).
  Exibimos impacto e deixamos o usuario decidir — privacidade antes de feature.

## Sprint Anterior
Sprint: 13 - Debounce, BLE TX Power e WhatsApp - CONCLUIDO (2026-06-30)
Entregue:

1. DEBOUNCE DE NOTIFICACAO (60s por trigger_id):
   - FireTriggersUseCase: _triggerLastFired = Map<String, DateTime> rastreia
     ultimo disparo por triggerId. Bloqueia re-disparo dentro de 60s.
   - Loga 'duplicate_trigger_blocked' no Supabase com seconds_since_last.
   - Resolve race condition onde GPS stream + GeofenceReceiver disparavam
     o mesmo trigger quase simultaneamente.

2. BLE DUPLICATAS REDUZIDAS:
   - BleService._emitDevices(): debounce de 500ms (Timer) agrupa resultados
     em burst antes de emitir para o StreamController.
   - MainActivity.kt: SCAN_MODE_LOW_LATENCY -> SCAN_MODE_BALANCED.
   - _devices ja era Map<String, DiscoveredSoproUser> (dedup por deviceId).

3. POTENCIA BLE AJUSTAVEL:
   - bleTxPowerProvider (StateProvider<int>, default=1=LOW) em settings_providers.
   - _BlePowerTile nas Configuracoes: dropdown com 4 opcoes
     (Minima ~2m=ULTRA_LOW, Baixa ~5m=LOW, Media ~10m=MEDIUM, Alta ~20m+=HIGH).
   - Persistido em SharedPreferences 'ble_tx_power'; restaurado no AppInitializer.
   - BleService.startAdvertising() recebe txPower e passa via MethodChannel.
   - MainActivity.startBleAdvertising(cardJson, txPower, result): usa
     txPower.coerceIn(0,3) no AdvertiseSettings.Builder.

4. WHATSAPP NO PERFIL (schemaVersion 3->4):
   - Migracao: addColumn(contextCards, phone) + addColumn(bleEncounters, phone).
   - phone em ContextCardEntity, BleEncounterEntity (default='').
   - Payload BLE ampliado: chave 'p' para phone.
   - ProfileScreen: campo "WhatsApp / Telefone" com FilteringTextInputFormatter.
     digitsOnly, maxLength=13, secao "Contato".
   - _ContextCardSheet: ElevatedButton verde (Color(0xFF25D366)) "Conversar no
     WhatsApp" se card.phone.isNotEmpty. Abre https://wa.me/55<digitos> via
     url_launcher (modo externalApplication). Prefixa 55 se nao comeca com 55.
   - AndroidManifest: <queries> com intent VIEW + scheme https (Android 11+).
   - pubspec.yaml: url_launcher ^6.3.0 adicionado.
   - dart run build_runner build: Drift *.g.dart regenerados.
   - flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Atual
Sprint: 14 - GATT Retry + Linguagem Simples - CONCLUIDO (2026-06-30)
Entregue:

1. CORRECAO GATT BLE (MainActivity.kt + BleService.dart):
   - closeZombieGatts(deviceId): fecha todos os GATTs ativos para o dispositivo
     antes de nova tentativa de conexao, eliminando conexoes zumbi (status=133).
   - connectAndReadCard: delay de 600ms antes de chamar device.connectGatt()
     (postDelayed no mainHandler). Android precisa de tempo entre discovery e connect.
     Timeout (10s) postado DENTRO do delay, iniciando somente apos connectGatt.
   - BleService.fetchContextCard: retry automatico — ate 3 tentativas totais.
     Delays entre tentativas: 600ms (retry 1) e 1200ms (retry 2).
     Loga 'ble_retry_success' no Supabase com attempt number se retry resolver.
     Loga 'ble_error' (gatt_error) somente na falha final, evitando ruido de log
     em falhas transitorias resolvidas pelo retry.

2. LINGUAGEM SIMPLES (strings.dart):
   - obLocationBody: "geofences locais" → "seus lugares cadastrados";
     "Seu GPS é usado apenas para" → "Seu GPS fica no dispositivo —".
   - settingsBleSection: "Bluetooth Social" → "Pessoas proximas".
   - settingsBleVisibleDesc: removido "via Bluetooth" (suficiente sem o tecnicismo).
   - settingsBleTxPower: "Alcance BLE" → "Alcance de deteccao".
   - obBleBody: removido "via Bluetooth" e "cartoes de contexto" → "cartoes".
   - profileVisibleDesc: removido "via Bluetooth".
   - Criterio: "BLE"/"Bluetooth Low Energy" e "geofencing" removidos do texto
     visivel. "Bluetooth" mantido apenas em labels de permissao (onde o SO
     tambem usa o termo) e textos de erro de hardware.
   - flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Proximo Sprint
Sprint: 15 - Possivelmente: tema claro/escuro, exportacao de dados,
estatisticas de uso, widget Android de ambiente na home,
icone de categoria para ambientes.

## Repositorio
https://github.com/JuniorFray/APP_SOPRO.git
