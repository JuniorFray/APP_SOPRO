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

## Sprint Anterior
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

## Sprint Anterior
Sprint: 15 - Cartao BLE Completo + WhatsApp Opcional - CONCLUIDO (2026-06-30)
Entregue:

1. CARTAO BLE COMPLETO (_ContextCardSheet em people_nearby_screen.dart):
   - Todos os campos do ContextCard exibidos condicionalmente (omite se vazio):
     Avatar (inicial colorida), Nome, "Cargo na Empresa" (formato legivel),
     Interesses como chips (tags split por virgula, filtrados), Nota pessoal/bio,
     "Ultima vez visto" relativo (Agora mesmo / Ha X min / Ha Xh / Ha X dias),
     botao WhatsApp (condicional, apenas se phone presente no payload).
   - isScrollControlled: true + SingleChildScrollView: sheet rolavel para
     perfis com muito conteudo.
   - lastSeen (DateTime de DiscoveredSoproUser) propagado de _onUserTapped
     via _showCardSheet ate _ContextCardSheet para calculo de tempo relativo.

2. WHATSAPP OPCIONAL NO PERFIL:
   - shareWhatsAppProvider (StateProvider<bool>, default=true) em settings_providers.dart.
   - Toggle "Compartilhar WhatsApp" na secao Privacidade do ProfileScreen
     (abaixo do toggle "Visivel para outros"). Persistido em SharedPreferences
     'share_whatsapp'; restaurado no AppInitializer.startup.
   - BleService.startAdvertising() aceita sharePhone:bool (default=true).
     Omite chave 'p' do payload JSON via collection-if quando false —
     payload continua compacto sem foto (foto so local, nunca via BLE).
   - PeopleNearbyScreen._startBle() le shareWhatsAppProvider e passa sharePhone
     ao startAdvertising(). O receiver so ve o telefone se o emissor optou.
   - Helper text do campo phone no ProfileScreen muda dinamicamente:
     "Sera incluido no seu cartao" (verde) ou "Salvo, mas nao compartilhado" (cinza).
   - strings.dart: profileShareWhatsApp, profileShareWhatsAppDesc,
     profilePhoneHelperOn, profilePhoneHelperOff adicionados.
   - flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: 16 - Deduplicacao BLE + Auditoria de Seguranca + Documentacao V1 - CONCLUIDO (2026-06-30)
Entregue:

PARTE 1 — Robustez BLE em ambientes de alto fluxo:
- DEDUPLICACAO POR IDENTIDADE ESTAVEL: _devices indexado por card.id (UUID
  gerado pelo dono do perfil) apos a primeira leitura GATT. Antes disso usa o
  MAC como chave temporaria. _macToStableId mapeia MAC → ID estavel para que
  redeteccoes (mesmo ou novo MAC) atualizem a entrada correta.
  _promoteToCardId() reindexia de MAC → card.id tratando 3 casos:
  refresh (card.id ja e chave), MAC rotation (mesmo card.id, novo MAC → mescla),
  primeira leitura (promove de MAC para card.id).
- EXPIRACAO TTL 10 s: Timer.periodic a cada 3 s. Entradas nao vistas ha
  mais de 10 s sao removidas automaticamente. Limpeza total de _macToStableId
  e _fetchingCards para os IDs expirados.
- REFRESH DE CARD A CADA 30 s: _maybeRefreshCard() agenda re-leitura GATT
  (via fetchContextCard) se fetchedAt < agora - 30s. _fetchingCards evita
  fetches paralelos para o mesmo dispositivo. Reflete mudancas de privacidade
  (ex: outro usuario desativa compartilhamento de WhatsApp) em tempo real.
- DiscoveredSoproUser: novo campo fetchedAt (DateTime?) registra quando o card
  foi carregado via GATT, usado para controle do refresh.
- BleService.dispose(): cancela _expiryTimer alem de stopScan/stopAdvertising.

PARTE 2 — Auditoria de seguranca:
- PAYLOAD BLE SANITIZADO: _sanitize() em todos os campos do ContextCard
  (trim + truncate no limite seguro: id=36, displayName/role/company=60,
  bio=200, tags=100, phone=15). JSON invalido descartado silenciosamente.
  Validacao de tipo: raw is! Map → retorna user sem modificar o estado.
- CHAVE SUPABASE DOCUMENTADA: comentario em app_logger.dart explica por que
  sb_publishable_ e seguro em codigo fonte (analogia firebase_options.dart)
  e qual politica RLS deve estar ativa no painel Supabase (INSERT-only).
- PRIVACIDADE DO TELEFONE VERIFICADA: chave 'p' omitida do payload BLE via
  collection-if quando sharePhone=false; numero salvo so localmente; nao
  aparece em nenhum log do Supabase; strips de digitos antes de abrir WhatsApp.
- ANDROID MANIFEST AUDITADO: todas as permissoes tem uso documentado;
  maxSdkVersion nos fallbacks legacy (BLUETOOTH/BLUETOOTH_ADMIN ate API 30,
  READ_EXTERNAL_STORAGE ate API 32); nenhuma permissao desnecessaria.
- BANCO DE DADOS: SQLCipher adiado para V2 (dados em /data/data/com.sopro.sopro/
  — armazenamento privado do app, inacessivel sem root). Documentado como
  limitacao conhecida da V1 na secao STATUS V1.
- flutter analyze lib/: No issues found. flutter build apk --release --split-per-abi: success.

## Sprint Anterior
Sprint: 17 - Fechamento V1 - CONCLUIDO (2026-06-30)
Entregue:

TAREFA 1 — Regressao critica (GeofenceReceiver nao mostrava notificacao com app morto):
- Causa raiz: GeofenceReceiver.kt criava canal com IMPORTANCE_HIGH quando o app nunca foi
  aberto (NotificationService ainda nao rodou). Motorola My UX silencia IMPORTANCE_HIGH de
  apps em background — mesma causa do bug do Sprint 13, mas no receiver nativo.
- Correcao: IMPORTANCE_MAX + PRIORITY_MAX + ticker + VISIBILITY_PUBLIC no GeofenceReceiver.kt.
- Diagnostico: AppLogger.log('native_geofence_registered', {count, total}) em
  GeofenceManager.start() confirma quantos geofences foram registrados com sucesso no Supabase.

TAREFA 2 — Sync de perfil BLE em tempo real:
- _cardRefreshAfter reduzido de 30s para 10s em BleService.
  Qualquer campo do ContextCard reflete para outros usuarios em ate 10s de re-deteccao BLE.

TAREFA 3 — Documentacao V1 finalizada:
- CLAUDE.md: Sprint 17 adicionado, STATUS V1 renomeado para V1 FINALIZADA, historico de
  17 sprints, todos os bugs de campo, auditoria de seguranca, stack tecnico, metricas de
  teste, arquitetura final e secao V2 Proximos Passos.
- flutter analyze lib/: No issues found. flutter build apk --release --split-per-abi: success.

## Sprint Anterior
Sprint: V2-Voz - Interacao por Voz - CONCLUIDO (2026-07-01)
Entregue:

REGRAS V2 APLICADAS:
- Todo codigo comentado sem excecao (regra V2).
- CLAUDE.md atualizado ao final do sprint (regra V2).
- Commit e push ao final do sprint (regra V2).
- Titulo do trigger NAO e obrigatorio: removido validator do campo titulo em
  _TriggerSheet (environment_detail_screen.dart). O usuario pode criar gatilho
  apenas com conteudo.

1. PACOTES DE VOZ:
   - speech_to_text: ^6.6.2 adicionado ao pubspec.yaml.
   - flutter_tts: ^3.6.3 adicionado (v3.x compativel com Kotlin 1.8.22 e compileSdk=35).
   - RECORD_AUDIO adicionado ao AndroidManifest.xml.

2. VOICE SERVICE (lib/infrastructure/voice/voice_service.dart):
   - VoiceIntent enum: createTrigger, openEnvironment, resolveTrigger, listTriggers, fallback.
   - VoiceResult: intent + transcript + triggerAction + environmentName.
   - VoiceService: STT via SpeechToText (localeId='pt_BR', SpeechListenOptions),
     TTS via FlutterTts (setLanguage('pt-BR')), processamento por regex on-device.
   - Regex de intencoes (pt-BR):
     createTrigger:   "lembra de X quando eu chegar em Y"
     openEnvironment: "salva esse lugar como X" / "cria um ambiente chamado X"
     resolveTrigger:  "resolvi X" / "pode apagar X"
     listTriggers:    "o que tenho pendente em X?"
     fallback:        texto livre

3. PROVIDERS DE VOZ (lib/presentation/providers/voice_providers.dart):
   - voiceServiceProvider (Provider<VoiceService>): singleton com onDispose.
   - voiceAudioResponseProvider (StateProvider<bool>, default=true).
   - voiceTextResponseProvider (StateProvider<bool>, default=true).
   - voiceSpeechRateProvider (StateProvider<double>, default=0.5).
   - Persistencia: SharedPreferences 'voice_audio_response', 'voice_text_response',
     'voice_speech_rate'. Restaurados em AppInitializer._init().

4. FAB DE VOZ NA HOME (home_screen.dart):
   - FloatingActionButton.small (mic_outlined) acima do FAB principal.
   - heroTag='voice_fab' para evitar conflito de hero animation.
   - Abre _VoiceBottomSheet via showModalBottomSheet.
   - _VoiceBottomSheet: escuta, anima, mostra resultado, executa acao confirmada.
   - _SoundWave: 5 barras com AnimationController senoidal + modulacao por soundLevel.
   - _handleVoiceResult(): navega para tela correta conforme VoiceIntent:
     createTrigger → EnvironmentDetailScreen (fuzzy match por nome) ou AddEnvironmentScreen.
     openEnvironment → AddEnvironmentScreen com initialName pre-preenchido.
     resolveTrigger → busca trigger em todos os ambientes e desativa o primeiro match.
     listTriggers → EnvironmentDetailScreen (fuzzy match por nome).
     fallback → SnackBar sugerindo selecionar um ambiente.

5. BOTOES DE MICROFONE NOS FORMULARIOS:
   - AddEnvironmentScreen: suffixIcon com mic_outlined no campo "Nome do local".
     _listenForName() ouve 7s e preenche _nameController.
     initialName: String? adicionado ao constructor para pre-preenchimento por voz.
   - environment_detail_screen.dart (_TriggerSheet): suffixIcon mic em titulo E conteudo.
     _listenForField() generico ouve 8s e preenche o controller do campo tocado.
     Spinner de loading enquanto _listeningTitle ou _listeningContent == true.

6. CONFIGURACOES DE VOZ (settings_screen.dart):
   - Nova secao "Interacao por voz" com:
     Toggle voiceAudioResponseProvider (resposta em audio).
     Toggle voiceTextResponseProvider (resposta em texto).
     _VoiceRateTile: dropdown Lenta(0.3)/Normal(0.5)/Rapida(0.7) para velocidade TTS.
   - Persistencia via SharedPreferences; restaurados em AppInitializer.

7. STRINGS:
   - Adicionado em lib/core/constants/strings.dart:
     voiceSection, voiceAudioResponse/Desc, voiceTextResponse/Desc, voiceSpeechRate,
     voiceRateSlow/Normal/Fast, voiceListeningTitle/Hint, voiceResultTitle,
     voiceConfirm, voiceRetry, voiceClose, voiceNotAvailable, voicePermissionDenied,
     voiceExamples, voiceIntentCreate/Env/Resolve/List/Fallback, voiceMicTooltip, voiceFillHint.

8. CORRECAO: flutter_tts v4.2.5 requer Kotlin 2.2 e compileSdk=36 (incompativel).
   Solucao: downgrade para flutter_tts: ^3.6.3 (Kotlin 1.8 compativel, API identica).

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: V2-Voz-Fix - Locale pt-BR + Gemini API - CONCLUIDO (2026-07-01)
Entregue:

1. LOCALE PT-BR DINAMICO (voice_service.dart):
   - _ptBrLocaleId detectado em runtime via _findPtBrLocale() (locales(), fallback 'pt*').
   - startListening() usa localeId: _ptBrLocaleId (null = padrao do sistema).

