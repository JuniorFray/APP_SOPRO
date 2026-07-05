# Sopro - Contexto do Projeto para Claude Code

## O Que E Este Projeto
Sopro e um app Flutter (Android-first, iOS-ready) de memoria fisica contextual.
Tagline: "O sussurro certo. No lugar certo."

O nome vem do "ponto" teatral: a pessoa que sussurra a fala esquecida ao ator
exatamente quando ele precisa. O app faz o mesmo com informacoes do dia a dia.

## Stack Tecnologico
- Framework: Flutter 3.x (Dart)
- State Management: Riverpod 2.x
- Banco local: Drift + SQLite (schemaVersion=4); SQLCipher pendente para V3
- Localizacao: GPS nativo via MethodChannel (FusedLocationProviderClient, 2 s)
- BLE Social: MethodChannel + EventChannel nativos (sem pacote BLE externo)
- Voz: record ^5.1.2 (gravacao M4A) + flutter_tts ^3.6.3 (TTS pt-BR)
- NLU: Gemini 2.5 Flash via REST (chave em .env, flutter_dotenv)
- Notificacoes: flutter_local_notifications (IMPORTANCE_MAX / PRIORITY_MAX)
- Background: flutter_background_service (foreground service)
- Logging: Supabase REST fire-and-forget (INSERT-only, tabela app_logs)
- Utilitarios: flutter_map + nominatim, image_picker, url_launcher, uuid

## Arquitetura (Clean Architecture simplificada)

```
lib/
  core/constants/strings.dart          -- Todas as strings visiveis (nunca hardcode)
  core/navigation/app_router.dart      -- GlobalKey<NavigatorState> + pushScreen()
  core/utils/environment_icon_mapper.dart -- Emoji por categoria de ambiente
  domain/entities/                     -- ContextCardEntity, EnvironmentEntity, TriggerEntity
  domain/use_cases/fire_triggers_use_case.dart
  data/database/                       -- Drift; schemaVersion=4; migracoes v1→v4
  data/repositories/                   -- Implementacoes dos contratos de dominio
  infrastructure/ble/                  -- BleService (scan/advertise/GATT/dedup/TTL/refresh 10s)
  infrastructure/geofence/             -- GeofenceManager (GPS stream) + NativeGeofenceService
  infrastructure/gps/                  -- NativeLocationService (FusedLocationProviderClient)
  infrastructure/notifications/        -- NotificationService (canais IMPORTANCE_MAX)
  infrastructure/background/           -- BackgroundServiceManager (foreground service)
  infrastructure/voice/                -- VoiceService (AudioRecorder + Gemini + TTS)
  infrastructure/logging/              -- AppLogger (Supabase fire-and-forget)
  presentation/providers/              -- Riverpod: StateProviders, StreamProviders, FutureProviders
  presentation/screens/                -- Home, EnvironmentDetail, Profile, Settings, PeopleNearby
  presentation/widgets/                -- AppInitializer, EnvironmentCard

android/app/src/main/kotlin/com/sopro/sopro/
  MainActivity.kt         -- BLE, GPS, Geofencing, Overlay; MethodChannel/EventChannel
  GeofenceReceiver.kt     -- BroadcastReceiver nativo (app morto, IMPORTANCE_MAX, ticker)
  BootReceiver.kt         -- Re-registra geofences apos reboot via SQLiteDatabase nativo
  FloatingVoiceService.kt -- Overlay flutuante: SpeechRecognizer + Gemini texto + SQLite direto
```

## Entidades Principais
- Trigger (Gatilho): intencao vinculada a um local (titulo opcional)
- Environment (Ambiente): local fisico com geofence e raio configuravel
- ContextCard: perfil publico trocado via BLE com outros usuarios
- BLEEncounter: registro de encontro com outro usuario Sopro

## BLE UUID Sopro (FIXO - nao alterar)
```
SERVICE_UUID:          550e8400-e29b-41d4-a716-446655440000
CONTEXT_CARD_CHAR_UUID: 550e8401-e29b-41d4-a716-446655440000
```

## ContextCard / BleEncounters (schemaVersion = 4)
ContextCards: id(UUID), displayName, role, company, bio, tags, phone, createdAt, updatedAt.
BleEncounters: deviceId(PK=MAC BLE), displayName, role, company, bio, tags, phone, encounteredAt.
BLE JSON payload: {id, n=displayName, r=role, c=company, b=bio, t=tags, p=phone(opcional)}
Dedup por card.id (UUID estavel); MAC usado como chave temporaria ate primeiro GATT.
TTL 10 s; refresh de card a cada 10 s; _sanitize() em todos os campos.

