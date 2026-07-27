# Skill Specification
Versão: 1.0 (Draft)

## Objetivo

Definir o padrão obrigatório para documentar qualquer Skill do Sopro.

Toda Skill deve seguir esta estrutura.

---

# Estrutura

## 1. Nome

Nome único da Skill.

Exemplo:

CreateEnvironment

---

## 2. Objetivo

Descreve a responsabilidade da Skill em uma única frase.

---

## 3. Responsabilidades

Lista tudo o que a Skill pode fazer.

---

## 4. Não Responsabilidades

Lista tudo o que esta Skill nunca deve fazer.

---

## 5. Entradas

Todos os parâmetros aceitos.

Indicar:

- obrigatório
- opcional
- origem

---

## 6. Saídas

Resultado esperado após a execução.

---

## 7. Fluxo

Sequência completa da execução.

Exemplo:

Receber parâmetros
↓

Validar dados
↓

Executar regra
↓

Persistir
↓

Retornar resultado

---

## 8. Estados

Quais etapas podem existir durante a execução.

Exemplo:

WaitingAddress

WaitingConfirmation

Completed

Cancelled

---

## 9. Tratamento de Erros

Como a Skill responde quando:

- dados inválidos
- dados incompletos
- serviço indisponível
- usuário cancela

---

## 10. Integração

Dependências da Skill.

Exemplo:

Repositories

Services

Planner

Conversation State

---

## 11. Exemplos

Conversas reais utilizando a Skill.

---

## Objetivo Final

Garantir que todas as Skills do Sopro possuam o mesmo padrão arquitetural, facilitando manutenção, testes e evolução do sistema.
