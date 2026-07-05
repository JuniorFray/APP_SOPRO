# Sopro - Contexto do Projeto para Claude Code

## O Que E Este Projeto
Sopro e um app Flutter (Android-first) de memoria fisica contextual.
Tagline: "O sussurro certo. No lugar certo."
O app lembra o usuario de tarefas no momento e local exato em que sao relevantes.

## Stack

| Camada       | Tecnologia                                                  |
|--------------|-------------------------------------------------------------|
| Framework    | Flutter 3.x + Dart                                          |
| State        | Riverpod 2.x                                                |
| Banco local  | Drift + SQLite schemaVersion=4                              |
| GPS          | FusedLocationProviderClient via MethodChannel               |
| BLE Social   | MethodChannel + EventChannel nativos                        |
| Voz (app)    | record ^5.1.2 (M4A) + flutter_tts ^3.6.3 (pt-BR)          |
| NLU          | Gemini 2.5 Flash via REST (chave em .env)                   |
| Notificacoes | flutter_local_notifications IMPORTANCE_MAX                  |
| Background   | flutter_background_service (foreground service)             |
| Logging      | Supabase REST fire-and-forget (INSERT-only)                 |

## Arquitetura Principal

```
lib/
  core/constants/strings.dart       -- strings visiveis (sem hardcode)
  domain/entities/                  -- EnvironmentEntity, TriggerEntity, ContextCardEntity
  data/database/                    -- Drift, schemaV4, migracoes v1→v4
  data/repositories/                -- implementacoes dos contratos
  infrastructure/geofence/          -- GeofenceManager (GPS stream) + nativo
  infrastructure/ble/               -- BleService scan/advertise/GATT/dedup TTL 10s
  infrastructure/voice/             -- VoiceService (AudioRecorder + Gemini + TTS)
  presentation/providers/           -- Riverpod providers
  presentation/screens/             -- Home, EnvironmentDetail, Settings, PeopleNearby

android/.../com/sopro/sopro/
  MainActivity.kt          -- BLE, GPS, Geofencing, Overlay (MethodChannel/EventChannel)
  GeofenceReceiver.kt      -- BroadcastReceiver (app morto, IMPORTANCE_MAX)
  BootReceiver.kt          -- re-registra geofences apos reboot
  FloatingVoiceService.kt  -- overlay flutuante: SpeechRecognizer + Gemini + SQLite direto
```

## Regras de Desenvolvimento (obrigatorias)
1. Todo codigo comentado sem excecao
2. Commits: Conventional Commits (feat:, fix:, docs:, refactor:, test:)
3. Sem hardcode de strings visiveis — usar lib/core/constants/strings.dart
4. Sem setState em telas complexas — usar Riverpod
5. Nenhum audio ou imagem bruta vai para servidor (tudo on-device)
6. Privacidade antes de feature
7. CLAUDE.md atualizado ao final de cada sprint + commit e push
8. db.close() em finally obrigatorio em todos os metodos SQLite direto
9. Nomes de ambiente sempre capitalizados com Locale pt-BR

## BLE UUID Sopro (FIXO - nao alterar)
```
SERVICE_UUID:           550e8400-e29b-41d4-a716-446655440000
CONTEXT_CARD_CHAR_UUID: 550e8401-e29b-41d4-a716-446655440000
```

## FloatingVoiceService — Como Funciona

```
Segurar botao (>300ms) → SpeechRecognizer pt-BR → transcreve fala
Transcript → Gemini 2.5 Flash (NLU, prompt minimo + exemplos) → JSON intent
  create_trigger     → resolvedEnv via Gemini ou regex fallback → writeTriggerToDb()
                       Se env nao existe → awaiting_env_confirm → pergunta criar
                       Se env desconhecido → awaiting_env_for_trigger → pede nome
  create_environment → GPS atual + fallback last_known → writeEnvironmentToDb()
  delete_environment → deleteEnvironmentFromDb() cascata manual triggers
  delete_trigger     → compileStatement + rowsAffected; TTS especifico se nao achar
  unknown            → TTS "Nao entendi."
App resume → invalidate(environmentsProvider + triggersByEnvironmentProvider)
```

Estados de voz (SharedPreferences "sopro_float_state", expiram em 30s):
- VAL_AWAITING_NAME: aguardando nome de ambiente apos comando sem nome
- awaiting_env_confirm: ambiente nao existe, pergunta se cria
- awaiting_env_for_trigger: trigger sem ambiente, pergunta qual local

Padrao SQLite obrigatorio:
```kotlin
var db: SQLiteDatabase? = null
return try {
    db = SQLiteDatabase.openDatabase(path, null, OPEN_READWRITE)
    // operacoes...
} catch (e: Exception) {
    logToSupabase("...", mapOf("error" to e.message))
    false
} finally {
    try { db?.close() } catch (_: Exception) {}
}
```

## Status — V1 e V2 Concluidas

- Geofencing dual: GeofencingClient (nativo) + GeofenceManager via GPS stream
- Notificacoes IMPORTANCE_MAX com ticker, testado Motorola G52
- BLE Social: dedup por card.id, TTL 10s, refresh 10s, GATT retry
- Botao flutuante: SpeechRecognizer + Gemini 2.5 Flash + SQLite direto
- Voz no app: AudioRecorder M4A + Gemini NLU + TTS pt-BR
- BootReceiver re-registra geofences apos reboot
- Dados visiveis apos overlay: invalidate no onResume (async + needs_refresh flag)
- Trigger com ambiente inexistente: fluxo awaiting_env_confirm cria amb + trigger
- Feedback TTS especifico em deletes que nao encontram o alvo
- Capitalizacao pt-BR em todos os nomes de ambiente salvos
- Extracao de ambiente do transcript via regex quando Gemini retorna vazio

## Proximos Passos — Fase 3

- SQLCipher: banco cifrado via Android Keystore
- Widget Android: ambiente ativo e gatilhos na home screen
- iOS: Core Bluetooth, CoreLocation, UNUserNotificationCenter

## Bugs Conhecidos

- Encoding de acentos nos logs Supabase pode aparecer distorcido (ex: "RÃ¡pido")
  ao ler no dashboard web; dado salvo no banco local esta correto.

## Repositorio
https://github.com/JuniorFray/APP_SOPRO.git
