# 10 - Configuration

Versão: 1.0 (Draft)

## Objetivo

O Configuration centraliza todas as configurações do Sopro, permitindo alterar o comportamento do framework sem modificar código.

---

## Responsabilidades

- Carregar configurações.
- Validar parâmetros.
- Fornecer configurações aos componentes.
- Suportar múltiplos ambientes.
- Gerenciar valores padrão.

---

## Arquitetura

```text
Configuration
│
├── Core
├── Behavior
├── Memory
├── Planner
├── Providers
├── Plugins
└── Logging
```

---

## Categorias

### Core

- Idioma
- Timezone
- Ambiente

### Behavior

- Persona
- Voz
- Formalidade
- Proatividade

### Memory

- Persistência
- Expiração
- Limites

### Providers

- LLM
- STT
- TTS
- Home Assistant
- APIs externas

### Plugins

- Plugins habilitados
- Ordem de carregamento

---

## Prioridade

```text
Valores padrão
      ↓
Arquivo de configuração
      ↓
Variáveis de ambiente
      ↓
Configuração em tempo de execução
```

---

## Validação

Toda configuração deve ser validada durante a inicialização.

Exemplos:

- parâmetros obrigatórios;
- tipos inválidos;
- dependências ausentes.

---

## Boas práticas

- Centralizar configurações.
- Evitar valores fixos no código.
- Permitir sobrescrita por ambiente.
- Manter configurações versionadas.

---

## Objetivo final

Fornecer uma configuração consistente, flexível e independente da implementação, facilitando implantação, manutenção e evolução do framework.
