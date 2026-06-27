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
- Localizacao: geolocator + geofence_service
- BLE Social: flutter_blue_plus
- ML On-Device: google_mlkit_text_recognition
- Notificacoes: flutter_local_notifications
- Background: flutter_background_service
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

## Regras Invioaveis
1. TODO codigo deve ter comentarios explicativos
2. Nenhum audio ou imagem bruta vai para servidor (tudo on-device)
3. Commits seguem Conventional Commits: feat:, fix:, docs:, refactor:, test:
4. Sem hardcode de strings visiveis - usar lib/core/constants/strings.dart
5. Sem setState em telas complexas - usar Riverpod
6. Privacidade antes de feature

## Sprint Atual
Sprint: 7 - BLE Social - CONCLUIDO
Entregue: flutter_blue_plus 2.3.9 (central role: scan + GATT read),
MainActivity.kt com BluetoothLeAdvertiser + BluetoothGattServer (peripheral role),
BleService.dart (scan/advertising/fetchContextCard), PeopleNearbyScreen ("Pessoas Aqui"),
botão no HomeScreen AppBar, permissões BLE no AndroidManifest.
UUIDs Sopro: Service=550e8400-..., ContextCard char=550e8401-...
license: License.nonprofit (FlutterBluePlus License — uso pessoal/educacional).

## Proximo Sprint
Sprint: 8 - BLEEncounters DB + Background Service fix
Objetivo: tabela BleEncounters no Drift para persistir encontros BLE,
corrigir flutter_background_service (pré-criar canal de notificação antes do startForeground),
integrar geofence + BLE em segundo plano.

## Repositorio
https://github.com/JuniorFray/APP_SOPRO.git