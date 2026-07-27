# Planner
Versão: 1.0 (Draft)

## Objetivo
O Planner decide o próximo passo da conversa.

Ele nunca executa regras de negócio. Sua responsabilidade é transformar uma intenção em um plano de execução.

---

## Responsabilidades

- Selecionar a Skill adequada.
- Verificar se existem informações obrigatórias.
- Solicitar dados faltantes ao usuário.
- Encaminhar a execução para a Skill.
- Retomar tarefas interrompidas.

---

## O que o Planner NÃO faz

- Não interpreta linguagem natural.
- Não acessa banco de dados.
- Não chama APIs externas.
- Não implementa regras de negócio.

Essas responsabilidades pertencem ao LLM, Repositories e Skills.

---

## Fluxo

1. Recebe a intenção do Conversation Manager.
2. Identifica a Skill.
3. Verifica o Conversation State.
4. Determina o próximo passo.
5. Executa ou solicita mais informações.

---

## Exemplos

### Exemplo 1

Usuário:
"Crie um ambiente Mercado."

Plano:

- Skill: CreateEnvironment
- Nome: Mercado
- Endereço: pendente

Resposta:
"Qual é o endereço?"

---

### Exemplo 2

Usuário:
"Como está o clima?"

Existe uma tarefa ativa.

Plano:

- Pausar tarefa atual.
- Executar Weather.
- Restaurar tarefa anterior.

---

## Princípios

- Sempre perguntar apenas o necessário.
- Nunca perder contexto.
- Executar apenas quando houver informações suficientes.
- Manter o fluxo previsível.

---

## Objetivo Final

Centralizar toda a tomada de decisão da conversa, mantendo as Skills simples e independentes.
