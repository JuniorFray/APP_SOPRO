# Skill - Shopping List
Versão: 1.0 (Draft)

## Objetivo

Gerenciar listas de compras por meio de conversas naturais.

---

## Responsabilidades

- Criar listas.
- Adicionar itens.
- Remover itens.
- Marcar itens como comprados.
- Consultar listas existentes.

---

## Não Responsabilidades

- Comprar produtos.
- Comparar preços.
- Fazer pedidos em mercados.

---

## Entradas

| Campo | Obrigatório |
|--------|-------------|
| Nome da lista | Não |
| Item | Depende da ação |
| Quantidade | Não |
| Unidade | Não |

---

## Estados

- WaitingAction
- WaitingItem
- UpdatingList
- Completed
- Cancelled

---

## Fluxo

Receber solicitação
↓

Identificar ação
↓

Localizar ou criar lista
↓

Aplicar alteração
↓

Persistir alterações
↓

Responder ao usuário

---

## Tratamento de erros

- Lista inexistente.
- Item não encontrado.
- Ação inválida.
- Falha na persistência.

---

## Dependências

- Planner
- Conversation State
- Shopping List Repository

---

## Regras

- Se nenhuma lista for informada, utilizar a lista padrão.
- Evitar itens duplicados.
- Permitir comandos incrementais como:
  - "adicione leite"
  - "remova pão"
  - "marque arroz como comprado"

---

## Resultado

A lista permanece sincronizada e disponível para consultas e alterações futuras.
