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

## Sprint Atual
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
   - Regex de intenções (pt-BR):
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

## Repositorio
https://github.com/JuniorFray/APP_SOPRO.git
