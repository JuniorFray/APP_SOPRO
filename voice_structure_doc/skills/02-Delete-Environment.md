# Skill - Delete Environment
Versão: 1.0 (Draft)

## Objetivo

Remover um ambiente existente do Sopro de forma segura.

---

## Responsabilidades

- Localizar o ambiente.
- Solicitar confirmação quando necessário.
- Excluir o ambiente.
- Garantir a consistência dos dados relacionados.

---

## Não Responsabilidades

- Criar ambientes.
- Editar ambientes.
- Restaurar ambientes excluídos.
- Executar automações.

---

## Entradas

| Campo | Obrigatório |
|--------|-------------|
| Ambiente | Sim |
| Confirmação | Sim |

---

## Estados

- WaitingEnvironment
- WaitingConfirmation
- Deleting
- Completed
- Cancelled

---

## Fluxo

Receber intenção
↓

Identificar ambiente
↓

Solicitar confirmação
↓

Excluir ambiente
↓

Retornar confirmação

---

## Tratamento de erros

- Ambiente inexistente.
- Ambiente em uso.
- Falha na exclusão.
- Cancelamento pelo usuário.

---

## Dependências

- Planner
- Conversation State
- Environment Repository

---

## Regras

- Exclusões devem exigir confirmação quando houver risco de perda de dados.
- A Skill deve informar claramente o impacto da exclusão.

---

## Resultado

O ambiente é removido do sistema e deixa de estar disponível para novas operações.
