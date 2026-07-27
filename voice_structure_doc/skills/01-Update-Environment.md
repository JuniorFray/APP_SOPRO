# Skill - Update Environment
Versão: 1.0 (Draft)

## Objetivo

Atualizar informações de um ambiente existente.

---

## Responsabilidades

- Alterar nome.
- Alterar endereço.
- Alterar categoria.
- Alterar propriedades configuráveis.

---

## Não Responsabilidades

- Criar ambientes.
- Excluir ambientes.
- Executar automações.

---

## Entradas

| Campo | Obrigatório |
|--------|-------------|
| Ambiente | Sim |
| Alteração desejada | Sim |
| Novo valor | Sim |

---

## Estados

- WaitingEnvironment
- WaitingField
- WaitingValue
- Updating
- Completed
- Cancelled

---

## Fluxo

Receber intenção
↓

Identificar ambiente
↓

Identificar atributo
↓

Solicitar valor (se necessário)
↓

Validar
↓

Atualizar
↓

Confirmar alteração

---

## Tratamento de erros

- Ambiente inexistente.
- Valor inválido.
- Alteração não suportada.
- Cancelamento pelo usuário.

---

## Dependências

- Planner
- Conversation State
- Environment Repository

---

## Resultado

O ambiente é atualizado e as alterações ficam imediatamente disponíveis para o restante do sistema.