## Regras Invioaveis
1. TODO codigo deve ter comentarios explicativos
2. Nenhum audio ou imagem bruta vai para servidor (tudo on-device)
3. Commits seguem Conventional Commits: feat:, fix:, docs:, refactor:, test:
4. Sem hardcode de strings visiveis — usar lib/core/constants/strings.dart
5. Sem setState em telas complexas — usar Riverpod
6. Privacidade antes de feature

## Regras V2 (obrigatorias desde Sprint V2-Voz)
- Todo codigo comentado sem excecao
- CLAUDE.md atualizado ao final de cada sprint
- Commit e push ao final de cada sprint

## Decisoes Tecnicas Permanentes
- **Dual geofencing**: GeofencingClient (nativo, app morto) + GeofenceManager via GPS stream (redundancia)
- **Notificacoes**: IMPORTANCE_MAX + PRIORITY_MAX + ticker + VISIBILITY_PUBLIC em todos os canais
- **Supabase logging**: fire-and-forget, nunca bloqueia UI, falhas silenciosas em producao
- **BLE phone toggle**: chave 'p' omitida do payload via collection-if quando sharePhone=false
- **Banco path**: LazyDatabase com path explicito; persiste em flutter.sopro_db_path nas SharedPreferences
- **FloatingVoice SQLite**: escreve direto no banco (db.close() em finally obrigatorio em todos os metodos)
- **onResume invalidate**: HomeScreen invalida environmentsProvider no onResume para refletir dados do servico

## Arquitetura do Botao Flutuante (FloatingVoiceService.kt)
```
Segurar botao (>300ms) → SpeechRecognizer pt-BR → Gemini 2.5 Flash (NLU) → intent
  create_trigger       → writeTriggerToDb() SQLite direto → log floating_trigger_created
  create_environment   → getLastLocationBlocking() + GPS fallback → writeEnvironmentToDb()
                         → registerGeofence() nativo → log floating_env_created
  delete_environment   → deleteEnvironmentFromDb() (cascata manual triggers)
  delete_trigger       → deleteTriggerFromDb() por titulo LIKE ou todos do ambiente
  unknown              → TTS "Nao entendi. Pressione novamente."
App abre/resume → ref.invalidate(environmentsProvider) → Drift re-query → dados visiveis
```
Padrao SQLite obrigatorio:
```kotlin
var db: SQLiteDatabase? = null
try { db = SQLiteDatabase.openDatabase(..., OPEN_READWRITE, null) ... }
catch (e: Exception) { logToSupabase(...); false }
finally { try { db?.close() } catch (_: Exception) {} }
```

## Canais de Notificacao Android
| Canal                   | Importance | Uso                             |
|-------------------------|------------|---------------------------------|
| sopro_triggers          | MAX        | Triggers (com som)              |
| sopro_triggers_silent   | MAX        | Triggers (sem som/vibracao)     |
| sopro_background        | MIN        | Foreground service persistente  |

## Auditoria de Seguranca
- Chave Supabase sb_publishable_: seguro (analogo firebase_options), RLS INSERT-only
- Payload BLE sanitizado: _sanitize() + truncate em todos os campos; JSON invalido descartado
- Telefone: nunca em logs Supabase; omitido do BLE quando toggle desativado
- Banco: armazenamento privado /data/data/com.sopro.sopro/ (inacessivel sem root); SQLCipher na V3
- Permissoes: todas justificadas no manifesto; maxSdkVersion nos fallbacks legacy

