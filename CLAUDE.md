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
| Banco local  | Drift + SQLite schemaVersion=5                              |
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

## Status — Sprint F3-1 Concluida (Geocoding com Cache)

- Cache SQLite tabela geocoding_cache (schemaV5, TTL 30 dias, migration v4->v5)
- GeocodingCacheDao: findByKey (TTL-aware), saveAll, deleteExpired, buildEntry
- Cascata: cache local -> Geocoder nativo Android -> Photon/OSM fallback
- GeocodingPlatformInterface + GeocodingResult (iOS-ready, sem acoplamento de plataforma)
- AndroidGeocodingService: normalizeKey, _parseNativeResult, _searchPhoton, _saveToCache
- IOSGeocodingService stub (UnsupportedError, Fase 4)
- PremiumGeocodingService stub (HERE/Google Places slot, zero custo)
- GeocodingRepository com provider Riverpod
- MethodChannel reverseGeocode adicionado ao MainActivity.kt
- Menu benchmark geocoder removido das Configuracoes (tela inerte preservada)

## Proximos Passos — Fase 3

- Sprint F3-2: Mapa Redesenhado — campo de busca com autocomplete usando geocoding F3-1
- Sprint F3-3: Auto-Detect — paradas de 10 min via WorkManager (app fechado)
- SQLCipher: banco cifrado via Android Keystore
- Widget Android: ambiente ativo e gatilhos na home screen
- iOS: Core Bluetooth, CoreLocation, UNUserNotificationCenter

## Bugs Conhecidos

- Encoding de acentos nos logs Supabase pode aparecer distorcido (ex: "RÃ¡pido")
  ao ler no dashboard web; dado salvo no banco local esta correto.

## Repositorio
https://github.com/JuniorFray/APP_SOPRO.git

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses it. If not, it passes through unchanged. This means RTK is always safe to use.

**Important**: Even in command chains with `&&`, use `rtk`:
```bash
# ❌ Wrong
git add . && git commit -m "msg" && git push

# ✅ Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check    # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (60-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk go test             # Go test failures only (90%)
rtk jest                # Jest failures only (99.5%)
rtk vitest              # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk pytest              # Python test failures only (90%)
rtk rake test           # Ruby test failures only (90%)
rtk rspec               # RSpec test failures only (60%)
rtk test <cmd>          # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
rtk git fetch           # Compact fetch
rtk git stash           # Compact stash
rtk git worktree        # Compact worktree
```

Note: Git passthrough works for ALL subcommands, even those not explicitly listed.

### GitHub (26-87% savings)
```bash
rtk gh pr view <num>    # Compact PR view (87%)
rtk gh pr checks        # Compact PR checks (79%)
rtk gh run list         # Compact workflow runs (82%)
rtk gh issue list       # Compact issue list (80%)
rtk gh api              # Compact API responses (26%)
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
rtk uv run <cmd>        # Compact uv project command output
```

### Files & Search (60-75% savings)
```bash
rtk ls <path>           # Tree format, compact (65%)
rtk read <file>         # Code reading with filtering (60%)
rtk grep <pattern>      # Search grouped by file (75%). Format flags (-c, -l, -L, -o, -Z) run raw.
rtk find <pattern>      # Find grouped by directory (70%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk deps                # Dependency overview
rtk env                 # Environment variables compact
rtk summary <cmd>       # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

### Infrastructure (85% savings)
```bash
rtk docker ps           # Compact container list
rtk docker images       # Compact image list
rtk docker logs <c>     # Deduplicated logs
rtk kubectl get         # Compact resource list
rtk kubectl logs        # Deduplicated pod logs
```

### Network (65-70% savings)
```bash
rtk curl <url>          # Compact HTTP responses (70%)
rtk wget <url>          # Compact download output (65%)
```

### Meta Commands
```bash
rtk gain                # View token savings statistics
rtk gain --history      # View command history with savings
rtk discover            # Analyze Claude Code sessions for missed RTK usage
rtk proxy <cmd>         # Run command without filtering (for debugging)
rtk init                # Add RTK instructions to CLAUDE.md
rtk init --global       # Add RTK to ~/.claude/CLAUDE.md
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| GitHub | gh pr, gh run, gh issue | 26-87% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Files | ls, read, grep, find | 60-75% |
| Infrastructure | docker, kubectl | 85% |
| Network | curl, wget | 65-70% |

Overall average: **60-90% token reduction** on common development operations.
<!-- /rtk-instructions -->

## Ponytail Rules (Token & Code Minimization)
When writing, modifying, or refactoring code, you must strictly follow the Ponytail methodology to eliminate over-engineering and minimize token output:

1. **The Lazy Senior Hierarchy**: Before writing any new function, component, or logic, evaluate solutions in this exact order:
   - Can this be solved with native browser/HTML features? (e.g., `<input type="date">` instead of a custom date-picker library).
   - Can this be solved using the language's native standard library?
   - Can this be solved using an existing dependency already installed in `package.json` / project configuration?
   - Only write custom code if all previous options are impossible.

2. **Code Compression**: 
   - Write the absolute minimum lines of code required to make the feature work robustly.
   - Do not add "future-proof" boilerplate, defensive types for internal-only data, or unrequested architecture layers.
   - Favor short, clear, and idiomatic expressions over deeply nested logic or abstract design patterns.

3. **Output Restraint**: Do not explain your code changes unless explicitly asked. Do not output conversational boilerplate (e.g., "Sure, I can help with that..."). Output only the code block updates or terminal commands.
