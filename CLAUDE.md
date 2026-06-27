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
- Background: flutter_background_service (desativado, Sprint 9)
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

## ContextCard Schema (schemaVersion = 2)
Campos: id (UUID), displayName, role (cargo), company (empresa),
bio (nota pessoal), tags (interesses), createdAt, updatedAt.
BLE JSON payload: {id, n=displayName, r=role, c=company, b=bio, t=tags}

## Regras Invioaveis
1. TODO codigo deve ter comentarios explicativos
2. Nenhum audio ou imagem bruta vai para servidor (tudo on-device)
3. Commits seguem Conventional Commits: feat:, fix:, docs:, refactor:, test:
4. Sem hardcode de strings visiveis - usar lib/core/constants/strings.dart
5. Sem setState em telas complexas - usar Riverpod
6. Privacidade antes de feature

## Sprint Atual
Sprint: 8 - UI Completa - CONCLUIDO
Entregue:
- OnboardingScreen (4 passos: boas-vindas, localizacao, notificacoes, BLE)
  cada passo explica o valor antes de pedir a permissao; PageView com
  indicadores de progresso; botao "Pular" em cada passo de permissao.
- ProfileScreen (editor do ContextCard: nome, cargo, empresa, interesses,
  nota pessoal, toggle visivel/invisivel via bleVisibleProvider).
- Persistencia: ContextCard salvo no Drift (schemaVersion 1->2 com migracao
  que adiciona colunas role e company em instalacoes existentes).
- Navegacao completa: HomeScreen verifica onboarding (card == null ->
  /onboarding -> /profile -> /home); perfil acessivel pelo icone da AppBar.
- bleVisibleProvider: preferencia de visibilidade BLE, respeitada pela
  PeopleNearbyScreen antes de iniciar advertising.
- AppInitializer simplificado: apenas initialize() sem requestPermission()
  (permissoes pedidas no onboarding com contexto explicativo).
- Geofences iniciados pelo HomeScreen apos confirmar que o perfil existe.
- flutter analyze lib/: No issues found. flutter build apk --debug: success.

## Proximo Sprint
Sprint: 9 - BLEEncounters DB + Background Service fix
Objetivo: tabela BleEncounters no Drift para persistir encontros BLE,
corrigir flutter_background_service (pre-criar canal de notificacao antes
do startForeground), integrar geofence + BLE em segundo plano.

## Repositorio
https://github.com/JuniorFray/APP_SOPRO.git
