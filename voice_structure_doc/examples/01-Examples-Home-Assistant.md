# Example - Home Assistant

Versão: 1.0 (Draft)

## Objetivo

Demonstrar o comportamento do Sopro quando a conversa ocorre dentro da tela principal.

---

## Princípios

- Fluxo guiado.
- Conversa contínua.
- Aproveitar contexto.
- Confirmar ações importantes.
- Retomar tarefas interrompidas.

---

## Exemplo 1 - Criar ambiente

Usuário:
"Crie um ambiente Mercado."

Sopro:
"Qual é o endereço?"

Usuário:
"Av. Brasil, 1500."

Sopro:
"Encontrei 'Av. Brasil, 1500'. Deseja utilizar este endereço?"

Usuário:
"Sim."

Sopro:
"Ambiente criado com sucesso."

---

## Exemplo 2 - Interrupção

Usuário:
"Crie um ambiente Academia."

Sopro:
"Qual é o endereço?"

Usuário:
"Como estará o clima amanhã?"

Sopro:
"Informa a previsão."

Sopro:
"Voltando ao ambiente Academia: qual é o endereço?"

---

## Exemplo 3 - Contexto

Usuário:
"Renomeie para Mercado Central."

O Sopro entende que o usuário está se referindo ao ambiente criado na conversa atual.

---

## Encerramento

No modo Home Assistant, o objetivo é concluir a tarefa com o menor esforço do usuário, mantendo contexto durante toda a conversa.
