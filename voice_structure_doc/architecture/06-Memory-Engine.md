# 06 - Memory Engine

Versão: 1.0 (Draft)

## Objetivo

O Memory Engine é responsável por armazenar, recuperar e gerenciar as memórias do Sopro, permitindo conversas contínuas e personalizadas sem adicionar essa responsabilidade às Skills.

---

## Responsabilidades

- Gerenciar memória de curto, médio e longo prazo.
- Recuperar contexto relevante.
- Persistir preferências do usuário.
- Aplicar políticas de retenção e expiração.
- Fornecer contexto ao Planner e ao Behavior Engine.

---

## Arquitetura

```text
Conversation Manager
        │
        ▼
   Memory Engine
        │
 ├── Short-Term Memory
 ├── Long-Term Memory
 ├── User Profile
 └── Semantic Search
```

---

## Tipos de memória

### Short-Term Memory

Mantém o contexto da conversa atual.

Exemplos:

- assunto em andamento;
- entidades mencionadas;
- respostas recentes.

### Long-Term Memory

Armazena informações persistentes.

Exemplos:

- preferências;
- rotinas;
- locais frequentes;
- dispositivos.

### User Profile

Informações estáveis do usuário.

Exemplos:

- idioma;
- persona;
- preferências de interação.

---

## Recuperação

Antes do Planner executar uma Skill, o Memory Engine pode recuperar informações relevantes por similaridade semântica ou chaves conhecidas.

---

## Expiração

Nem toda informação deve ser permanente.

Políticas incluem:

- memória temporária;
- expiração por tempo;
- remoção por baixa relevância;
- exclusão solicitada pelo usuário.

---

## Integrações

- Conversation Manager
- Conversation State
- Behavior Engine
- Planner
- Tool Providers

---

## Boas práticas

- Armazenar apenas informações úteis.
- Evitar duplicação.
- Permitir auditoria e exclusão.
- Separar memória transitória da persistente.

---

## Objetivo final

Fornecer memória consistente e reutilizável para que o Sopro mantenha contexto, personalize interações e evolua ao longo do tempo sem aumentar a complexidade das Skills.
