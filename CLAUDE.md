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

## Sprint Atual
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

## Proximo Sprint
Sprint: 12 - Polimento avanado e exportacao
Possivelmente: tema claro/escuro, exportacao de dados, estatisticas de uso,
widget Android de ambiente na home, icone de categoria para ambientes.

## Repositorio
https://github.com/JuniorFray/APP_SOPRO.git