2. GEMINI API PARA INTENCAO DE VOZ:
   - app_constants.dart: geminiApiKey (dotenv), geminiEndpoint, geminiSystemPrompt.
   - resolveIntent(): async, tenta Gemini, fallback regex.
   - _processIntentWithGemini(): POST HttpClient, timeout 8s, temperatura 0, strip markdown.
   - voice_debug logado no Supabase com transcript, has_key, gemini_http, gemini_raw,
     gemini_error, final_intent.
   - Chave Gemini via flutter_dotenv (.env no .gitignore, .env.example no repo).

3. _processing spinner no bottom sheet; campo de transcript no spinner state.

- flutter analyze lib/: No issues found.

## Sprint Anterior
Sprint: V2-Gemini-Robustez - Modelo correto + Ingles STT + Transcript editavel - CONCLUIDO (2026-07-01)
Entregue:

1. MODELO GEMINI CORRETO (app_constants.dart):
   - gemini-2.0-flash → gemini-1.5-flash (2.0-flash retornava 404 neste tier).

2. HEURISTICA STT EM INGLES (voice_service.dart):
   - _mightBeEnglish(): detecta se transcript foi capturado em ingles pelo STT.
     Criterios: sem acentos (áéíóú etc.) E sem palavras funcionais portuguesas
     (de, em, no, lembra, criar, casa, trabalho...). Conservador — false positives
     aceitaveis (pior caso: envia contexto extra desnecessariamente ao Gemini).
   - _englishHint: nota injetada no texto do usuario ao Gemini quando ingles detectado.
     Exemplos: "create" → "criar", "environment" → "ambiente", "creative cousin" → "criar ambiente casa".
   - _processIntentWithGemini(transcript, {maybeEnglish}): aceita flag e injeta hint.
   - resolveIntent(): detecta _mightBeEnglish(), passa flag, loga 'maybe_english' no Supabase.

3. TRANSCRIPT EDITAVEL NO BOTTOM SHEET (home_screen.dart):
   - _transcriptController: TextEditingController no estado de resultado.
   - Campo TextField editavel com label "O que voce disse" e botao refresh (re-analisar).
   - _reanalyze(): processa o texto editado pelo usuario, permite corrigir ingles errado.
   - _onFinal(): popula _transcriptController com o texto do STT.
   - Transcript removido do interior do card de intencao (agora no TextField acima).
   - textOn (voiceTextResponseProvider) removido do build() — transcript sempre visivel.

4. STRINGS:
   - voiceTranscriptLabel = 'O que voce disse'.
   - voiceReanalyze = 'Re-analisar'.

- flutter analyze lib/: No issues found.

## Sprint Anterior
Sprint: V2-VoicePro - Botao WhatsApp + Zero Confirmacao + Busca Case-Insensitive - CONCLUIDO (2026-07-01)
Entregue:

1. BUG FIX — BUSCA DE AMBIENTE CASE-INSENSITIVE E PARCIAL:
   - _matchEnv() em _VoiceFabState: exact match primeiro (case-insensitive),
     depois CONTAINS match ("casa" encontra "Minha Casa" e vice-versa).
   - Resolve o bug onde Gemini retornava "casa" (minusculo) e ambiente
     estava salvo como "Casa" → gatilho nao era salvo.
   - Log 'trigger_voice_failed' no Supabase com env_name_from_gemini,
     trigger_action e transcript quando ambiente nao for encontrado.
   - Snackbar verde "Gatilho criado em [env] ✓" apos salvar com sucesso.

2. FLUXO ZERO CONFIRMACAO (hands-free total):
   - _executeResult() despacha diretamente sem esperar confirmacao manual.
   - criar_trigger + env encontrado → salva TriggerEntity no banco → snackbar → _setSuccess().
   - criar_trigger + env nao encontrado → _EnvPickerSheet (lista de ambientes, 1 toque).
   - criar_ambiente → getCurrentPosition() via NativeLocationService → abre
     AddEnvironmentScreen com initialName E initialPosition pre-definidos.
   - resolver_trigger → setActive(false) diretamente → snackbar → _setSuccess().
   - listar_triggers + env encontrado → _TriggerListSheet inline no sheet.
   - listar_triggers + env nao encontrado → _EnvPickerSheet → _TriggerListSheet.
   - nao_entendido → _FallbackSheet com campo editavel + botao Re-analisar.

