# Conversation Architecture

Versão: 1.0 (Draft)

## Objetivo
Definir a arquitetura conversacional do Sopro.

## Filosofia
O Sopro não é um interpretador de comandos. É um assistente conversacional orientado a tarefas.

## Princípios
1. O LLM interpreta linguagem, mas não contém a lógica de negócio.
2. Toda ação é executada por uma Skill.
3. Toda conversa possui um estado.
4. O Planner decide antes de executar.
5. Skills possuem responsabilidade única.
6. Conversas podem ser interrompidas e retomadas.
7. A mesma Skill pode ter fluxos diferentes (Overlay e Home).

## Componentes
- Conversation Manager
- Planner
- Conversation State
- Skills
- Repositories / Services

## Fluxo
Usuário → STT → LLM → Conversation Manager → Planner → Skill → Repository → Resposta

## Objetivo Final
Separar linguagem, contexto, planejamento, execução e persistência.
