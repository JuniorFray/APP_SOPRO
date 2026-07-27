# Conversation Examples
Versão: 1.0 (Draft)

## Objetivo

Apresentar exemplos completos de conversas que representam o comportamento esperado do Sopro.

---

# Cenário 1 - Coleta de informações

Usuário:
"Crie um ambiente Mercado."

Sopro:
"Qual é o endereço?"

Usuário:
"Av. Brasil, 1500."

Sopro:
"Ambiente criado."

---

# Cenário 2 - Interrupção e retomada

Usuário:
"Crie um lembrete."

Sopro:
"Sobre o que deseja ser lembrado?"

Usuário:
"Como está o clima?"

Sopro:
"Informa o clima."

Sopro:
"Voltando ao lembrete. Sobre o que deseja ser lembrado?"

---

# Cenário 3 - Referência contextual

Usuário:
"Renomeie para Mercado Central."

Sopro identifica o objeto da conversa atual sem solicitar nova identificação.

---

# Cenário 4 - Ambiguidade

Usuário:
"Crie um ambiente na Paulista."

Sopro:
"Encontrei várias opções. Qual delas você deseja utilizar?"

---

# Cenário 5 - Mudança de Skill

Usuário:
"Adicione leite à lista de compras."

Após concluir:

"Crie um lembrete para comprar amanhã."

Cada solicitação gera um novo plano no Planner, preservando a continuidade da conversa.

---

## Princípios demonstrados

- Aproveitamento de contexto.
- Mínimo de perguntas.
- Interrupções seguras.
- Retomada automática.
- Conversa natural.
