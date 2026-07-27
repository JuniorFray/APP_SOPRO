# Skill - Search Address
Versão: 1.0 (Draft)

## Objetivo

Localizar, validar e normalizar endereços informados pelo usuário.

---

## Responsabilidades

- Pesquisar endereços.
- Resolver ambiguidades.
- Retornar sugestões.
- Normalizar dados geográficos.

---

## Não Responsabilidades

- Criar ambientes.
- Salvar endereços.
- Definir regras de negócio.

---

## Entradas

| Campo | Obrigatório |
|--------|-------------|
| Texto informado | Sim |
| Contexto da busca | Não |

---

## Saídas

- Endereço único validado.
- Lista de sugestões.
- Endereço não encontrado.

---

## Estados

- WaitingQuery
- Searching
- WaitingSelection
- Completed
- NotFound
- Cancelled

---

## Fluxo

Receber texto
↓

Pesquisar serviço de mapas
↓

Existe apenas um resultado?

→ Sim: retornar endereço

→ Não: solicitar escolha

↓

Confirmar endereço

---

## Tratamento de erros

- Nenhum resultado.
- Muitos resultados.
- Serviço indisponível.
- Cancelamento pelo usuário.

---

## Dependências

- Planner
- Conversation State
- Geocoding Service

---

## Regras

- Nunca assumir um endereço ambíguo.
- Sempre solicitar confirmação quando houver mais de uma opção.
- Retornar endereço em formato padronizado.

---

## Resultado

Disponibilizar um endereço validado para utilização por outras Skills.
