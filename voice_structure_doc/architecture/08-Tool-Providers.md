# 08 - Tool Providers

Versão: 1.0 (Draft)

## Objetivo

O Tool Provider abstrai o acesso a serviços externos, permitindo que o Sopro utilize diferentes provedores sem alterar o Planner ou as Skills.

---

## Responsabilidades

- Padronizar integrações externas.
- Ocultar detalhes de implementação.
- Permitir substituição de provedores.
- Centralizar autenticação e configuração.
- Tratar falhas de comunicação.

---

## Arquitetura

```text
Skill
   │
   ▼
Tool Provider
   │
   ├── LLM
   ├── STT
   ├── TTS
   ├── Home Assistant
   ├── Maps
   ├── Weather
   ├── Notifications
   └── Database
```

---

## Interface

Todo Provider deve implementar:

```text
connect()
execute()
health()
disconnect()
```

A Skill interage apenas com essa interface.

---

## Exemplos de Providers

### LLM

- OpenAI
- Gemini
- Ollama

### Voz

- OpenAI Realtime
- ElevenLabs
- Kokoro
- Piper
- Qwen3-TTS

### Automação

- Home Assistant
- MQTT

### Serviços

- Geocoding
- Clima
- Agenda
- Banco de dados

---

## Seleção

O Provider ativo é definido por configuração e pode ser substituído sem alterar o restante do framework.

---

## Tratamento de erros

- Timeout
- Falha de autenticação
- Serviço indisponível
- Retry quando aplicável

Os erros são retornados ao Planner de forma padronizada.

---

## Boas práticas

- Não expor SDKs às Skills.
- Manter Providers independentes.
- Suportar múltiplas implementações.
- Centralizar credenciais.

---

## Objetivo final

Criar uma camada de abstração entre o Sopro e qualquer serviço externo, permitindo trocar tecnologias e reduzir acoplamento sem modificar a lógica das Skills.
