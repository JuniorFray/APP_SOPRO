
# 05 - Base Skill

Versão: 1.0 (Draft)

## Objetivo

A Base Skill define o contrato padrão para todas as Skills do Sopro. Ela estabelece um ciclo de vida único, interfaces consistentes e responsabilidades comuns, garantindo que qualquer Skill possa ser executada pelo Planner sem tratamento especial.

---

## Responsabilidades

- Padronizar a interface das Skills.
- Validar entradas.
- Executar a lógica da Skill.
- Produzir uma resposta estruturada.
- Reportar erros de forma consistente.
- Integrar-se ao Conversation State.

---

## Ciclo de Vida

```text
Planner
   │
   ▼
validate()
   │
   ▼
execute()
   │
   ▼
respond()
```

### validate()

- Verifica parâmetros obrigatórios.
- Confirma pré-condições.
- Retorna erros de validação quando necessário.

### execute()

- Executa a lógica principal.
- Pode acessar Providers, APIs e serviços externos.
- Não deve definir personalidade ou tom da resposta.

### respond()

- Retorna um resultado estruturado para o Behavior Engine formatar.

---

## Interface

```text
Skill
├── id
├── name
├── description
├── validate()
├── execute()
└── respond()
```

---

## Entrada

A Skill recebe:

- parâmetros do Planner;
- Conversation State;
- contexto da execução.

---

## Saída

Todas as Skills retornam uma estrutura padronizada:

```text
success
data
message
metadata
```

---

## Tratamento de erros

As Skills nunca encerram a conversa diretamente.

Elas retornam erros estruturados, por exemplo:

- parâmetro inválido;
- recurso inexistente;
- falha externa;
- permissão insuficiente.

O Planner decide como prosseguir.

---

## Integrações

- Planner
- Conversation State
- Behavior Engine
- Tool Providers

---

## Boas práticas

- Uma Skill deve possuir uma única responsabilidade.
- Evitar dependências entre Skills.
- Não controlar personalidade ou voz.
- Manter respostas determinísticas sempre que possível.
- Registrar eventos relevantes para observabilidade.

---

## Objetivo final

Garantir que todas as Skills do Sopro possuam comportamento consistente, sejam facilmente extensíveis e possam ser executadas de forma uniforme pelo Planner.
