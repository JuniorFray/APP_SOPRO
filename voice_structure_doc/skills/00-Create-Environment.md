# Skill - Create Environment
Versão: 1.0 (Draft)

## Objetivo

Criar um novo ambiente no Sopro.

---

## Responsabilidades

- Criar o ambiente.
- Coletar informações obrigatórias.
- Validar os dados.
- Persistir o ambiente.

---

## Não Responsabilidades

- Editar ambientes.
- Excluir ambientes.
- Consultar clima.
- Executar automações.

---

## Entradas

| Campo | Obrigatório |
|--------|-------------|
| Nome | Sim |
| Endereço | Depende do contexto |
| Categoria | Não |

---

## Comportamento por contexto

### Overlay

Fluxo rápido.

- Solicita apenas o nome quando necessário.
- Cria o ambiente.
- Não pesquisa endereço automaticamente.

### Home Assistant

Fluxo completo.

- Solicita nome.
- Solicita endereço quando necessário.
- Pode pesquisar endereços.
- Pode solicitar confirmação.
- Finaliza o cadastro completamente.

---

## Estados

- WaitingName
- WaitingAddress
- WaitingAddressConfirmation
- Creating
- Completed
- Cancelled

---

## Fluxo

Receber intenção
↓

Selecionar contexto
↓

Coletar dados obrigatórios
↓

Validar
↓

Criar ambiente
↓

Retornar confirmação

---

## Tratamento de erros

- Nome vazio.
- Endereço não encontrado.
- Endereço ambíguo.
- Cancelamento pelo usuário.

---

## Dependências

- Planner
- Conversation State
- Environment Repository
- Address Service (Home)

---

## Resultado

Um novo ambiente disponível para utilização pelo usuário.
