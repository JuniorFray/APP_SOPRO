# Skill - Reminder
Versão: 1.0 (Draft)

## Objetivo

Criar, atualizar, concluir e cancelar lembretes pessoais do usuário.

---

## Responsabilidades

- Criar lembretes.
- Interpretar datas e horários.
- Solicitar informações faltantes.
- Atualizar lembretes existentes.
- Marcar lembretes como concluídos.
- Cancelar lembretes.

---

## Não Responsabilidades

- Gerenciar calendário completo.
- Executar notificações diretamente.
- Interpretar regras de recorrência complexas (outra Skill).

---

## Entradas

| Campo | Obrigatório |
|--------|-------------|
| Descrição | Sim |
| Data | Não |
| Hora | Não |
| Local | Não |

---

## Estados

- WaitingDescription
- WaitingDate
- WaitingTime
- WaitingConfirmation
- Saving
- Completed
- Cancelled

---

## Fluxo

Receber solicitação
↓

Extrair informações disponíveis
↓

Solicitar dados faltantes
↓

Validar data e hora
↓

Salvar lembrete
↓

Confirmar criação

---

## Tratamento de erros

- Data inválida.
- Hora inválida.
- Informações insuficientes.
- Cancelamento pelo usuário.
- Falha na persistência.

---

## Dependências

- Planner
- Conversation State
- Reminder Repository
- Date/Time Resolver

---

## Regras

- Nunca assumir datas ambíguas.
- Utilizar o contexto da conversa quando possível.
- Confirmar informações críticas antes de salvar.
- Permitir edição antes da confirmação final.

---

## Resultado

Um lembrete persistido e disponível para futuras consultas e notificações.