## Historico de Sprints (resumo)
Sprint 1-8    — Setup, CRUD, telas core, GPS, geofencing, triggers, onboarding, BLE Social, ContextCard.
Sprint 9-12   — BleEncounters DB, background service, deep-link, configuracoes, Supabase logs, foto, icone.
Sprint 13-17  — Notif IMPORTANCE_MAX, debounce trigger, GATT retry, dedup BLE (card.id), GeofenceReceiver fix.
V2-Voz        — VoiceService (STT + TTS), FAB mic, regex on-device, mic nos formularios, configuracoes de voz.
V2-Voz-Fix    — Locale pt-BR dinamico, Gemini API para NLU com fallback regex.
V2-GeminiRobustez — Modelo gemini-1.5-flash, heuristica STT ingles, transcript editavel.
V2-GeminiAudio — Substitui STT por gravacao M4A + Gemini Audio API. Hold-to-record UX.
V2-VoicePro   — Botao WhatsApp-style, fluxo zero-confirmacao, sheets inline, case-insensitive match.
V2-VoicePro-Etapa1 — Fix truncamento JSON Gemini, contexto de ambientes no prompt, 8 intents.
V2-VoicePro-Etapa2 — BootReceiver (geofences apos reboot), Redesign Soft Dark, icones emoji.
V2-VoicePro-Etapa3 — Extracao de titulo Gemini, notificacao contextual inteligente, exclusao por voz.
V2-VoicePro-Etapa4 — Delete sem confirmacao (undo snackbar), titulo correto salvo, TTS conversacional.
V2-VoicePro-Etapa5 — Geofence imediato apos criar ambiente, FloatingVoiceService overlay.
V2-VoicePro-Etapa6 — Audio otimizado 12kbps/8kHz, deteccao de silencio 1.5s, botao redesenhado.
V2-VoicePro-Etapa7 — Movimento livre na tela, hold-to-record, voz sem nome de ambiente.
V2-VoicePro-Etapa8 — Gemini em coroutine IO, estado awaiting_name, 3 ripples animados.
V2-VoicePro-Etapa9 — Modelo gemini-2.5-flash correto, drag independente da gravacao, delay TTS.
V2-VoicePro-Etapa10 — JSON completo ByteArrayOutputStream, ambientes via SQLite, TTS nativo pt-BR, beep.
V2-VoicePro-Etapa11 — Fix MediaRecorder leak (releaseMediaRecorder centralizado), TTS sem repeticao.
V2-VoicePro-Etapa12 — FloatingVoice: SpeechRecognizer substitui MediaRecorder + Gemini Audio.
V2-FloatingTriggerFix — BroadcastReceiver + MethodChannel para persistir via Drift (WAL cache fix).
TransparentVoiceActivity — Activity pura sem Flutter Engine para acoes sem abrir o app.
FloatingVoiceSQLiteDireto — Remove TransparentVoiceActivity; SQLite direto no FloatingVoiceService.
WorkManager — Tentativa de WorkManager para contornar WAL; depois revertido.
GPS-Fallback — Fallback de ultima localizacao (flutter.last_known_lat/lon) quando GPS null.
DbCloseFix + Delete — db.close() em finally em todos os metodos; delete_environment/trigger por voz.
SQLiteDireto-InvalidateResume — WorkManager revertido; SQLite direto + invalidate no onResume. ESTADO FINAL.
DebugLogs — logToSupabase estrategicos em processTextWithGemini (raw response, catch, before_main, dispatch).
FallbackAwaitingName — fallback GPS (last_known_lat/lon) no fluxo awaiting_name (bloco 1).
Expiracao30s — VAL_AWAITING_NAME expira em 30s com timestamp voice_state_set_at.
JsonExtraction — indexOf/lastIndexOf para extrair JSON entre primeiro { e ultimo } no parseGeminiResponse.
PromptMinimo — prompt Gemini reduzido + maxOutputTokens 1024.
Capitalizacao — nomes de ambiente capitalizados com Locale pt-BR ao salvar/deletar.
NeedsRefresh — flag flutter.needs_refresh em SharedPreferences apos delete; onResume async verifica e invalida.
TriggerAmbienteInexistente — awaiting_env_confirm: TTS pergunta se cria ambiente + bypass Gemini + handler GPS+create.
FeedbackDelete — TTS especifico quando ambiente/trigger nao encontrado no delete; compileStatement para rowsAffected.

## STATUS ATUAL (2026-07-05)

| Componente                   | Status                                         |
|------------------------------|------------------------------------------------|
| Geofencing dual              | OK (GeofencingClient + GPS stream)             |
| Notificacoes heads-up        | OK (IMPORTANCE_MAX, testado Motorola G52)      |
| BLE Social                   | OK (dedup card.id, TTL 10s, refresh 10s)       |
| Botao flutuante              | OK (SpeechRecognizer + Gemini + SQLite direto) |
| Voz no app                   | OK (AudioRecorder + Gemini 2.5 Flash)          |
| Banco de dados               | OK (Drift schemaV4, path explicito)            |
| Notif apos reboot            | OK (BootReceiver re-registra geofences)        |
| Dados visiveis apos overlay  | OK (invalidate no onResume, async + needs_refresh) |
| Trigger amb. inexistente     | OK (awaiting_env_confirm, cria amb + trigger)  |
| Feedback delete falha        | OK (TTS especifico, compileStatement rowsAffected) |

## V3 — Proximos Passos
- SQLCipher: substituir conexao SQLite por cifrada (Android Keystore)
- Tema claro/escuro: ThemeMode dinamico
- Foto de perfil via Supabase Storage (hoje so local)
- Widget Android: ambiente ativo e seus gatilhos na home screen
- Exportacao de dados: backup JSON de ambientes, gatilhos e encontros
- Estatisticas de uso: frequencia de triggers por ambiente
- Cache de mapa offline
- Background service: reinicio apos OEM kill via WorkManager
- iOS: Core Bluetooth, CoreLocation, UNUserNotificationCenter
- Supabase RLS: confirmar INSERT-only; indice em device_id

## Repositorio
https://github.com/JuniorFray/APP_SOPRO.git