3. BOTAO DE GRAVACAO ESTILO WHATSAPP (_VoiceFab):
   - Substituiu FloatingActionButton.small + _VoiceBottomSheet (removidos).
   - Tamanho: 64x64dp, circulo, elevation via boxShadow.
   - Cor idle: AppTheme.accent (#E94560); gravando: #E53935 (vermelho).
   - Ícone: Icons.mic_rounded 28dp; sucesso: Icons.check_rounded verde 32dp.
   - SEGURAR (onPointerDown): inicia gravacao.
   - SOLTAR (onPointerUp): processa ou cancela conforme zona.
   - ARRASTAR PARA CIMA > 60dp: ativa zona de cancelamento.
     Lixeira aparece acima (Container 44dp, vermelho quando ativa).
     Botao fica cinza na zona de cancelamento.
     Soltar nessa zona → cancela sem processar.
   - Animacao de pulso: AnimationController 700ms, escala 1.0↔1.12 (repeat reverse).
   - Auto-stop: 30 s de gravacao maxima.
   - Contador de segundos abaixo do botao durante gravacao.
   - _setSuccess(): estado success (verde) por 1 s → volta a idle.
   - _FabState enum: idle/recording/processing/success/error.

4. SHEETS DE CONTINUACAO:
   - _EnvPickerSheet (ConsumerWidget): lista de ambientes com titulo/subtitulo.
     Titulo dinamico ("Em qual ambiente?" ou "Pendencias de qual ambiente?").
     Subtitulo = acao reconhecida para contexto visual.
     Tap → Navigator.pop + onEnvSelected callback.
   - _TriggerListSheet (ConsumerWidget + FutureBuilder): lista apenas triggers ativos.
     getActiveByEnvironment() do repositorio.
     Exibe titulo + conteudo com separadores visuais.
   - _FallbackSheet (ConsumerStatefulWidget): TextField editavel + botao Re-analisar.
     Chama resolveIntentFromText() e passa resultado de volta via onResult callback.
     autofocus: true para o teclado abrir automaticamente.

5. PREPARACAO V3 — OVERLAY:
   - AndroidManifest: SYSTEM_ALERT_WINDOW adicionado (necessaria para overlay futuro).
   - lib/infrastructure/voice/voice_overlay_service.dart: stub com comentario
     detalhado explicando requisitos V3 (WindowManager, MethodChannel dedicado).
   - onboarding_screen.dart: passo 5 adicionado (icone mic_external_on_outlined,
     cor accent, titulo/corpo de AppStrings.obOverlayTitle/Body).
     _requestBle() agora chama _nextPage() em vez de _goHome() (ha um passo a mais).
     _primaryLabel: case 4 = obOverlayBtn. _primaryAction: case 4 = _goHome.
   - strings.dart: obOverlayTitle, obOverlayBody, obOverlayBtn adicionados.

6. ADD_ENVIRONMENT_SCREEN — initialPosition:
   - Parametro LatLng? initialPosition adicionado ao constructor.
   - initState(): se initialPosition != null, define _selectedPoint e
     centraliza o mapa com move(initialPosition!, 15.0) apos primeiro frame.
   - Permite que o comando de voz "criar_ambiente" posicione o pin GPS
     automaticamente sem o usuario clicar na bolinha de localizacao.

7. STRINGS NOVAS (strings.dart):
   - voiceTriggerSavedIn, voiceTriggerDeactivated, voiceTriggerNotFound.
   - voiceEnvPickerTitle, voiceEnvPickerAction.
   - voiceTriggerListTitle, voiceNoTriggersPending.
   - obOverlayTitle, obOverlayBody, obOverlayBtn.

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: V2-GeminiAudio - Gravacao de audio + Gemini Audio API - CONCLUIDO (2026-07-01)
Entregue:

### Mudanca de estrategia
STT on-device (speech_to_text) substituido por gravacao de audio + Gemini Audio API.
Uma unica chamada faz STT + NLU simultaneamente. Resolve o problema de locale pt-BR
ignorado no Motorola (engine STT nativo capturava em ingles independente da config).

1. PACOTES (pubspec.yaml):
   - REMOVIDO: speech_to_text ^6.6.2.
   - ADICIONADO: record ^5.1.2 — AudioRecorder para M4A/AAC 16kHz 64kbps.

2. VOICE SERVICE REESCRITO (lib/infrastructure/voice/voice_service.dart):
   - AudioRecorder substitui SpeechToText. Gravacao em M4A (RecordConfig: aacLc, 16000 Hz, 64kbps).
   - startRecording(): inicia gravacao em getTemporaryDirectory()/sopro_voice.m4a.
     Retorna bool (false se permissao negada).
   - stopRecording(): para gravacao, retorna caminho do arquivo ou null.
   - cancelRecording(): descarta gravacao sem processar.
   - isRecording: Future<bool> via _recorder.isRecording().
   - processAudio(filePath): le arquivo, base64 encoda, envia ao Gemini 2.5 Flash Preview.
     JSON contract: {transcricao, intent, ambiente, titulo, conteudo}. Loga voice_debug.
   - transcribeAudio(filePath): chama processAudio e retorna so result.transcript (String?).
     Usado pelos campos de formulario (nome do ambiente, titulo/conteudo do gatilho).
   - resolveIntentFromText(transcript): Gemini Text API + fallback regex para re-analise
     apos edicao manual. Substitui o antigo resolveIntent(transcript).
   - _sendAudioToGemini(base64): POST inline_data audio/m4a, timeout 30s.
   - _sendTextToGemini(transcript): POST text parts, timeout 10s (re-analise).
   - Regex parseIntent() mantido como fallback offline.
   - TTS (speak/stopSpeaking) inalterado.
   - REMOVIDOS: SpeechToText, _findPtBrLocale, startListening, stopListening.

3. ENDPOINT GEMINI AUDIO:
   - gemini-2.5-flash-preview-05-20:generateContent (suporta inline_data de audio).
   - geminiSystemPrompt: solicita campo 'transcricao' + intent + ambiente + titulo + conteudo.
   - geminiTextPrompt: versao texto para re-analise po edicao manual.

4. HOME SCREEN - BOTTOM SHEET REESCRITO (home_screen.dart):
   - UX: botao grande (88px) — SEGURAR para gravar, SOLTAR para processar.
     Listener (onPointerDown/Up/Cancel) em vez de GestureDetector.
   - Icone muda mic→stop; fundo accent→vermelho (#E53935) com glow enquanto grava.
   - Contador de segundos em tempo real. Auto-stop aos 30s (Timer.periodic).
   - Estados: idle | gravando | processando (spinner) | resultado | erro.
   - Resultado: TextField editavel com transcricao + botao re-analisar + card de intencao.
   - _reanalyze(): chama service.resolveIntentFromText() (nao grava novamente).
   - _SoundWave removida (nao faz sentido sem nivel de som do STT).
   - import dart:math removido.

5. FORMULARIOS COM MICROFONE ATUALIZADOS:
   - add_environment_screen.dart: _recordForName() substitui _listenForName().
     Tap → grava 7 s → para automaticamente → transcribeAudio() → preenche _nameController.
     Segundo tap cancela gravacao em andamento.
   - environment_detail_screen.dart: _recordForField() substitui _listenForField().
     Mesma logica, 8 s por campo. Cancela corretamente no dispose().
   - import dart:async adicionado em ambos os arquivos.

6. LOGS SUPABASE (voice_debug):
   - audio_size_bytes: tamanho do arquivo gravado em bytes.
   - gemini_http: status HTTP da resposta do Gemini.
   - gemini_raw: JSON bruto retornado pelo Gemini.
   - gemini_error: descricao do erro se houver falha.
   - final_intent: intencao final (apos fallback).

- flutter analyze lib/: No issues found.

## V1 FINALIZADA — Sopro 0.1.0

### Historico de Sprints

Sprint 1  — Setup: tabelas Environments/Triggers/ContextCards, CRUD basico, Drift + SQLite.
Sprint 2  — Telas core: HomeScreen, AddEnvironmentScreen, EnvironmentDetailScreen.
Sprint 3  — GPS nativo: FusedLocationProviderClient via MethodChannel, stream de posicao.
Sprint 4  — Geofencing: GeofencingClient + GeofenceReceiver nativo, raio configuravel.
Sprint 5  — Motor de triggers: FireTriggersUseCase + flutter_local_notifications.
Sprint 6  — Onboarding: fluxo 4 passos, permissoes de localizacao e notificacoes.
Sprint 7  — BLE Social: scan + advertise + GATT server/client via MethodChannel (sem pacote BLE externo).
Sprint 8  — ContextCard v2: campos role + company; ContextCardEntity; troca BLE funcional.
Sprint 9  — BleEncounters + BG: tabela BleEncounters (schemaV3), foreground service corrigido.
Sprint 10 — Triggers em 2o plano: deep-link de notificacao → EnvironmentDetailScreen.
Sprint 11 — Configuracoes: SettingsScreen, edicao de ambientes/gatilhos, animacoes push.
Sprint 12 — Supabase logs: AppLogger fire-and-forget, foto de perfil, icone do app, som/cooldown.
Sprint 13 — Notif + WhatsApp: canal Importance.MAX, debounce de trigger, TX Power BLE, campo phone.
Sprint 14 — GATT Retry: auto-retry 3x + closeZombieGatts; linguagem sem jargao tecnico na UI.
Sprint 15 — Cartao completo: _ContextCardSheet com todos os campos; toggle WhatsApp independente.
Sprint 16 — Dedup BLE: dedup por card.id, TTL 10s, refresh 30s, auditoria de seguranca.
Sprint 17      — Fechamento V1: fix GeofenceReceiver (IMPORTANCE_MAX), refresh BLE 10s, docs finais.
Sprint V2-Voz  — Voz: speech_to_text + flutter_tts, FAB mic na Home, regex on-device, mic nos formularios, configuracoes de voz.
Sprint V2-Voz-Fix     — Locale pt-BR dinamico via locales() + Gemini API para intencao com fallback regex; _processing spinner no sheet.
Sprint V2-Gemini-Robustez — Modelo gemini-1.5-flash, heuristica STT ingles, transcript editavel com re-analisar.
Sprint V2-GeminiAudio  — Substitui STT por gravacao de audio + Gemini 2.5 Flash Audio API. UX: segure para gravar, solte para processar.
Sprint V2-VoicePro     — Botao WhatsApp-style (hold=gravar/arrastar=cancelar), fluxo zero-confirmacao, seletor de ambiente inline, lista de triggers inline, bug fix de busca case-insensitive, SYSTEM_ALERT_WINDOW, stub VoiceOverlayService, passo 5 no onboarding.

### Bugs Corrigidos em Campo (Motorola G52, Android 12)

- Notificacoes de trigger nao apareciam (Motorola My UX): canal Importance.HIGH ignorado por
  apps em background. Corrigido: Importance.MAX + Priority.MAX + ticker no FireTriggersUseCase.
- Notificacoes de geofence nativo nao apareciam (mesma causa): GeofenceReceiver.kt criava o
  canal com IMPORTANCE_HIGH quando o app nunca foi aberto. Corrigido: IMPORTANCE_MAX + ticker.
- GATT status=133 / "service not found": conexao sem fechar GATT zumbi anterior causava falha.
  Corrigido: closeZombieGatts() antes de cada tentativa + delay 600ms + 2 retries no Dart.
- MAC rotation — mesmo usuario aparecia multiplas vezes na lista BLE.
  Corrigido: deduplicacao por card.id (UUID estavel) como chave primaria do Map.
- Race condition de trigger duplo: GeofenceReceiver + GeofenceManager disparavam simultaneamente.
  Corrigido: debounce de 60 s por triggerId em FireTriggersUseCase.
- SharedPreferences obsoletas (OEM Auto Backup): prefs restauradas sem banco, causando
  onboarding_done=true com banco vazio. Corrigido: AppInitializer detecta e reseta flags.
- "Bad notification for startForeground": canal sopro_background nao existia antes do servico.
  Corrigido: NotificationService.initialize() cria ambos os canais antes do servico subir.
- GPS lento demais para geofencing confiavel: intervalo era 5s.
  Corrigido: intervalo de 2s em FusedLocationProviderClient (MainActivity.kt).

### Auditoria de Seguranca V1

Chave Supabase em source      — SEGURO. sb_publishable_ e projetada para apps cliente (analogo firebase_options). RLS no painel deve ser INSERT-only na tabela app_logs.
Payload BLE sanitizado        — CORRIGIDO (Sprint 16). _sanitize() em todos os campos; JSON invalido descartado.
Dados pessoais nos logs       — OK. Nenhum log envia telefone, nome ou coordenadas exatas. So event_type, environment_id e erros.
Toggle WhatsApp respeitado    — OK. Chave 'p' omitida do payload BLE; numero so no banco local.
Permissoes Android            — OK. Todas justificadas no manifesto; maxSdkVersion nos fallbacks.
Banco de dados cifrado        — PENDENTE V2. Drift usa SQLite padrao. Dados em armazenamento privado (/data/data/com.sopro.sopro/) inacessivel sem root. SQLCipher na V2.
Localizacao em segundo plano  — ACEITO. ACCESS_BACKGROUND_LOCATION necessario para GeofencingClient com app morto. Documentado e justificado no manifesto.

### Stack Tecnico Final

Flutter 3.x / Dart, Riverpod 2.x, Drift (SQLite schemaV4), MethodChannel / EventChannel nativos,
FusedLocationProviderClient (GPS 2s), GeofencingClient (geofences nativos com app morto),
flutter_local_notifications (IMPORTANCE_MAX), flutter_background_service (foreground service),
Supabase REST (logging anonimo, INSERT-only), image_picker, url_launcher, flutter_map + nominatim.

### Arquitetura Final

lib/
  core/constants/strings.dart         -- Todas as strings visiveis (nunca hardcode em widget)
  core/navigation/app_router.dart     -- GlobalKey<NavigatorState> + pushScreen() animado
  domain/entities/                    -- ContextCardEntity, EnvironmentEntity, TriggerEntity
  domain/use_cases/fire_triggers_use_case.dart
  data/database/                      -- Drift; schemaVersion=4; migracoes automaticas v1→v4
  data/repositories/                  -- Implementacoes dos contratos de dominio
  infrastructure/ble/                 -- BleService (scan/advertise/GATT/dedup/TTL/refresh 10s)
  infrastructure/geofence/            -- GeofenceManager (GPS stream) + NativeGeofenceService
  infrastructure/gps/                 -- NativeLocationService (FusedLocationProviderClient)
  infrastructure/notifications/       -- NotificationService (canais Android IMPORTANCE_MAX)
  infrastructure/background/          -- BackgroundServiceManager (foreground service)
  infrastructure/logging/             -- AppLogger (Supabase fire-and-forget)
  presentation/providers/             -- Riverpod: StateProviders, StreamProviders, FutureProviders
  presentation/screens/               -- Home, EnvironmentDetail, Profile, Settings, PeopleNearby
  presentation/widgets/               -- AppInitializer, EnvironmentCard

android/app/src/main/kotlin/com/sopro/sopro/
  MainActivity.kt      -- BLE scan/advertise/GATT, GPS, Geofencing; MethodChannel/EventChannel
  GeofenceReceiver.kt  -- BroadcastReceiver nativo (app morto, IMPORTANCE_MAX, ticker)

### Metricas de Teste de Campo

Dispositivos: Motorola G52 (Android 12, My UX)
Cenarios validados:
  [OK] Trigger ao entrar em geofence com app em foreground
  [OK] Trigger ao entrar em geofence com app minimizado (foreground service)
  [OK] Notificacao heads-up no Motorola (canal IMPORTANCE_MAX)
  [OK] Deep-link da notificacao abre EnvironmentDetailScreen
  [OK] Troca de ContextCard via BLE (GATT) entre dois dispositivos
  [OK] Retry GATT (3x) resolve status=133
  [OK] MAC rotation: mesmo usuario nao aparece duplicado
  [OK] TTL de 10s remove usuarios que foram embora
  [OK] Toggle WhatsApp omite numero do payload BLE
  [OK] Historico de encontros persiste entre sessoes
  [PENDENTE] Geofence nativo com app completamente morto — fix Sprint 17, aguarda validacao

### V2 — Proximos Passos

- SQLCipher: substituir driftDatabase('sopro') por conexao cifrada (Android Keystore).
- Atualizar Flutter SDK para Dart 3.10+ (desbloqueia plugins geolocator mais modernos).
- Tema claro/escuro: ThemeMode dinamico respeitando preferencia do sistema.
- Foto de perfil via Supabase Storage: sincronizar entre dispositivos (hoje so local).
- Widget Android: AppWidget na home screen com ambiente ativo e seus gatilhos.
- Exportacao de dados: backup manual (JSON) de ambientes, gatilhos e encontros.
- Estatisticas de uso: dashboard com frequencia de triggers por ambiente.
- Cache de mapa offline: tiles pre-baixados para uso sem internet.
- Background service mais robusto: reinicio apos OEM kill via WorkManager (fallback).
- iOS: camada nativa (Core Bluetooth, CoreLocation, UNUserNotificationCenter).
- Supabase RLS: confirmar INSERT-only em app_logs; adicionar indice em device_id.

## Sprint Atual
Sprint: V2-VoicePro-Etapa1 - Correcoes Criticas do Assistente de Voz - CONCLUIDO (2026-07-01)
Entregue:

CORRECAO 1 — Truncamento de JSON (causa raiz de ~80% das falhas de voz):
- voice_service.dart: substituiu response.transform(utf8.decoder).join() por
  consolidateHttpClientResponseBytes(response) + utf8.decode(bodyBytes) em
  _sendAudioToGemini() e _sendTextToGemini(). Garante leitura de todos os
  bytes antes de decodificar — evita respostas Gemini cortadas em payloads grandes.

CORRECAO 2 — Contexto de ambientes injetado no Gemini:
- VoiceService._buildEnvContext(): constroi suffix com lista de nomes dos ambientes
  existentes, injetado no prompt antes de cada chamada Gemini (audio e texto).
- processAudio() e resolveIntentFromText() recebem existingEnvironments: List<String>.
- _VoiceFabState._stopAndProcess(): busca envs via environmentRepositoryProvider
  ANTES de chamar processAudio() e passa envNames.
- _FallbackSheetState._reanalyze(): idem para re-analise por texto.
- Resultado: Gemini retorna nome EXATO do banco (ex: "Casa" e nao "casa"),
  eliminando falhas de _matchEnv() sem depender do regex case-insensitive como fallback.

CORRECAO 3 — Schemas JSON padronizados no system prompt:
- app_constants.dart: geminiSystemPrompt e geminiTextPrompt reescritos com
  7 schemas fixos: create_trigger, create_environment, create_environment_with_trigger,
  update_environment, list_environments, list_triggers, resolve_trigger, unknown.
- maxOutputTokens: 256 → 512 no audio (schemas novos sao mais verbosos).

CORRECAO 4 — Mapeamento dos novos schemas:
- VoiceIntent enum: adicionados createEnvironmentWithTrigger, updateEnvironment,
  listEnvironments (totalizando 8 intents).
- VoiceResult: adicionados triggerContent (String?), environmentRadius (int?),
  triggerTitles (List<String>) para carregar dados dos novos schemas.
- _mapGeminiResponse(): reescrito com suporte aos 7 novos schemas + retro-
  compatibilidade com schema legado (criar_trigger, criar_ambiente, etc).
- _executeResult(): novos cases para createEnvironmentWithTrigger,
  updateEnvironment, listEnvironments.
- _handleCreateEnvironmentWithTrigger(): abre AddEnvironmentScreen com GPS auto +
  SnackBar listando os gatilhos pendentes (limitacao: nav nao retorna resultado).
- _handleUpdateEnvironment(): atualiza raio diretamente via upsert se Gemini
  forneceu novo valor; caso contrario abre AddEnvironmentScreen em modo edicao.
- _handleListEnvironments(): exibe _EnvsListSheet (novo widget inline).
- _EnvsListSheet: lista nome e raio de todos os ambientes cadastrados num sheet.

CORRECAO 5 — GestureDetector com long press:
- _VoiceFab substituiu Listener (pointer events brutos) por GestureDetector
  com onLongPressStart/onLongPressMoveUpdate/onLongPressEnd/onLongPressCancel.
- Toque curto (< 500ms) dispara onTap → SnackBar "Segure para gravar".
- Long press (>= 500ms) inicia gravacao.
- Gesto de cancelar usa details.offsetFromOrigin.dy (mais preciso que delta acumulado).
- Removido _dragDeltaY (campo desnecessario com GestureDetector).

CORRECOES 6-7: GPS auto ao criar ambiente e SYSTEM_ALERT_WINDOW ja entregues
no sprint V2-VoicePro anterior (verificado sem regressao).

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Atual
Sprint: V2-VoicePro-Etapa2 - Notificacao Nativa + Redesign Soft Dark + Icones - CONCLUIDO (2026-07-02)
Entregue:

TAREFA 1 — Notificacao nativa com app fechado (BootReceiver):
- FLAG_MUTABLE no PendingIntent ja estava correto em MainActivity.kt (confirmado).
- BootReceiver.kt (novo): BroadcastReceiver que recebe BOOT_COMPLETED.
  Abre sopro.db via SQLiteDatabase nativo (sem Flutter Engine).
  Caminhos tentados: app_flutter/sopro.db, filesDir/sopro.db, getDatabasePath().
  Re-registra todos os ambientes no GeofencingClient com FLAG_MUTABLE + NEVER_EXPIRE.
  Atualiza SharedPreferences {envId → envName} para o GeofenceReceiver.
  Loga 'geofence_boot_reregistered' com count no Supabase (fire-and-forget, falha silenciosa).
- AndroidManifest: BootReceiver declarado com android:exported="true" +
  intent-filter BOOT_COMPLETED. RECEIVE_BOOT_COMPLETED ja estava no manifesto.
- Resolucao: geofences sao re-registrados apos reboot sem que o usuario precise
  reabrir o app — notificacoes voltam a funcionar imediatamente.

TAREFA 2 — Redesign "Soft Dark":
- app_theme.dart: novo design system completo.
  Cores: backgroundPrimary #12121A, backgroundSurface #1E1E2A,
         backgroundElevated #252535, accent #E8445A, textPrimary #F0F0F5,
         textSecondary #8A8A9A, textDisabled #3A3A4A.
  Nova constante borderColor #2A2A38 (borda 0.5dp em cards).
  Constantes de raio: radiusCard=16, radiusButton=20, radiusInput=14,
                      radiusBadge=20, radiusIcon=12.
  cardDecoration(): BoxDecoration padrao com cor + borda 0.5px + radius 16.
  darkTheme: ElevatedButton com radius 20 (pilula suave); InputDecorationTheme
             com radius 14, borda 0.5px em repouso e accent em foco;
             AppBar titleTextStyle com letterSpacing 0.2 (0.01em).
- environment_card.dart: Card com elevation=0, borda 0.5px, radius 16.
  _DeleteBackground com radius 16. Container de icone com radius 12 e emoji.
- environment_detail_screen.dart: _EnvironmentInfoCard usa AppTheme.cardDecoration().
  Badge de raio com radius radiusBadge + borda 0.5px. _TriggerTile Card com
  elevation=0, radius 12, borda 0.5px.
- home_screen.dart: titulo "Sopro" no AppBar com letterSpacing 0.8 (0.04em a 20sp).
  FAB glow: 0x59E8445A em idle (accent 35%), 0x8CE53935 ao gravar (55%).

TAREFA 3 — Icones ilustrativos nos ambientes:
- lib/core/utils/environment_icon_mapper.dart (novo): EnvironmentIconMapper com
  typedef EnvironmentVisual = ({String emoji, Color color}).
  getVisual(name): 14 categorias mapeadas por palavras-chave (case-insensitive,
  sem acentos via _normalize()). Fallback: 📍 cinza.
  Categorias: casa/lar, trabalho/empresa, mercado, farmacia, saude,
              academia, escola, banco, posto/mecanico, obra, restaurante,
              padaria/cafe, parque, loja/shopping.
- environment_card.dart: leading substituido por Container 44x44 com emoji e
  cor de fundo do mapper (radius 12px = AppTheme.radiusIcon).
- environment_detail_screen.dart: _EnvironmentInfoCard exibe emoji do mapper
  em vez do icone place_outlined.

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: V2-VoicePro-Etapa3 - Extracao de Titulo + Notificacao Contextual + Exclusao por Voz - CONCLUIDO (2026-07-03)
Entregue:

MELHORIA 1 — Extracao inteligente do titulo do gatilho:
- app_constants.dart: geminiSystemPrompt ampliado de 7 para 10 schemas.
  Adicionada regra critica de extracao de titulo logo apos os schemas:
  "Para o campo trigger.title, extraia SOMENTE a acao a ser realizada,
  sem pronomes, sem 'quando chegar', sem nome do ambiente. Maximo 50 chars,
  objetivo e no infinitivo."
  4 exemplos concretos de titulo correto/incorreto para calibrar o modelo.
- geminiTextPrompt: regra de titulo adicionada tambem na versao texto (re-analise).
  3 novos schemas declarados: delete_environment, delete_trigger, delete_all_triggers.

MELHORIA 2 — Notificacao contextual inteligente:
- fire_triggers_use_case.dart: _buildNotificationMessage(triggerTitle, envName).
  5 regras em ordem de prioridade por palavras-chave do titulo:
  comprar/buscar/pegar/trazer → "Voce esta em X. Lembrou de Y?"
  falar/ligar/contatar/avisar/perguntar → "Voce chegou em X. Nao esqueca de Y."
  verificar/checar/conferir/inspecionar → "Voce esta em X. Y."
  pagar/renovar/assinar/entregar → "Voce chegou em X. Atencao: Y."
  default → "Voce chegou em X. Hora de y!"
  showTrigger(): body substituido por _buildNotificationMessage(); title = trigger.title.
- GeofenceReceiver.kt: readFirstTriggerTitle(context, envId) le primeiro trigger ativo
  do banco SQLite diretamente (sem Flutter Engine), mesmos caminhos do BootReceiver.
  buildNotificationBody(title?, envName): mesma logica de 5 prioridades do Dart.
  Titulo da notificacao: triggerTitle se disponivel, "Sopro — envName" como fallback.
  Importados: android.database.sqlite.SQLiteDatabase, java.io.File.

MELHORIA 3 — Exclusao por voz:
- voice_service.dart: VoiceIntent enum +3 valores: deleteEnvironment, deleteTrigger,
  deleteAllTriggers. _mapGeminiResponse(): 3 novos cases mapeando os schemas JSON.
- home_screen.dart: _executeResult() +3 cases. 3 novos handlers:
  _handleDeleteEnvironment(): busca ambiente por nome, mostra _DeleteEnvConfirmSheet
    (confirmacao obrigatoria — acao irreversivel). Loga 'voice_delete' no Supabase.
  _handleDeleteTrigger(): busca triggers ativos por titulo. 1 match → exclui
    diretamente. >1 match → _DeleteTriggerPickerSheet. 0 matches → snackbar.
  _handleDeleteAllTriggers(): busca ambiente, mostra _DeleteAllTriggersConfirmSheet
    (confirmacao), exclui todos os triggers do ambiente (ativos e inativos).
  3 novos sheets: _DeleteEnvConfirmSheet, _DeleteTriggerPickerSheet,
    _DeleteAllTriggersConfirmSheet.
  Todos os fluxos logam 'voice_delete' {intent, environment, trigger_title, sucesso}.
- strings.dart: voiceDeleteEnvTitle, voiceDeleteAllTitle, voiceDeletePickerTitle,
  voiceEnvDeleted, voiceTriggerDeleted, voiceAllTriggersDeleted,
  voiceTriggerDeleteNotFound, voiceEnvNotFoundForDelete.

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: V2-VoicePro-Etapa4 - Delete sem confirmacao + Titulo correto + TTS conversacional - CONCLUIDO (2026-07-03)
Entregue:

FIX 1 — Delete de ambiente sem confirmacao (undo snackbar):
- _handleDeleteEnvironment(): removida _DeleteEnvConfirmSheet.
  Fluxo: salva todos os triggers do ambiente → deleta o ambiente (cascade) →
  fala "Ambiente X removido" (TTS) → exibe SnackBar "Desfazer" (5 s).
  Ao pressionar Desfazer: re-salva o ambiente, re-salva todos os triggers,
  re-registra o geofence nativo via nativeGeofenceServiceProvider.addGeofence().
  Loga 'voice_delete_undone' no Supabase apos restauracao bem-sucedida.
- _DeleteEnvConfirmSheet removida do arquivo (sem uso).
- strings.dart: AppStrings.undo = 'Desfazer' (ja existia, usado aqui).

FIX 2 — Delete de trigger sem titulo (triggerAction == null):
- _handleDeleteTrigger(): novo roteamento quando triggerAction e null:
  - environmentName presente → busca triggers ativos daquele ambiente.
    1 trigger → exclui via _deleteTriggerDirectly().
    >1 triggers → abre _DeleteTriggerPickerSheet.
    0 triggers → snackbar + TTS "Nenhum lembrete em X."
  - environmentName tambem null → abre _EnvPickerSheet, ao selecionar
    o ambiente repete a logica acima (1 / >1 / 0 triggers).
  - app_constants.dart: 2 exemplos adicionados ao geminiSystemPrompt para
    delete_trigger com title:null (Etapa3).

FIX 3 — Titulo do trigger salvo corretamente:
- _handleCreateTrigger(): content: result.triggerContent ?? '' (era result.transcript).
- _saveAndConfirm(): idem.
- _saveAndConfirmWithGps(): idem.
- Causa: o transcript completo era salvo como conteudo do gatilho em vez do
  campo 'content' extraido pelo Gemini.

FIX 4 — TTS conversacional em todos os handlers de voz:
- _speak(text): helper que le voiceAudioResponseProvider + voiceSpeechRateProvider
  antes de chamar voiceServiceProvider.speak(). Silencioso se toggle desativado.
- TTS adicionado em todos os handlers de _VoiceFabState:
  createEnvironmentWithTrigger: "Pronto! Ambiente X criado com N lembrete(s)."
  createTrigger (sucesso): "Anotado! Vou te lembrar de Y quando chegar em X."
  createTrigger (nao encontrado): "Nao encontrei o ambiente X. Quer criar agora?"
  resolveTrigger (sucesso): "Feito! Lembrete Y marcado como resolvido."
  resolveTrigger (nao encontrado): "Nao encontrei esse lembrete."
  listTriggers (encontrado): "Voce tem N lembrete(s) em X: titulo1, titulo2."
  listTriggers (nao encontrado): "Pendencias de qual ambiente?"
  listEnvironments: "Voce tem N local(is) cadastrado(s)."
  updateEnvironment (sucesso): "Feito! Raio de X atualizado para Y metros."
  fallback: "Nao entendi. Pode repetir ou digitar o que precisa?"
  deleteEnvironment (sucesso): "Ambiente X removido."
  deleteEnvironment (nao encontrado): "Nao encontrei o ambiente X."
  deleteTrigger (vazio): "Nao encontrei esse lembrete."
  deleteTrigger (multiplos): "Qual lembrete voce quer remover? Toque em um deles."
  deleteAllTriggers (onConfirm): "Todos os lembretes de X removidos."

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Atual
Sprint: V2-VoicePro-Etapa5 - Geofence pos-criacao e Botao Voz Flutuante - CONCLUIDO (2026-07-03)
Entregue:

FIX 1 — Geofence registrado apos criar/editar ambiente:
- native_geofence_service.dart: addSingleGeofence(EnvironmentEntity env) — wrapper
  de addGeofence() que loga 'native_geofence_added' {env_id, env_name} no Supabase.
- add_environment_screen.dart: _submit() gera o UUID antes do save() (para ter o ID
  correto disponivel). Apos save(), chama addSingleGeofence() com try/catch silencioso.
  Importados: uuid ^4.x e nativeGeofenceServiceProvider.
- home_screen.dart: _createEnvironmentFromGps() substitui a chamada direta a addGeofence()
  por addSingleGeofence() (inclui o log de Supabase automaticamente).
- MainActivity.kt: Log.d adicionado em addNativeGeofence():
  entrada: "addGeofence[nome] lat= lng= radius= id="
  sucesso: "addGeofence[nome] aceito pelo GeofencingClient ✓"
  falha:   "addGeofence[nome] rejeitado pelo GeofencingClient: erro"
- Resultado: qualquer ambiente criado ou editado — seja por voz ou manualmente —
  agora registra o geofence nativo imediatamente, sem aguardar o proximo startup.
  Log 'native_geofence_added' no Supabase confirma o registro em tempo real.

FIX 2 — Botao de voz flutuante (overlay):
ANDROID:
- FloatingVoiceService.kt (novo): Service com TYPE_APPLICATION_OVERLAY.
  Foreground service usando canal 'sopro_background' (IMPORTANCE_MIN, sem som).
  Exibe botao circular 64dp accent (#E8445A) no canto inferior direito (24dp/96dp).
  Verifica Settings.canDrawOverlays() em onCreate(); chama stopSelf() se negado.
  onClickListener e onLongClickListener: ambos chamam openAppWithVoice().
  openAppWithVoice(): startActivity com FLAG_ACTIVITY_SINGLE_TOP + OPEN_VOICE=true.
- MainActivity.kt: campo overlayChannel: MethodChannel? armazenado para invocar Dart.
  MethodChannel "com.sopro.sopro/overlay" com 4 metodos:
    hasOverlayPermission() → Settings.canDrawOverlays(this)
    startFloatingVoiceService() → startForegroundService/startService conforme SDK
    stopFloatingVoiceService() → stopService
    openOverlayPermissionSettings() → Settings.ACTION_MANAGE_OVERLAY_PERMISSION
  onNewIntent(): detecta OPEN_VOICE=true no Intent, chama
    overlayChannel?.invokeMethod("openVoiceFromOverlay", null).
- AndroidManifest: <service android:name=".FloatingVoiceService" android:exported="false"/>
  (SYSTEM_ALERT_WINDOW ja declarada desde Sprint V2-VoicePro).
  Uri e Settings importados em MainActivity.kt.

FLUTTER:
- home_screen.dart (_VoiceFabState):
  Campo _overlayChannel = MethodChannel('com.sopro.sopro/overlay').
  initState(): setMethodCallHandler para 'openVoiceFromOverlay' → chama _onPressStart()
    quando idle, iniciando gravacao automaticamente como se o usuario tivesse pressionado o FAB.
  dispose(): cancela o listener (setMethodCallHandler(null)).
  Importado: package:flutter/services.dart.
- settings_providers.dart: floatingVoiceEnabledProvider (StateProvider<bool>, default=false).
  Persistencia via SharedPreferences 'floating_voice_enabled'.
- settings_screen.dart: importado flutter/services.dart + const _overlayChannel.
  Secao "Acesso rapido" com _OverlayToggleTile:
    ao ativar: verifica permissao → se negada: openOverlayPermissionSettings (nao ativa);
    se concedida: startFloatingVoiceService + persiste prefs.
    ao desativar: stopFloatingVoiceService + persiste prefs.
  Widget _OverlayToggleTile adicionado ao fim do arquivo.
- app_initializer.dart: restaura overlay no startup se floating_voice_enabled=true:
  verifica permissao — se concedida: startFloatingVoiceService + atualiza provider;
  se revogada: reseta 'floating_voice_enabled'=false nas prefs silenciosamente.
  Importado: package:flutter/services.dart.
- strings.dart: settingsOverlaySection, settingsOverlayEnabled, settingsOverlayEnabledDesc,
  settingsOverlayPermNeeded adicionados.

ARQUITETURA (sem duplicacao de codigo):
  Overlay apenas abre o app (Intent) → MainActivity detecta OPEN_VOICE → notifica
  Flutter via MethodChannel → _VoiceFabState._onPressStart() grava + processa via
  VoiceService existente (AudioRecorder + Gemini). Zero logica duplicada em Kotlin.

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: V2-VoicePro-Etapa6 - Audio Otimizado + Botao Flutuante Redesenhado + Onboarding - CONCLUIDO (2026-07-03)
Entregue:

FIX 1 — Performance de audio (audio_size_bytes 244 KB → ~12 KB):
- voice_service.dart: bitRate 64000 → 12000 (12 kbps), sampleRate 16000 → 8000 (8 kHz).
  Qualidade de voz suficiente para STT; tamanho-alvo ~1 KB/s (12-15 KB em 10 s).
- Deteccao de silencio: onAmplitudeChanged(100ms) escuta amplitude durante gravacao.
  Timer de 1500 ms de silencio consecutivo abaixo de -35 dBFS → auto-stop.
- Duracao maxima: Timer interno de 10 s (era 30 s no FAB — agora o servico controla).
- Novo campo _autoStopController (StreamController<void>.broadcast()).
  Novo getter onAutoStop: Stream<void> notifica o FAB quando dispara silencio ou 10 s.
- _cancelAutoStopTimers(): cancela maxDurationTimer + silenceTimer + amplitudeSub.
  Chamado em stopRecording(), cancelRecording() e dispose() para evitar race condition.
- home_screen.dart: _VoiceFabState subscreve ao onAutoStop em initState() via _autoStopSub.
  Ao receber evento → chama _stopAndProcess() se estiver gravando.
  _autoStopSub cancelado em dispose(). _maxSeconds = 30 mantido como safety net.

FIX 2 — Botao flutuante redesenhado (FloatingVoiceService.kt reescrito):
2a. Formato circular: GradientDrawable OVAL 56dp (era View quadrado 64dp).
    Icone ic_launcher_foreground centralizado com padding 10dp (ScaleType CENTER_INSIDE).
2b. Gravacao direta no servico (sem abrir o app):
    MediaRecorder com MPEG_4/AAC, 8000 Hz, 12 kbps → arquivo minusculo.
    Toque simples = alterna on/off gravacao.
    Auto-stop em 10 s (mainHandler.postDelayed).
    Gemini Audio API via HttpURLConnection (background Thread):
      Lê API key de FlutterSharedPreferences 'gemini_api_key' (salva pelo AppInitializer).
      Prompt simplificado → apenas create_trigger e unknown.
      Cria trigger diretamente no sopro.db via SQLiteDatabase.openDatabase() (READWRITE).
      Reutiliza pattern de caminhos do BootReceiver.kt para localizar o banco.
    Toast de confirmação: "Anotado! Vou te lembrar de X em Y ✓".
    Nomes de ambientes lidos do SharedPreferences do GeofenceReceiver para o prompt.
2c. Arrastavel: OnTouchListener com ACTION_MOVE.
    Movimentos > 8dp detectados como drag → updateViewLayout() do WindowManager.
    Ultima posicao salva em SharedPreferences 'sopro_float_pos' (restaurada no proximo start).
    Se arrastou enquanto gravava → cancela a gravacao.
2d. Animacao de onda: segundo View (GradientDrawable OVAL, accent 25% opacidade) atras do botao.
    Animacao por Handler (30 fps): escala 1.0 → 1.4 → 1.0, alpha inversamente proporcional.
    Anel visivel apenas durante gravacao; oculto no idle.
2e. Oculto dentro do app: ActivityLifecycleCallbacks registrado via applicationContext.
    onActivityStarted: incrementa contador + oculta containerView.
    onActivityStopped: decrementa; se 0 → aguarda 200 ms + exibe (evita flicker).
    Desregistrado em onDestroy(). Sem Application personalizada necessaria.
- app_initializer.dart: salva geminiApiKey em SharedPreferences 'gemini_api_key'
  apos carregar prefs (secao 6), para uso pelo FloatingVoiceService Kotlin.
  Importado: app_constants.dart.

FIX 3 — Onboarding "Acesso rapido" com permissao real:
3a. Titulo: "Acesso rapido (em breve)" → "Acesso rapido" (feature disponivel agora).
    Corpo atualizado: descreve o botao flutuante e o gesto de gravar.
3b. Botoes do passo 4:
    Primario "Ativar acesso rápido" → _requestOverlayPermission():
      hasOverlayPermission() verdadeiro → _checkAndActivateOverlay() diretamente.
      hasOverlayPermission() falso → openOverlayPermissionSettings() + seta flag.
    Secundario "Agora não" → _nextPage() → _goHome() (mantem comportamento).
    Botao secundario visivel no passo 4 (antes era condicional ao _denialMessage).
3c. didChangeAppLifecycleState com WidgetsBindingObserver:
    Quando app retorna (resumed) e _waitingForOverlayPermission=true:
      _checkAndActivateOverlay(): verifica permissao → se concedida: inicia servico +
      atualiza floatingVoiceEnabledProvider + persiste pref + SnackBar "Botao ativado!".
    Importados: flutter/services.dart, settings_providers.dart.
- strings.dart: obOverlayTitle sem "(em breve)", obOverlayBody atualizado,
  obOverlayBtn = "Ativar acesso rápido", obOverlaySkip = "Agora não",
  obOverlayActivated = "Botão flutuante ativado!".

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: V2-VoicePro-Etapa7 - Botao Flutuante: Movimento Livre, Hold-to-Record, Voz sem Nome - CONCLUIDO (2026-07-03)
Entregue:

FIX 1 - MOVIMENTO LIVRE NA TELA TODA (FloatingVoiceService.kt):
- gravity alterado de Gravity.BOTTOM|END para Gravity.TOP|START.
  Com TOP|START, x e y sao offsets absolutos do canto superior esquerdo:
  drag horizontal E vertical funcionam sem inversao de eixo.
- ACTION_MOVE: dy = (event.rawY - dragStartY).toInt() (era invertido para BOTTOM).
  Ambos os eixos atualizados: params.x = initParamX + dx; params.y = initParamY + dy.
- Posicao padrao calculada dinamicamente (canto inferior direito):
  defaultButtonPosition(wavePx): usa displayMetrics para calcular x/y com margem
  24dp da direita e 96dp de baixo. Persiste ao arrastar (SharedPreferences).

FIX 2 - GRAVACAO DENTRO DO SERVICE (FloatingVoiceService.kt):
- ContextCompat.checkSelfPermission(RECORD_AUDIO) verificado antes de iniciar
  MediaRecorder. Toast "Permissao de microfone necessaria" se negado.
- Filename com timestamp: "floating_voice_${System.currentTimeMillis()}.m4a"
  evita corrupcao de arquivo em gravacoes concorrentes.
- Adicionado import androidx.core.content.ContextCompat.

FIX 3 - SEGURAR FALAR SOLTAR (FloatingVoiceService.kt):
- Logica de toque substituida por hold-to-record (estilo WhatsApp):
  ACTION_DOWN: agenda startRecording() via mainHandler.postDelayed(300ms).
  ACTION_MOVE >8dp: isDragging=true, cancela Runnable, reposiciona botao.
  ACTION_UP !dragging && isRecording: stopAndProcess() (processa audio).
  ACTION_UP !dragging && duration<300ms: Toast "Segure para gravar".
  ACTION_UP dragging: salva posicao, reset drag.
  ACTION_CANCEL: cancela Runnable + gravacao ativa.
- Novos campos: pressStartTime: Long, recordingStartRunnable: Runnable?.

FIX 4 - VOZ SEM NOME DE AMBIENTE (home_screen.dart):
- Campo _pendingEnvCreate: bool = false adicionado ao _VoiceFabState.
- _handleOpenEnvironment: quando environmentName nulo/vazio:
  Fala via TTS "Qual o nome do ambiente?", seta _pendingEnvCreate=true,
  aguarda 500ms e chama _onPressStart() para nova gravacao automatica.
- _stopAndProcess: quando _pendingEnvCreate=true, trata resultado da segunda
  gravacao como nome do ambiente: prefere environmentName (se Gemini entendeu
  create_environment) ou transcript (fallback). Depois chama _handleOpenEnvironment
  com o nome preenchido para criar o ambiente via GPS.

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Atual
Sprint: V2-VoicePro-Etapa8 - Gemini Coroutine, Estado Aguardando Nome e Efeito Visual - CONCLUIDO (2026-07-03)
Entregue:

FIX 1 - GEMINI NO SERVICE (causa raiz do erro — chamada de rede na main thread):
- FloatingVoiceService.kt: adicionado CoroutineScope(Dispatchers.IO + SupervisorJob()).
  serviceScope.cancel() em onDestroy() cancela coroutines pendentes.
- stopAndProcess(): serviceScope.launch { callGeminiWithAudio() } — toda a chamada
  de rede roda em IO thread. withContext(Dispatchers.Main) executa o resultado na UI.
- logToSupabase("floating_voice_debug"): log ANTES (step=before_gemini, audio_bytes)
  e DEPOIS (step=after_gemini, intent, error) de cada chamada Gemini.
  Usa mesma URL/chave do AppLogger.dart (publishable key, INSERT-only RLS).
- data class FloatVoiceResult(intent, environment, triggerTitle, triggerContent,
  transcript, error) substitui retorno implícito via parseAndExecute().
- Supabase key/URL copiados do AppLogger.dart como constantes no companion object.
- build.gradle: kotlinx-coroutines-android:1.7.3 adicionado.

IPC via SharedPreferences:
- Resultados que precisam de GPS (create_environment) salvos em
  "sopro_float_state" → KEY_PENDING_INTENT + KEY_PENDING_TS.
- MainActivity.onResume(): le pending intent com timestamp < 30s,
  limpa as chaves e invoca overlayChannel.invokeMethod("processPendingIntent", json).
- home_screen.dart: handler "processPendingIntent" adicionado ao setMethodCallHandler.
  _handleServicePendingIntent(): deserializa JSON, chama _handleOpenEnvironment()
  para criar ambiente com GPS atual. Import dart:convert adicionado.

FIX 2 - ESTADO AGUARDANDO NOME (FloatingVoiceService.kt):
- executeVoiceResult(): verifica "sopro_float_state" -> voice_state.
  Se VAL_AWAITING_NAME: limpa estado, usa transcript como nome do ambiente,
  salva como pending intent para o app confirmar o local via GPS.
- Caso create_environment sem nome: seta voice_state=awaiting_env_name,
  Toast "Qual e o nome? Segure para gravar o nome do ambiente."
- Na proxima gravacao: transcript usado diretamente como nome.

FIX 3 - EFEITO VISUAL AO PRESSIONAR (FloatingVoiceService.kt):
a. ESCALA DO BOTAO: ObjectAnimator.ofFloat(btn, "scaleX"/"scaleY", 1.0f, 1.3f)
   com duration=200ms e OvershootInterpolator (efeito elastico).
   Revertido em revertButtonAppearance(): escala volta a 1.0f em 150ms.
b. TRES ONDAS RIPPLE (ValueAnimator, substitui waveView e waveHandler):
   rippleViews: List<View> com 3 Views circulares (60dp cada, accent color).
   Cada onda: ValueAnimator.ofFloat(0f, 1f), duration=900ms, delay 0/300/600ms,
   INFINITE loop. scaleX/Y: 1.0 → 2.5; alpha: 0.6 → 0.0.
   Container aumentado para 160dp para acomodar ripples expandidos.
   startRippleAnimations() / stopRippleAnimations() gerenciam lista rippleAnimators.
c. COR durante gravacao: #FF2244 (mais vivo que o anterior #E53935).
   Restaura #E8445A (accent) ao parar.
- waveView, waveHandler, waveScale, waveGrowing e animateWave() REMOVIDOS.

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: V2-VoicePro-Etapa9 - Modelo Gemini Correto, Drag Independente e Delay TTS - CONCLUIDO (2026-07-03)
Entregue:

FIX 1 — MODELO GEMINI CORRETO (FloatingVoiceService.kt):
- GEMINI_ENDPOINT mudou de "gemini-2.5-flash-preview-05-20:generateContent"
  para "gemini-2.5-flash:generateContent" (mesmo modelo de AppConstants.geminiModel).
- Causa: modelo preview retornava HTTP 404 — Supabase logava after_gemini com error=http_404.
- Resultado: step=after_gemini agora tem intent valido (create_trigger/create_environment/unknown).

FIX 2 — GRAVACAO E ARRASTO COMPLETAMENTE INDEPENDENTES (FloatingVoiceService.kt):
- isDragging removido (campo e toda logica associada).
- handleTouch() refatorado com dois estados independentes:
  POSICAO: ACTION_MOVE SEMPRE atualiza params.x/y e chama updateViewLayout() —
    sem threshold, sem verificacao de estado de gravacao.
  GRAVACAO: ACTION_DOWN agenda recordingStartRunnable apos 300ms (sem condicao isDragging).
    ACTION_UP: cancela runnable se soltar antes dos 300ms; se isRecording → stopAndProcess()
    SEMPRE (mesmo que tenha arrastado); salva posicao em SharedPreferences SEMPRE.
  ACTION_CANCEL (evento de sistema): unico caso que descarta gravacao em andamento.
- Resultado: arrastar o botao durante gravacao nao cancela mais o audio. Soltar
  processa o audio independente de quanto o usuario arrastou.

FIX 3 — DELAY DE 2000MS APOS PERGUNTAR NOME DO AMBIENTE (FloatingVoiceService.kt):
- executeVoiceResult() caso create_environment sem nome:
  Toast imediato: "Qual e o nome do ambiente?"
  Handler.postDelayed(2000ms): "Segure o botao para gravar o nome."
  Garante que o mic nao captura o audio do Toast/TTS como entrada da proxima gravacao.

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: V2-VoicePro-Etapa10 - JSON Completo, Ambientes SQLite, TTS Nativo e Som de Ativacao - CONCLUIDO (2026-07-03)
Entregue:

FIX 1 — JSON COMPLETO NO KOTLIN (FloatingVoiceService.kt):
- callGeminiWithAudio(): substituiu conn.inputStream.readBytes() por loop explícito
  com ByteArrayOutputStream + buffer de 4096 bytes. Lê TODOS os bytes antes de
  decodificar — elimina truncamento em respostas Gemini grandes onde read() pode
  retornar parcialmente.
- Import java.io.ByteArrayOutputStream adicionado.

FIX 2 — CONTEXTO DE AMBIENTES VIA SQLite (FloatingVoiceService.kt):
- readEnvironmentNamesFromDb(): novo helper que abre sopro.db via SQLiteDatabase
  (mesmo padrão de caminhos do BootReceiver) e lê SELECT name FROM environments.
  Fallback: tenta sem WHERE se deleted_at não existir; retorna emptyList() em erro.
- findDbFile(): helper compartilhado para localizar sopro.db (evita duplicação).
  Usado por readEnvironmentNamesFromDb() e createTriggerInDb().
- callGeminiWithAudio(): usa readEnvironmentNamesFromDb() em vez de SharedPreferences
  do GeofenceReceiver. Inicia com "Ambientes existentes: X, Y" (nomes exatos do banco).
  Resultado: Gemini retorna nome exato do banco, eliminando falhas de matching.

FIX 3 — PARAR GRAVACAO QUANDO name=null (FloatingVoiceService.kt):
- executeVoiceResult() caso create_environment sem nome:
  Gravação já para em stopAndProcess() antes de chegar aqui.
  Salva voice_state=awaiting_env_name, mostra Toast, chama speak() imediatamente.
  mainHandler.postDelayed(2000ms): segundo Toast "Segure o botão para gravar o nome."
  Botão já reverteu ao idle — usuário precisa segurar novamente para a próxima gravação.
  Na próxima gravação: transcript usado direto como nome (sem enviar ao Gemini novamente).

FIX 4 — TTS NATIVO NO SERVICE (FloatingVoiceService.kt):
- FloatingVoiceService implementa TextToSpeech.OnInitListener.
- private var tts: TextToSpeech? = null — nullable, evita crash antes do onInit.
- onCreate(): tts = TextToSpeech(this, this).
- onInit(): tts.language = Locale("pt", "BR").
- onDestroy(): tts?.stop(); tts?.shutdown(); tts = null.
- speak(text): tts?.speak(text, QUEUE_FLUSH, null, "sopro_utt") — silencioso se null.
- Respostas por acao:
  create_trigger sucesso: "Anotado! Vou te lembrar de [titulo] quando chegar em [ambiente]."
  create_trigger env nao encontrado: "Não encontrei o local [nome]."
  create_trigger sem dados: "Não entendi. Diga: lembra de X quando chegar em Y."
  create_environment sucesso: "Pronto! Ambiente [nome] criado."
  create_environment sem nome: "Qual é o nome do ambiente?"
  awaiting_env_name sucesso: "Pronto! Abra o Sopro para confirmar o local de [nome]."
  awaiting_env_name sem audio: "Não ouvi o nome. Pressione novamente."
  unknown: "Não entendi. Pressione novamente para tentar."
  error: "Não entendi. Pressione novamente para tentar."
- Imports adicionados: android.speech.tts.TextToSpeech, java.util.Locale.

FIX 5 — SOM DE ATIVACAO DO MICROFONE (FloatingVoiceService.kt):
- startRecording(): após isRecording = true, cria ToneGenerator(STREAM_MUSIC, 80).
  startTone(TONE_PROP_BEEP, 120ms) — som curto de confirmação, volume 80%.
  mainHandler.postDelayed(200ms): toneGen.release() após o tom terminar.
  try/catch silencioso: ToneGenerator pode falhar em alguns dispositivos/modos de áudio.
- Import android.media.AudioManager e android.media.ToneGenerator adicionados.

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: V2-VoicePro-Etapa11 - MediaRecorder Leak, JSON Completo, TTS Sem Repeticao e Nome Generico - CONCLUIDO (2026-07-03)
Entregue:

FIX 1 — MEDIARECORDER RESOURCE LEAK (CRITICO) (FloatingVoiceService.kt):
- releaseMediaRecorder(): metodo centralizado com try/catch separados para stop() e
  release(). Garante que release SEMPRE executa mesmo se stop lancar excecao.
  Ao final seta mediaRecorder = null — obrigatorio para proxima chamada criar instancia nova.
- startRecording(): chama releaseMediaRecorder() ANTES de criar nova instancia
  (limpa qualquer instancia anterior). No catch de prepare()/start() chama
  releaseMediaRecorder() novamente — fix do leak que existia no caminho de erro.
- stopAndProcess(): substituiu stopRecordingIfActive() por isRecording=false +
  releaseMediaRecorder() explicitamente, garantindo o padrao correto.
- ACTION_CANCEL: substitui stopRecordingIfActive() por isRecording=false +
  releaseMediaRecorder() — mesmo padrao.
- onDestroy(): usa releaseMediaRecorder() em vez de stopRecordingIfActive().
- stopRecordingIfActive() REMOVIDO — substituido pelo padrao centralizado.

FIX 2 — JSON COMPLETO SEM BUFFEREDREADER (FloatingVoiceService.kt):
- errorStream: substituiu `bufferedReader()?.readText()` por `readBytes()?.toString(Charsets.UTF_8)`.
  Resultado logado com Log.d para diagnostico. Sem BufferedReader em nenhum caminho HTTP.
- inputStream (sucesso): ja usava ByteArrayOutputStream loop desde Etapa10 (mantido).

FIX 3 — TTS SEM REPETICAO AO ABRIR APP:
- FloatingVoiceService.speak(): apos qualquer fala bem-sucedida, salva timestamp
  em FlutterSharedPreferences com chave "flutter.floating_spoke_at" via putLong().
  Constante KEY_FLOATING_SPOKE adicionada ao companion object.
- VoiceService.dart speak(): le 'floating_spoke_at' via SharedPreferences antes de
  falar. Se diff < 10000ms (10 s): retorna sem falar — evita TTS duplicado quando
  o app abre logo apos um comando pelo botao flutuante.
  Import 'package:shared_preferences/shared_preferences.dart' adicionado.

FIX 4 — VOZ MELHOR NO TTS NATIVO (FloatingVoiceService.kt):
- onInit(): apos definir Locale("pt", "BR"), filtra tts.voices por:
  locale.language=="pt", locale.country=="BR", !isNetworkConnectionRequired,
  quality >= Voice.QUALITY_NORMAL. Ordena por quality decrescente e aplica a melhor.
  (Voice.QUALITY_NORMAL = 400 — valor correto para android.speech.tts.Voice)
- setSpeechRate(0.95f): levemente mais lento que o padrao (1.0f).
- setPitch(1.05f): tom ligeiramente mais alto = articulacao mais clara.
- Log.d registra nome e quality da voz selecionada para diagnostico.
- Import android.speech.tts.Voice adicionado.

FIX 5 — NOME GENERICO BLOQUEADO (FloatingVoiceService.kt):
- BLOCKED_ENV_NAMES: Set<String> no companion object com 11 nomes genericos:
  "ambiente", "local", "lugar", "aqui", "este", "esse", "novo", "meu", "um", "o", "a".
- create_environment: rawName.takeIf { !BLOCKED_ENV_NAMES.contains(it.lowercase()) }
  trata nome generico como vazio → salva VAL_AWAITING_NAME, TTS pede nome real.
- VAL_AWAITING_NAME branch: mesma validacao aplicada ao transcript da segunda gravacao.
  Se ainda generico: re-seta awaiting_env_name + TTS "Qual e o nome do lugar? Por exemplo..."
  (loop de ate 1 tentativa adicional antes de desistir).

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: TransparentVoiceActivity - Acoes de Voz Sem Abrir App - CONCLUIDO (2026-07-04)
Entregue:

OBJETIVO: create_trigger e create_environment do botao flutuante sem tornar o app visivel.
Causa anterior: VoiceActionReceiver chamava MainActivity com FLAG_REORDER_TO_FRONT, trazendo
o app para frente. Novo fluxo: FloatingVoiceService → SharedPreferences "sopro_voice" →
TransparentVoiceActivity (transparente, sem historico) → MethodChannel → AppInitializer.dart.

1. TransparentVoiceActivity.kt (novo):
   - Estende FlutterActivity. Theme: @android:style/Theme.Translucent.NoTitleBar.
   - getCachedEngineId(): retorna "sopro_engine" se engine esta no FlutterEngineCache,
     null caso contrario (FlutterActivity cria engine novo automaticamente).
   - shouldDestroyEngineWithHost(): false — nao destroi o engine da MainActivity.
   - onCreate(): le prefs "sopro_voice", valida timestamp < 30 s, invoca
     MethodChannel "com.sopro.sopro/voice_action" processAction com o JSON,
     chama finish() imediatamente. Activity transparente = zero visibilidade.
   - noHistory=true + excludeFromRecents=true: nunca aparece no backstack/app recentes.

2. MainActivity.kt:
   - Import io.flutter.embedding.engine.FlutterEngineCache adicionado.
   - configureFlutterEngine(): FlutterEngineCache.getInstance().put("sopro_engine", flutterEngine)
     logo apos super.configureFlutterEngine(). Engine cacheado garante processamento < 200 ms.

3. AndroidManifest.xml:
   - <activity android:name=".TransparentVoiceActivity" ...> declarada com
     theme=Translucent, excludeFromRecents=true, noHistory=true, exported=false.

4. FloatingVoiceService.kt:
   - REMOVIDOS: campos pendingEnvName / pendingEnvTimer; metodos startPendingEnvironmentFlow(),
     cancelPendingEnvironment(), confirmPendingEnvironment(), dispatchTriggerViaBroadcast(),
     savePendingIntent(). Eliminado o countdown de 5 s e o mecanismo de BroadcastReceiver.
   - ADICIONADOS: dispatchActionViaActivity(actionJson): salva em "sopro_voice" prefs +
     startActivity(TransparentVoiceActivity, FLAG_ACTIVITY_NEW_TASK).
     dispatchCreateEnvironment(envName): monta JSON create_environment + chama dispatch +
     feedback imediato via showToast/speak.
   - executeVoiceResult create_trigger: inline JSON + dispatchActionViaActivity + feedback.
   - executeVoiceResult create_environment (nome valido): dispatchCreateEnvironment().
   - executeVoiceResult VAL_AWAITING_NAME: dispatchCreateEnvironment() em vez do countdown.
   - handleTouch ACTION_UP: removida verificacao pendingEnvName.
   - startListeningForVoice: removida chamada cancelPendingEnvironment().
   - onDestroy: removido cancelamento do pendingEnvTimer.

5. AppInitializer.dart:
   - Import environment_entity.dart adicionado.
   - _processFloatingVoiceAction() ampliado para tratar intent create_environment:
     getCurrentPosition() via nativeLocationServiceProvider (retorna null se GPS indisponivel).
     Cria EnvironmentEntity com raio 100 m + GPS atual.
     environmentRepositoryProvider.save(env) + nativeGeofenceServiceProvider.addSingleGeofence(env).
     Loga 'env_created_by_voice' com status/name/lat/lng no Supabase.
     Falha silenciosa com log 'floating_voice_action_error' em caso de excecao.

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: V2-VoicePro-Etapa12 - SpeechRecognizer + Gemini Texto + Confirmacao 5s - CONCLUIDO (2026-07-03)
Entregue:

REFATORACAO COMPLETA — FloatingVoiceService: MediaRecorder + Gemini Audio → SpeechRecognizer + Gemini Texto:

REMOVIDOS:
- import android.media.MediaRecorder (e toda logica de gravacao em arquivo).
- import android.util.Base64 (sem mais codificacao de audio).
- import java.io.ByteArrayOutputStream (sem mais leitura de stream de audio).
- Campos: mediaRecorder, audioFile, isRecording.
- Metodos: startRecording(), stopAndProcess(), releaseMediaRecorder(), callGeminiWithAudio().

ADICIONADOS:
- import android.speech.RecognitionListener, RecognizerIntent, SpeechRecognizer.
- Campo speechRecognizer: SpeechRecognizer? — criado em onCreate() (main thread).
- Campo isListening: Boolean — substitui isRecording para controle de estado.
- Campos pendingEnvName: String? e pendingEnvTimer: Runnable? — confirmacao de 5 s.

FLUXO NOVO:
1. SEGURAR (> 300 ms) → startListeningForVoice() → SpeechRecognizer.startListening(pt-BR)
   + beep ToneGenerator + escala botao + ripples.
2. onReadyForSpeech → startRippleAnimations().
3. onEndOfSpeech → showProcessingState() (cinza, para ripples, 1.0x).
4. SOLTAR → stopListeningAndProcess() → speechRecognizer.stopListening().
5. onResults(text) → check VAL_AWAITING_NAME (usa transcript direto sem Gemini) OU
   serviceScope.launch { processTextWithGemini(text) }.
6. onError(code) → revertButtonAppearance() + speak(msg_amigavel).

processTextWithGemini(transcript: String) [suspend, Dispatchers.IO]:
- Loga stt_result com transcript no Supabase.
- Lê ambientes via readEnvironmentNamesFromDb() (mesmo helper existente).
- Monta prompt com 3 schemas (create_trigger, create_environment, unknown) +
  lista de ambientes exatos + transcript do usuario.
- POST ao GEMINI_ENDPOINT com text parts apenas (sem inline_data de audio).
- Lê resposta com inputStream.readBytes() (leitura completa, sem ByteArrayOutputStream).
- Loga after_gemini com http, response_length e transcript no Supabase.
- withContext(Main): revertButtonAppearance() + executeVoiceResult(result).

CONFIRMACAO DE AMBIENTE COM 5 SEGUNDOS:
- startPendingEnvironmentFlow(envName): speak "Criar X? Aguarde 5 s para confirmar
  ou pressione para cancelar." + mainHandler.postDelayed(confirmPendingEnvironment, 5000).
- cancelPendingEnvironment(): cancela timer, limpa campos, speak "Cancelado." —
  chamado por tap curto (duration < 300 ms) durante countdown.
- confirmPendingEnvironment(): savePendingIntent() para IPC com o app (GPS).
  Speak "Pronto! Abra o Sopro para confirmar o local de X."
- handleTouch ACTION_UP: `pendingEnvName != null && duration < 300L` → cancelar.

CONTINUIDADE DE FIXES ANTERIORES:
- FIX 3 (TTS sem repeticao): speak() salva KEY_FLOATING_SPOKE, mantido intacto.
- FIX 4 (melhor voz pt-BR): onInit() com Voice.QUALITY_NORMAL, mantido intacto.
- FIX 5 (nomes genericos): BLOCKED_ENV_NAMES verificado em ambos os caminhos, mantido.
- Arrasto independente: ACTION_MOVE sempre reposiciona, ACTION_CANCEL cancela STT.
- initSpeechRecognizer(): chamado em onCreate() — SpeechRecognizer.isRecognitionAvailable()
  verificado antes de criar; destroy() em onDestroy() (main thread).

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Atual
Sprint: V2-VoicePro-FloatingTriggerFix - create_trigger via BroadcastReceiver + MethodChannel - CONCLUIDO (2026-07-03)
Entregue:

DIAGNOSTICO:
- Supabase confirmava after_gemini http:200 para create_trigger, mas trigger nao aparecia no app.
- Causa raiz: Drift mantem o banco em WAL mode com cache interno. Escrever direto no SQLite
  a partir do FloatingVoiceService (outro processo) nao invalida o cache do Drift —
  os dados existiam no arquivo mas o app nao os via nos streams/queries.

SOLUCAO — BroadcastReceiver + MethodChannel (Flutter/Drift):

1. VoiceActionReceiver.kt (novo):
   - BroadcastReceiver registrado para "com.sopro.sopro.VOICE_ACTION" (exported="false").
   - onReceive(): salva action_json + timestamp em SharedPreferences "sopro_voice".
   - startActivity com FLAG_ACTIVITY_SINGLE_TOP + FLAG_ACTIVITY_REORDER_TO_FRONT
     para trazer MainActivity ao foreground e disparar onNewIntent().

2. AndroidManifest.xml:
   - <receiver android:name=".VoiceActionReceiver" android:exported="false">
     com <intent-filter> para "com.sopro.sopro.VOICE_ACTION".

3. FloatingVoiceService.kt:
   - createTriggerInDb() REMOVIDO (escrita direta ao SQLite abandonada).
   - dispatchTriggerViaBroadcast(envName, title, content): monta JSON, chama
     sendBroadcast(Intent(ACTION_VOICE).setPackage(packageName)) + feedback imediato
     (toast + TTS). Escrita no banco delegada ao Flutter via broadcast.

4. MainActivity.kt:
   - voiceActionChannel: MethodChannel? adicionado (canal "com.sopro.sopro/voice_action").
   - Inicializado em configureFlutterEngine() (sem setMethodCallHandler — so invoca Dart).
   - onNewIntent(): +if EXTRA_PROCESS_ACTION → processVoiceActionFromPrefs().
   - processVoiceActionFromPrefs(): le "sopro_voice" prefs, valida timestamp < 30 s,
     limpa prefs e chama voiceActionChannel?.invokeMethod("processAction", actionJson).

5. AppInitializer.dart:
   - Imports: dart:convert, package:uuid/uuid.dart, trigger_entity.dart.
   - _setupVoiceActionChannel(): registra handler no MethodChannel "com.sopro.sopro/voice_action".
     Chamado em _init() antes do overlay setup.
   - _processFloatingVoiceAction(jsonStr): parse JSON, busca ambiente por nome
     (case-insensitive, indexWhere), cria TriggerEntity com Uuid().v4(), salva via
     ref.read(triggerRepositoryProvider).save(). Loga trigger_created_from_floating
     {status: ok/env_not_found/error, env, title} no Supabase.

FLUXO COMPLETO:
  FloatingVoiceService.dispatchTriggerViaBroadcast()
    → sendBroadcast(ACTION_VOICE)
    → VoiceActionReceiver.onReceive(): prefs + startActivity(PROCESS_VOICE_ACTION)
    → MainActivity.onNewIntent(): processVoiceActionFromPrefs()
    → voiceActionChannel.invokeMethod("processAction", json)
    → AppInitializer._processFloatingVoiceAction(): Drift.save(TriggerEntity)
    → Supabase log "trigger_created_from_floating" {status:ok}

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: TransparentVoiceActivity sem Flutter - SQLite Direto - CONCLUIDO (2026-07-04)
Entregue:

PROBLEMA: TransparentVoiceActivity extendia FlutterActivity, o que inicializava o
Flutter Engine ao ser chamada pelo FloatingVoiceService. Isso:
  - Causava abertura do app ou onboarding em alguns dispositivos (engine novo sem estado).
  - Criava dependencia do FlutterEngineCache (acoplamento desnecessario).
  - Adicionava latencia de inicializacao do Dart VM.

SOLUCAO: TransparentVoiceActivity reescrita como Activity pura (sem Flutter):

1. TransparentVoiceActivity.kt (reescrito):
   - Estende Activity (nao mais FlutterActivity).
   - window.setBackgroundDrawableResource(android.R.color.transparent): zero visibilidade.
   - Le "sopro_voice" SharedPreferences, valida timestamp < 30 s, limpa imediatamente.
   - create_trigger: SQLiteDatabase.openDatabase() + SELECT id FROM environments
     (case-insensitive) + INSERT INTO triggers (id, environment_id, title, content,
     is_active=1, created_at). Colunas baseadas em triggers_table.dart (Drift schema).
   - create_environment: FusedLocationProviderClient.lastLocation (assíncrono) +
     INSERT INTO environments (id, name, latitude, longitude, radius_meters, created_at).
     Chama registerGeofence() apos persistir — mesmo padrao do BootReceiver.kt.
   - registerGeofence(): Geofence.Builder + GeofencingClient.addGeofences +
     salva env_name nas SharedPreferences do GeofenceReceiver.
   - findDbFile(): mesmos 3 caminhos candidatos do BootReceiver.kt/FloatingVoiceService.kt.
   - finish() sobrescrito com overridePendingTransition(0, 0) — sem animacao.
   - REMOVIDO: CACHED_ENGINE_ID, getCachedEngineId(), shouldDestroyEngineWithHost(),
     import FlutterActivity, import FlutterEngineCache, import MethodChannel.
   - ADICIONADO: imports SQLiteDatabase, Geofence, GeofencingRequest, LocationServices,
     PendingIntent, ContextCompat, UUID.

2. MainActivity.kt:
   - REMOVIDO: import io.flutter.embedding.engine.FlutterEngineCache.
   - REMOVIDO: FlutterEngineCache.getInstance().put(CACHED_ENGINE_ID, flutterEngine)
     (era necessario apenas para a TransparentVoiceActivity antiga).

3. FloatingVoiceService.kt — ActivityLifecycleCallbacks:
   - onActivityStarted(): if (activity is TransparentVoiceActivity) return
     — activity transparente nao deve acionar ocultamento do botao flutuante.
   - onActivityStopped(): idem — nao deve decrementar o contador nem mostrar o botao.

RESULTADO:
  - App NAO abre, NAO vai para onboarding, NAO e visivel ao usuario.
  - Botao flutuante NAO some apos o comando de voz.
  - Zero inicializacao de Flutter Engine — 10x mais rapido.
  - Dados no SQLite na proxima abertura do app (Drift re-query).
  - Supabase: ZERO app_start ao criar trigger/ambiente pelo botao flutuante.

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Atual
Sprint: FloatingVoiceService SQLite Direto - Remocao de TransparentVoiceActivity e VoiceActionReceiver - CONCLUIDO (2026-07-04)
Entregue:

OBJETIVO: Eliminar completamente a camada de indirection (TransparentVoiceActivity +
VoiceActionReceiver + MethodChannel) e escrever direto no SQLite a partir do
FloatingVoiceService. Resultado: zero startActivity, zero abertura do app, zero
Flutter Engine ao usar o botao flutuante.

ARQUIVOS REMOVIDOS:
- TransparentVoiceActivity.kt (Activity transparente que escrevia no SQLite via Intent)
- VoiceActionReceiver.kt (BroadcastReceiver que recebia JSON e iniciava MainActivity)

ANDROIDMANIFEST.XML:
- Removidas declaracoes: <receiver .VoiceActionReceiver> e <activity .TransparentVoiceActivity>.

FLOATINGVOICESERVICE.KT:
- REMOVIDOS: dispatchActionViaActivity(), dispatchCreateEnvironment(),
  referencias a VoiceActionReceiver.PREFS_NAME / KEY_PENDING / KEY_PENDING_TIME,
  constantes KEY_PENDING_INTENT e KEY_PENDING_TS (sem uso apos remocao),
  filtro "if (activity is TransparentVoiceActivity) return" no ActivityLifecycleCallbacks.
- ADICIONADOS:
  writeEnvironmentToDb(name, lat, lon, radius): File(filesDir, "sopro.db") +
    INSERT INTO environments (id, name, latitude, longitude, radius_meters, created_at).
    Colunas exatas do schema Drift. Chama registerGeofence() via mainHandler.post().
    Loga floating_env_created ou floating_env_error no Supabase.
  writeTriggerToDb(title, content, envName): SELECT id FROM environments (case-insensitive)
    + INSERT INTO triggers (id, environment_id, title, content, is_active=1, created_at).
    Retorna bool (false se ambiente nao encontrado). Loga floating_trigger_created/error.
  detectEmoji(name): mapa de palavras-chave para emoji (casa, trabalho, mercado…).
  registerGeofence(id, name, lat, lon, radius): Geofence.Builder + GeofencingRequest +
    GeofencingClient.addGeofences + salva nome nas prefs do GeofenceReceiver.
    (movido do TransparentVoiceActivity, mesmo padrao do BootReceiver).
  getLastLocationBlocking(): Tasks.await(FusedLocationProviderClient.lastLocation, 10s).
    Chamado de Dispatchers.IO. Retorna null se permissao negada ou GPS indisponivel.
- NOVOS IMPORTS: Geofence, GeofencingRequest, LocationServices, Tasks, UUID, TimeUnit.
- executeVoiceResult() — 3 spots atualizados:
  create_trigger: serviceScope.launch { writeTriggerToDb() } + feedback condicional.
  create_environment (nome valido): serviceScope.launch { getLastLocationBlocking() + writeEnvironmentToDb() }.
  VAL_AWAITING_NAME: idem para o segundo nome capturado por voz.

MAINACTIVITY.KT:
- REMOVIDOS: VOICE_ACTION_CHANNEL, voiceActionChannel, voiceActionChannel setup em
  configureFlutterEngine(), processVoiceActionFromPrefs(), bloco EXTRA_PROCESS_ACTION
  em onNewIntent(), override onResume() (so verificava KEY_PENDING_INTENT do IPC antigo).

APP_INITIALIZER.DART:
- REMOVIDOS: _setupVoiceActionChannel(), _processFloatingVoiceAction(), imports
  dart:convert, uuid, trigger_entity.dart, environment_entity.dart.
  (location_providers.dart mantido — exporta notificationServiceProvider usado no _init()).

CAMINHO DO BANCO CONFIRMADO: File(filesDir, "sopro.db")
= /data/data/com.sopro.sopro/files/sopro.db (drift_flutter usa getApplicationDocumentsDirectory()).

- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Sprint Anterior
Sprint: WorkManager - Persistencia via Dart/Drift sem abrir o app - CONCLUIDO (2026-07-05)
Entregue:

PROBLEMA RESOLVIDO — bug de cache WAL do SQLite direto:
- FloatingVoiceService escrevia no SQLite diretamente (floating_env_created confirmado
  no Supabase), mas o Drift no app Flutter nao via os dados porque mantem uma conexao
  aberta em cache (WAL mode). O dado existia no arquivo .db mas nao aparecia nos
  streams/queries enquanto o app estava rodando.

SOLUCAO — WorkManager + callbackDispatcher Dart:
1. pubspec.yaml: workmanager: ^0.5.1 adicionado.
2. lib/infrastructure/background/voice_action_worker.dart (novo):
   - callbackDispatcher() com @pragma('vm:entry-point') — entry-point do WorkManager.
   - kVoiceActionTask = 'voice_action' — nome da tarefa (coincide com Kotlin).
   - _kPendingKey = 'voice_pending_action' — chave SharedPreferences (Flutter adiciona
     prefixo 'flutter.' automaticamente; Kotlin grava como 'flutter.voice_pending_action').
   - _createEnvironment(): le id/name/lat/lon/radius do JSON, cria EnvironmentEntity
     com o UUID pre-gerado pelo Kotlin (mesmo ID do geofence), salva via
     EnvironmentRepository(db.environmentsDao). Geofence NAO registrado aqui —
     ja feito pelo FloatingVoiceService.registerGeofence() no mesmo fluxo.
   - _createTrigger(): busca ambiente por nome (exact match case-insensitive, depois
     contains como fallback), cria TriggerEntity, salva via TriggerRepository(db.triggersDao).
   - Ambas fecham SoproDatabase() no finally. AppLogger.log() para diagnostico.
3. lib/main.dart: Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode)
   adicionado apos WidgetsFlutterBinding.ensureInitialized(), antes do dotenv.load().
4. FloatingVoiceService.kt — REMOVIDOS: writeEnvironmentToDb(), writeTriggerToDb().
   ADICIONADO: scheduleVoiceAction(actionJson: String):
   - Grava JSON em 'flutter.voice_pending_action' no arquivo FlutterSharedPreferences.
   - Enfileira OneTimeWorkRequest.Builder(BackgroundWorker).setExpedited() via
     WorkManager.enqueueUniqueWork('sopro_voice_action', ExistingWorkPolicy.REPLACE).
   - Input data key: 'be.tramckrijte.workmanagerexample.dart_task' = 'voice_action'
     (key legacy do plugin, mantida por compatibilidade em todas as versoes 0.5.x).
   - executeVoiceResult() — 3 spots atualizados:
     create_trigger: verifica existencia do ambiente via readEnvironmentNamesFromDb()
       antes de agendar (feedback imediato ao usuario sem esperar o WorkManager).
     create_environment (nome valido): gera UUID, chama scheduleVoiceAction() +
       registerGeofence() com o mesmo UUID — garante ID consistente entre DB e geofence.
     VAL_AWAITING_NAME: idem para segundo nome capturado por voz.
   - NOVOS IMPORTS: androidx.work.Data/ExistingWorkPolicy/ListenableWorker/
     OneTimeWorkRequest/OutOfQuotaPolicy/WorkManager.
   - NOVAS CONSTANTES no companion: VOICE_ACTION_TASK, WM_DART_TASK_KEY.
5. android/app/build.gradle: androidx.work:work-runtime-ktx:2.9.1 declarado
   explicitamente — o compilador Kotlin nao resolve androidx.work.* apenas via
   dependencia transitiva do plugin Flutter.

COMPORTAMENTO ESPERADO APOS A MUDANCA:
- Botao flutuante com app FECHADO: WorkManager executa em background, Drift salva
  corretamente. Na proxima abertura do app, os streams Riverpod carregam os novos dados.
- Botao flutuante com app ABERTO: WorkManager escreve via Drift em isolate separado.
  Os streams watchAll() do app principal nao atualizam automaticamente (SQLite update
  hook nao dispara entre isolates), mas a proxima navegacao/refresh exibe os dados.
- Geofence: sempre registrado nativamente pelo FloatingVoiceService (sem dependencia
  de MethodChannel no isolate WorkManager).

- flutter analyze lib/: No issues found. flutter build apk --debug: success.
- flutter build apk --release --split-per-abi: success (arm64-v8a 22.1 MB).

## STATUS ATUAL - Julho 2026

### Arquitetura do Floating Button — Estado Atual (2026-07-05)

| Componente                   | Status                        |
|------------------------------|-------------------------------|
| SpeechRecognizer (pt-BR)     | OK                            |
| Gemini texto (NLU)           | OK — http 200                 |
| Persistencia via Drift       | OK — WorkManager implementado |
| Geofence nativo              | OK — registerGeofence() Kotlin|
| Streams watchAll() em tempo real | Limitacao conhecida (ver abaixo) |

### Limitacao Conhecida — Streams em Tempo Real

Dart streams Riverpod (watchAll()) no app principal NAO atualizam automaticamente
quando o WorkManager worker escreve, porque o SQLite update hook nao dispara entre
isolates Dart distintos. Os dados aparecem na proxima abertura do app ou navegacao
que force um rebuild dos providers.

Para uso tipico (botao flutuante com app fechado/minimizado), o comportamento e
transparente ao usuario — os dados estao prontos quando o app abre.

### Mudancas Recentes (pos-V1, nao documentadas nos sprints anteriores)

- sopro_database.dart: LazyDatabase com path explicito substitui
  driftDatabase(name:'sopro'). Persiste caminho em flutter.sopro_db_path
  nas SharedPreferences a cada abertura do banco.
- FloatingVoiceService: writeEnvironmentToDb() e writeTriggerToDb() REMOVIDOS.
  scheduleVoiceAction() agenda WorkManager; findDbFile() mantido apenas para
  readEnvironmentNamesFromDb() (prompt Gemini).
- TransparentVoiceActivity e VoiceActionReceiver removidos completamente.
- SpeechRecognizer (Etapa12) substituiu AudioRecord + MediaRecorder + AMR.
  Zero arquivo de audio, zero base64 — transcript enviado ao Gemini como texto.
- app_initializer.dart: forca criacao do banco (db.select(db.environments).get())
  antes de qualquer acesso pelo FloatingVoiceService.

## Repositorio
https://github.com/JuniorFray/APP_SOPRO.git
