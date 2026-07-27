# Skill - Notification
Versão: 1.0 (Draft)

## Objetivo

Entregar notificações ao usuário no momento apropriado, utilizando eventos gerados por outras Skills.

---

## Responsabilidades

- Agendar notificações.
- Enviar notificações locais.
- Cancelar notificações.
- Atualizar notificações existentes.
- Registrar o status de entrega.

---

## Não Responsabilidades

- Criar lembretes.
- Definir regras de negócio.
- Interpretar linguagem natural.

---

## Entradas

| Campo | Obrigatório |
|--------|-------------|
| Evento | Sim |
| Data/Hora | Sim |
| Conteúdo | Sim |
| Prioridade | Não |

---

## Estados

- WaitingSchedule
- Scheduled
- Delivered
- Cancelled
- Failed

---

## Fluxo

Receber evento
↓

Validar dados
↓

Agendar notificação
↓

Aguardar horário
↓

Entregar
↓

Registrar resultado

---

## Tratamento de erros

- Horário inválido.
- Agendamento duplicado.
- Falha na entrega.
- Cancelamento pelo usuário.

---

## Dependências

- Planner
- Conversation State
- Notification Service
- Reminder Skill (opcional)

---

## Regras

- Não gerar notificações sem origem definida.
- Cada notificação deve possuir um identificador único.
- Alterações em eventos de origem devem atualizar a notificação correspondente.

---

## Resultado

A notificação é agendada, entregue e registrada para acompanhamento pelo sistema.
