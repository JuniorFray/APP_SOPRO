# Sopro — Fase 3: Visão Geral
> Geocoding, Mapa Redesenhado e Auto-Detect

---

## Decisões técnicas confirmadas

| Decisão | Status | Base |
|---|---|---|
| Geocoder nativo Android como fonte 1 | Confirmado | Benchmark 466 endereços, 100% sucesso |
| Photon como fallback | Confirmado | Já integrado, sem custo |
| Slot para provedor premium futuro | Reservado | Stub implementado, zero custo |
| Android Places / HERE descartados | Descartado | Requer billing / ToS restritivo |
| Cache local SQLite obrigatório | Confirmado | Antes de qualquer chamada externa |

---

## Sprints da Fase 3

**Sprint F3-1 — Geocoding com Cache**
Infraestrutura em cascata: cache → Geocoder nativo → Photon.
Interface abstrata iOS-ready. Slot reservado para provedor premium futuro.

**Sprint F3-2 — Mapa Redesenhado**
Campo de busca com autocomplete usando o geocoding do F3-1.
Confirmação antes de criar ambiente. Integração com fluxo de voz.

**Sprint F3-3 — Auto-Detect**
Detectar paradas de 10 min em locais desconhecidos.
Funciona com app fechado via WorkManager.

---

## Estratégia de cache

| Situação | Ação |
|---|---|
| Busca feita nos últimos 30 dias | Cache local — zero chamada |
| Local já cadastrado como ambiente | Banco local — zero chamada |
| Query nova — nome de estabelecimento | Geocoder nativo (grátis) |
| Query nova — endereço com número | Geocoder nativo (86.6% preciso) |
| Geocoder retorna vazio | Photon fallback (grátis) |
| Geocoder retorna múltiplos | Lista para usuário confirmar |

---

## Arquitetura iOS-Ready

Cada serviço tem: interface abstrata + implementação Android + stub iOS.

```
lib/infrastructure/
  geocoding/
    geocoding_platform_interface.dart   ← contrato
    android_geocoding_service.dart      ← Geocoder nativo + Photon
    ios_geocoding_service_stub.dart     ← UnsupportedError (iOS futuro)
    premium_geocoding_service_stub.dart ← slot para HERE/Google
  location/
    (já existe — NativeLocationService)
  voice/
    (já existe — FloatingVoiceService)
```

### Mapeamento Android → iOS (referência futura)

| Android | iOS futuro |
|---|---|
| `Geocoder.getFromLocationName()` | `CLGeocoder.geocodeAddressString()` |
| `Geocoder.getFromLocation()` | `CLGeocoder.reverseGeocodeLocation()` |
| `GeofencingClient` | `CLLocationManager` (CLCircularRegion) |
| `SpeechRecognizer` | `SFSpeechRecognizer` |
| `SYSTEM_ALERT_WINDOW` | Widget tela de bloqueio (sem equivalente) |

---

## Regras da Fase 3

1. Todo código comentado
2. Cache antes de qualquer chamada externa
3. Cada serviço novo tem interface abstrata + stub iOS
4. CLAUDE.md atualizado ao final de cada sprint
5. Commit + push ao final de cada sprint

---

*Fase 3 — atualizado 06/07/2026*
