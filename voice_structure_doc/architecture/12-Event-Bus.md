# 12 - Event Bus

Versão: 1.0 (Draft)

## Objetivo

O Event Bus fornece um mecanismo de comunicação desacoplada entre os componentes do Sopro, permitindo que eventos sejam publicados e consumidos sem dependências diretas.

---

## Responsabilidades

- Publicar eventos.
- Registrar assinantes.
- Distribuir eventos.
- Desacoplar componentes.
- Facilitar extensibilidade.

---

## Arquitetura

```text
Conversation Manager
        │
Behavior Engine
        │
Planner
        │
Skills
        │
Providers
        │
        ▼
     Event Bus
```

---

## Estrutura de um Evento

```text
id
type
timestamp
source
payload
metadata
```

Cada evento possui identificação única e dados necessários para seu processamento.

---

## Exemplos

- ConversationStarted
- ConversationEnded
- SkillStarted
- SkillCompleted
- ProviderFailed
- MemoryUpdated
- NotificationSent
- EnvironmentCreated

---

## Fluxo

```text
Componente
    │
publish()
    │
    ▼
Event Bus
    │
dispatch()
    │
    ▼
Subscribers
```

---

## Assinantes

Qualquer componente pode registrar interesse em um tipo de evento:

- Observability
- Memory Engine
- Behavior Engine
- Plugins
- Providers

---

## Boas práticas

- Eventos devem ser imutáveis.
- Evitar lógica de negócio no Event Bus.
- Processar eventos de forma independente.
- Utilizar nomes claros e versionáveis.

---

## Objetivo final

Permitir comunicação flexível e desacoplada entre os componentes do Sopro, simplificando integrações, extensões e monitoramento sem aumentar o acoplamento do framework.
