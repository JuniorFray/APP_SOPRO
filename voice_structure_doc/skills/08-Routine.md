# Skill - Routine
Versão: 1.0 (Draft)

## Objetivo

Gerenciar rotinas recorrentes executadas automaticamente pelo Sopro.

---

## Responsabilidades

- Criar rotinas.
- Atualizar rotinas.
- Ativar ou desativar rotinas.
- Excluir rotinas.
- Acionar eventos programados.

---

## Não Responsabilidades

- Executar lógica específica de outras Skills.
- Enviar notificações diretamente.
- Controlar dispositivos.

---

## Entradas

| Campo | Obrigatório |
|--------|-------------|
| Nome | Sim |
| Gatilho | Sim |
| Ações | Sim |
| Recorrência | Sim |

---

## Estados

- WaitingName
- WaitingTrigger
- WaitingActions
- WaitingConfirmation
- Saving
- Active
- Disabled
- Completed
- Cancelled

---

## Fluxo

Receber solicitação
↓

Coletar gatilho
↓

Coletar ações
↓

Validar rotina
↓

Salvar
↓

Ativar

---

## Tratamento de erros

- Gatilho inválido.
- Ação inexistente.
- Rotina duplicada.
- Cancelamento pelo usuário.

---

## Dependências

- Planner
- Conversation State
- Routine Repository
- Scheduler

---

## Regras

- Uma rotina pode executar uma ou mais Skills.
- Rotinas devem ser independentes das conversas.
- Toda alteração deve atualizar o agendamento automaticamente.

---

## Resultado

Uma rotina persistida, pronta para execução automática conforme seu gatilho.
