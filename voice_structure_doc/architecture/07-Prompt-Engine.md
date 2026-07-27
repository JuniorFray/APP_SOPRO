
# 07 - Prompt Engine

Versão: 1.0 (Draft)

## Objetivo

O Prompt Engine é responsável por construir o contexto enviado ao LLM. Ele combina informações dos componentes do framework em um único prompt estruturado, mantendo as Skills independentes da engenharia de prompt.

---

## Responsabilidades

- Montar prompts de forma consistente.
- Combinar contexto de múltiplas fontes.
- Minimizar tokens desnecessários.
- Definir a ordem das informações.
- Isolar a engenharia de prompt do restante do framework.

---

## Arquitetura

```text
Behavior Engine
        │
Conversation State
        │
Memory Engine
        │
Planner
        │
Skill
        │
        ▼
   Prompt Engine
        │
        ▼
        LLM
```

---

## Fontes de contexto

O Prompt Engine pode utilizar:

- Behavior Engine
- Conversation State
- Memory Engine
- Planner
- Skill ativa
- Configurações do sistema

---

## Estrutura do Prompt

```text
1. Instruções do sistema
2. Personalidade
3. Contexto da conversa
4. Memórias relevantes
5. Objetivo do Planner
6. Dados da Skill
7. Entrada do usuário
```

Cada seção é independente e reutilizável.

---

## Otimização

- Remover contexto irrelevante.
- Limitar histórico enviado.
- Evitar duplicação de informações.
- Priorizar contexto mais recente.

---

## Integrações

- Behavior Engine
- Memory Engine
- Conversation State
- Planner
- Tool Providers

---

## Boas práticas

- Prompts devem ser determinísticos.
- Evitar lógica de negócio dentro dos prompts.
- Centralizar templates.
- Permitir evolução sem alterar Skills.

---

## Objetivo final

Garantir que o LLM receba sempre um contexto completo, consistente e otimizado, separando engenharia de prompt da lógica de execução do Sopro.
