# 16 - Behavior Engine

Versão: 1.0 (Draft)

## Objetivo

O Behavior Engine define **como** o Sopro interage com o usuário. Ele controla personalidade, estilo de conversa, voz e adaptação ao contexto, mantendo as Skills focadas apenas na lógica de negócio.

\---

## Arquitetura

```text
Usuário
    │
Conversation Manager
    │
Behavior Engine
    │
Planner
    │
Skill
```

\---

## Responsabilidades

* Definir personalidade ativa.
* Selecionar voz.
* Ajustar tom de voz.
* Controlar nível de conversa.
* Adaptar comportamento ao contexto.
* Garantir consistência durante toda a sessão.

\---

## Componentes

```text
Behavior Engine
│
├── Personality
├── Voice
├── Conversation Style
├── Greetings
├── Humor
├── Proactivity
├── Context Adaptation
└── Memory Influence
```

\---

## Fontes de contexto

* Preferências do usuário.
* Horário.
* Dia da semana.
* Ambiente (Overlay / Home Assistant).
* Histórico recente.
* Conversation State.

\---

## Personas

* Assistant (padrão)
* Minimal
* Friendly
* Professional
* Coach

A persona pode ser escolhida pelo usuário e alterada dinamicamente.

\---

## Voz

O mecanismo de voz é desacoplado da arquitetura.

Backends suportados:

* OpenAI Realtime
* Gemini Live
* ElevenLabs
* Kokoro
* Piper
* Silero VAD
* Parakeet STT
* Gemma (llama.cpp)
* Qwen3-TTS

A troca do provedor não impacta Planner ou Skills.

\---

## Regras

* Nunca alterar o significado da resposta.
* Nunca interferir na execução das Skills.
* Manter personalidade consistente durante a conversa.
* Adaptar o comportamento de forma sutil.

\---

## Objetivo final

Separar completamente **comportamento**, **voz** e **personalidade** da lógica das Skills, permitindo uma experiência natural, configurável e de baixo custo.

