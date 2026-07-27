# Estrutura e conteúdo de: D:\APP SOPRO\voice_structure_doc

## Árvore de diretórios

```
\architecture
\examples
\skills
\architecture\00-Behavior-Engine.md
\architecture\01-Conversation-Architecture.md
\architecture\02-Conversation-State.md
\architecture\03-Planner.md
\architecture\04-Skill-Specification.md
\architecture\05-Base-Skill.md
\architecture\06-Memory-Engine.md
\architecture\07-Prompt-Engine.md
\architecture\08-Tool-Providers.md
\architecture\09-Plugin-System.md
\architecture\10-Configuration.md
\architecture\11-Observability.md
\architecture\12-Event-Bus.md
\architecture\13-Creating-a-Skill.md
\architecture\14-Creating-a-Provider.md
\architecture\15-Best-Practices.md
\architecture\16-Testing.md
\architecture\17-Deployment.md
\examples\00-Conversation-Examples.md
\examples\01-Examples-Home-Assistant.md
\examples\02-Examples-Overlay.md
\skills\00-Create-Environment.md
\skills\01-Update-Environment.md
\skills\02-Delete-Environment.md
\skills\03-Search-Address.md
\skills\04-Weather.md
\skills\05-Reminder.md
\skills\06-Notification.md
\skills\07-Shopping-List.md
\skills\08-Routine.md
\skills\09-Geofencing.md
```

## Conteúdo dos arquivos


## File: \architecture\00-Behavior-Engine.md

```
# 16 - Behavior Engine

Versão: 1.0 (Draft)

## Objetivo

O Behavior Engine define **como** o Sopro interage com o usuário. Ele controla personalidade, estilo de conversa, voz e adaptação ao contexto, mantendo as Skills focadas apenas na lógica de negócio.

\---

## Arquitetura

```text
Usuário
    │
Conversation Manager
    │
Behavior Engine
    │
Planner
    │
Skill
```

\---

## Responsabilidades

* Definir personalidade ativa.
* Selecionar voz.
* Ajustar tom de voz.
* Controlar nível de conversa.
* Adaptar comportamento ao contexto.
* Garantir consistência durante toda a sessão.

\---

## Componentes

```text
Behavior Engine
│
├── Personality
├── Voice
├── Conversation Style
├── Greetings
├── Humor
├── Proactivity
├── Context Adaptation
└── Memory Influence
```

\---

## Fontes de contexto

* Preferências do usuário.
* Horário.
* Dia da semana.
* Ambiente (Overlay / Home Assistant).
* Histórico recente.
* Conversation State.

\---

## Personas

* Assistant (padrão)
* Minimal
* Friendly
* Professional
* Coach

A persona pode ser escolhida pelo usuário e alterada dinamicamente.

\---

## Voz

O mecanismo de voz é desacoplado da arquitetura.

Backends suportados:

* OpenAI Realtime
* Gemini Live
* ElevenLabs
* Kokoro
* Piper
* Silero VAD
* Parakeet STT
* Gemma (llama.cpp)
* Qwen3-TTS

A troca do provedor não impacta Planner ou Skills.

\---

## Regras

* Nunca alterar o significado da resposta.
* Nunca interferir na execução das Skills.
* Manter personalidade consistente durante a conversa.
* Adaptar o comportamento de forma sutil.

\---

## Objetivo final

Separar completamente **comportamento**, **voz** e **personalidade** da lógica das Skills, permitindo uma experiência natural, configurável e de baixo custo.


```

## File: \architecture\01-Conversation-Architecture.md

```
# Conversation Architecture

Versão: 1.0 (Draft)

## Objetivo
Definir a arquitetura conversacional do Sopro.

## Filosofia
O Sopro não é um interpretador de comandos. É um assistente conversacional orientado a tarefas.

## Princípios
1. O LLM interpreta linguagem, mas não contém a lógica de negócio.
2. Toda ação é executada por uma Skill.
3. Toda conversa possui um estado.
4. O Planner decide antes de executar.
5. Skills possuem responsabilidade única.
6. Conversas podem ser interrompidas e retomadas.
7. A mesma Skill pode ter fluxos diferentes (Overlay e Home).

## Componentes
- Conversation Manager
- Planner
- Conversation State
- Skills
- Repositories / Services

## Fluxo
Usuário → STT → LLM → Conversation Manager → Planner → Skill → Repository → Resposta

## Objetivo Final
Separar linguagem, contexto, planejamento, execução e persistência.

```

## File: \architecture\02-Conversation-State.md

```
# Conversation State

Versão: 1.0 (Draft)

## Objetivo
Manter o contexto da conversa sem depender do histórico enviado ao LLM.

## Estado mínimo
- Skill ativa
- Origem (Overlay/Home)
- Etapa atual
- Dados coletados
- Dados pendentes
- Última interação

## Regras
1. Uma tarefa ativa por conversa.
2. Interrupções preservam o estado.
3. Ao finalizar a tarefa, o estado é limpo.
4. Persistência e estado são responsabilidades diferentes.

## Exemplo
Skill: CreateEnvironment
Etapa: Aguardando confirmação do endereço
Nome: Mercado

## Ciclo
Criar estado → Atualizar → Executar Skills → Finalizar → Limpar estado.

```

## File: \architecture\03-Planner.md

```
# Planner
Versão: 1.0 (Draft)

## Objetivo
O Planner decide o próximo passo da conversa.

Ele nunca executa regras de negócio. Sua responsabilidade é transformar uma intenção em um plano de execução.

---

## Responsabilidades

- Selecionar a Skill adequada.
- Verificar se existem informações obrigatórias.
- Solicitar dados faltantes ao usuário.
- Encaminhar a execução para a Skill.
- Retomar tarefas interrompidas.

---

## O que o Planner NÃO faz

- Não interpreta linguagem natural.
- Não acessa banco de dados.
- Não chama APIs externas.
- Não implementa regras de negócio.

Essas responsabilidades pertencem ao LLM, Repositories e Skills.

---

## Fluxo

1. Recebe a intenção do Conversation Manager.
2. Identifica a Skill.
3. Verifica o Conversation State.
4. Determina o próximo passo.
5. Executa ou solicita mais informações.

---

## Exemplos

### Exemplo 1

Usuário:
"Crie um ambiente Mercado."

Plano:

- Skill: CreateEnvironment
- Nome: Mercado
- Endereço: pendente

Resposta:
"Qual é o endereço?"

---

### Exemplo 2

Usuário:
"Como está o clima?"

Existe uma tarefa ativa.

Plano:

- Pausar tarefa atual.
- Executar Weather.
- Restaurar tarefa anterior.

---

## Princípios

- Sempre perguntar apenas o necessário.
- Nunca perder contexto.
- Executar apenas quando houver informações suficientes.
- Manter o fluxo previsível.

---

## Objetivo Final

Centralizar toda a tomada de decisão da conversa, mantendo as Skills simples e independentes.

```

## File: \architecture\04-Skill-Specification.md

```
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

```

## File: \architecture\05-Base-Skill.md

```

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

```

## File: \architecture\06-Memory-Engine.md

```
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

```

## File: \architecture\07-Prompt-Engine.md

```

# 07 - Prompt Engine

Versão: 1.0 (Draft)

## Objetivo

O Prompt Engine é responsável por construir o contexto enviado ao LLM. Ele combina informações dos componentes do framework em um único prompt estruturado, mantendo as Skills independentes da engenharia de prompt.

---

## Responsabilidades

- Montar prompts de forma consistente.
- Combinar contexto de múltiplas fontes.
- Minimizar tokens desnecessários.
- Definir a ordem das informações.
- Isolar a engenharia de prompt do restante do framework.

---

## Arquitetura

```text
Behavior Engine
        │
Conversation State
        │
Memory Engine
        │
Planner
        │
Skill
        │
        ▼
   Prompt Engine
        │
        ▼
        LLM
```

---

## Fontes de contexto

O Prompt Engine pode utilizar:

- Behavior Engine
- Conversation State
- Memory Engine
- Planner
- Skill ativa
- Configurações do sistema

---

## Estrutura do Prompt

```text
1. Instruções do sistema
2. Personalidade
3. Contexto da conversa
4. Memórias relevantes
5. Objetivo do Planner
6. Dados da Skill
7. Entrada do usuário
```

Cada seção é independente e reutilizável.

---

## Otimização

- Remover contexto irrelevante.
- Limitar histórico enviado.
- Evitar duplicação de informações.
- Priorizar contexto mais recente.

---

## Integrações

- Behavior Engine
- Memory Engine
- Conversation State
- Planner
- Tool Providers

---

## Boas práticas

- Prompts devem ser determinísticos.
- Evitar lógica de negócio dentro dos prompts.
- Centralizar templates.
- Permitir evolução sem alterar Skills.

---

## Objetivo final

Garantir que o LLM receba sempre um contexto completo, consistente e otimizado, separando engenharia de prompt da lógica de execução do Sopro.

```

## File: \architecture\08-Tool-Providers.md

```
# 08 - Tool Providers

Versão: 1.0 (Draft)

## Objetivo

O Tool Provider abstrai o acesso a serviços externos, permitindo que o Sopro utilize diferentes provedores sem alterar o Planner ou as Skills.

---

## Responsabilidades

- Padronizar integrações externas.
- Ocultar detalhes de implementação.
- Permitir substituição de provedores.
- Centralizar autenticação e configuração.
- Tratar falhas de comunicação.

---

## Arquitetura

```text
Skill
   │
   ▼
Tool Provider
   │
   ├── LLM
   ├── STT
   ├── TTS
   ├── Home Assistant
   ├── Maps
   ├── Weather
   ├── Notifications
   └── Database
```

---

## Interface

Todo Provider deve implementar:

```text
connect()
execute()
health()
disconnect()
```

A Skill interage apenas com essa interface.

---

## Exemplos de Providers

### LLM

- OpenAI
- Gemini
- Ollama

### Voz

- OpenAI Realtime
- ElevenLabs
- Kokoro
- Piper
- Qwen3-TTS

### Automação

- Home Assistant
- MQTT

### Serviços

- Geocoding
- Clima
- Agenda
- Banco de dados

---

## Seleção

O Provider ativo é definido por configuração e pode ser substituído sem alterar o restante do framework.

---

## Tratamento de erros

- Timeout
- Falha de autenticação
- Serviço indisponível
- Retry quando aplicável

Os erros são retornados ao Planner de forma padronizada.

---

## Boas práticas

- Não expor SDKs às Skills.
- Manter Providers independentes.
- Suportar múltiplas implementações.
- Centralizar credenciais.

---

## Objetivo final

Criar uma camada de abstração entre o Sopro e qualquer serviço externo, permitindo trocar tecnologias e reduzir acoplamento sem modificar a lógica das Skills.

```

## File: \architecture\09-Plugin-System.md

```
# 09 - Plugin System

Versão: 1.0 (Draft)

## Objetivo

O Plugin System permite estender o Sopro adicionando novas Skills, Tool Providers e componentes sem modificar o núcleo do framework.

---

## Responsabilidades

- Descobrir plugins automaticamente.
- Registrar componentes.
- Gerenciar ciclo de vida.
- Isolar dependências.
- Permitir habilitar ou desabilitar plugins.

---

## Arquitetura

```text
Plugin
   │
   ▼
Plugin Manager
   │
   ├── Skill Plugins
   ├── Provider Plugins
   ├── Behavior Plugins
   └── Memory Plugins
```

---

## Tipos de Plugins

### Skills
Adicionam novas capacidades ao Planner.

### Providers
Integram novos serviços externos.

### Behavior
Expandem personas ou comportamentos.

### Memory
Adicionam novas estratégias de armazenamento e recuperação.

---

## Registro

Cada plugin fornece um manifesto contendo:

```text
id
name
version
type
dependencies
entrypoint
```

O Plugin Manager registra automaticamente os componentes disponíveis.

---

## Ciclo de Vida

```text
load()
initialize()
start()
stop()
unload()
```

---

## Isolamento

- Plugins não acessam componentes internos diretamente.
- Toda comunicação ocorre por interfaces públicas.
- Falhas em um plugin não devem comprometer o framework.

---

## Boas práticas

- Uma responsabilidade por plugin.
- Compatibilidade por versão.
- Dependências explícitas.
- Configuração externa.

---

## Objetivo final

Permitir que o Sopro evolua por meio de extensões independentes, reduzindo acoplamento e facilitando a manutenção e a distribuição de novas funcionalidades.

```

## File: \architecture\10-Configuration.md

```
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

```

## File: \architecture\11-Observability.md

```
# 11 - Observability

Versão: 1.0 (Draft)

## Objetivo

O Observability fornece visibilidade sobre o funcionamento do Sopro, permitindo monitorar, diagnosticar e auditar o comportamento do framework em produção.

---

## Responsabilidades

- Registrar eventos.
- Coletar métricas.
- Realizar tracing das execuções.
- Facilitar diagnóstico de falhas.
- Apoiar auditoria e análise de desempenho.

---

## Arquitetura

```text
Framework
    │
    ▼
Observability
│
├── Logging
├── Metrics
├── Tracing
└── Audit
```

---

## Logging

Registrar eventos relevantes como:

- início e fim de conversas;
- execução de Skills;
- chamadas a Providers;
- erros e exceções;
- mudanças de estado.

---

## Métricas

Exemplos:

- tempo de resposta;
- número de conversas;
- uso de Skills;
- consumo de tokens;
- falhas por Provider.

---

## Tracing

Permite acompanhar uma execução completa:

```text
Usuário
    ↓
Conversation Manager
    ↓
Behavior Engine
    ↓
Planner
    ↓
Skill
    ↓
Provider
```

Cada etapa recebe um identificador para correlação.

---

## Auditoria

Registrar ações importantes:

- criação de ambientes;
- alterações persistentes;
- notificações enviadas;
- mudanças de configuração.

---

## Boas práticas

- Não registrar dados sensíveis.
- Permitir diferentes níveis de log.
- Utilizar identificadores únicos por conversa.
- Integrar com plataformas de monitoramento.

---

## Objetivo final

Garantir que o funcionamento do Sopro possa ser monitorado, analisado e auditado de forma consistente, facilitando manutenção, depuração e evolução do framework.

```

## File: \architecture\12-Event-Bus.md

```
# 12 - Event Bus

Versão: 1.0 (Draft)

## Objetivo

O Event Bus fornece um mecanismo de comunicação desacoplada entre os componentes do Sopro, permitindo que eventos sejam publicados e consumidos sem dependências diretas.

---

## Responsabilidades

- Publicar eventos.
- Registrar assinantes.
- Distribuir eventos.
- Desacoplar componentes.
- Facilitar extensibilidade.

---

## Arquitetura

```text
Conversation Manager
        │
Behavior Engine
        │
Planner
        │
Skills
        │
Providers
        │
        ▼
     Event Bus
```

---

## Estrutura de um Evento

```text
id
type
timestamp
source
payload
metadata
```

Cada evento possui identificação única e dados necessários para seu processamento.

---

## Exemplos

- ConversationStarted
- ConversationEnded
- SkillStarted
- SkillCompleted
- ProviderFailed
- MemoryUpdated
- NotificationSent
- EnvironmentCreated

---

## Fluxo

```text
Componente
    │
publish()
    │
    ▼
Event Bus
    │
dispatch()
    │
    ▼
Subscribers
```

---

## Assinantes

Qualquer componente pode registrar interesse em um tipo de evento:

- Observability
- Memory Engine
- Behavior Engine
- Plugins
- Providers

---

## Boas práticas

- Eventos devem ser imutáveis.
- Evitar lógica de negócio no Event Bus.
- Processar eventos de forma independente.
- Utilizar nomes claros e versionáveis.

---

## Objetivo final

Permitir comunicação flexível e desacoplada entre os componentes do Sopro, simplificando integrações, extensões e monitoramento sem aumentar o acoplamento do framework.

```

## File: \architecture\13-Creating-a-Skill.md

```
# 13 - Creating a Skill

## Objetivo
Descrever o processo para criar uma nova Skill no Sopro.

## Passos
1. Herdar a Base Skill.
2. Definir id, nome e descrição.
3. Implementar `validate()`.
4. Implementar `execute()`.
5. Implementar `respond()`.
6. Registrar a Skill no Plugin System.

## Estrutura

```text
MySkill
├── validate()
├── execute()
└── respond()
```

## Boas práticas

- Uma responsabilidade por Skill.
- Não acessar Providers diretamente sem abstração.
- Não implementar personalidade na Skill.
- Retornar respostas estruturadas.

## Resultado

A Skill estará disponível para o Planner automaticamente após o registro.

```

## File: \architecture\14-Creating-a-Provider.md

```
# 14 - Creating a Provider

## Objetivo
Padronizar a criação de novos Tool Providers.

## Interface

```text
connect()
execute()
health()
disconnect()
```

## Passos

1. Implementar a interface.
2. Configurar autenticação.
3. Registrar no Plugin System.
4. Configurar no Configuration.

## Boas práticas

- Não expor SDKs às Skills.
- Tratar timeout e retry.
- Centralizar credenciais.

## Resultado

O Provider poderá substituir outro sem alterar o restante do framework.

```

## File: \architecture\15-Best-Practices.md

```
# 15 - Best Practices

## Arquitetura

- Componentes desacoplados.
- Interfaces estáveis.
- Configuração externa.

## Skills

- Uma responsabilidade.
- Determinísticas quando possível.
- Sem lógica de personalidade.

## Providers

- Independentes.
- Reutilizáveis.
- Tratamento consistente de erros.

## Conversação

- Reutilizar contexto.
- Fazer o mínimo de perguntas.
- Manter consistência de comportamento.

## Código

- Testável.
- Modular.
- Documentado.

```

## File: \architecture\16-Testing.md

```
# 16 - Testing

## Objetivo

Garantir confiabilidade do framework.

## Tipos

- Testes unitários
- Testes de integração
- Testes de Skills
- Testes de Providers
- Testes de conversação

## Validar

- Fluxo do Planner
- Conversation State
- Memory Engine
- Behavior Engine
- Prompt Engine

## Boas práticas

- Automatizar testes.
- Utilizar mocks para Providers.
- Cobrir cenários de erro.

```

## File: \architecture\17-Deployment.md

```
# 17 - Deployment

## Objetivo

Padronizar a implantação do Sopro.

## Ambientes

- Development
- Staging
- Production

## Configuração

- Variáveis de ambiente
- Providers
- Plugins
- Logging

## Checklist

- Configuração validada
- Providers disponíveis
- Observabilidade habilitada
- Testes executados

## Objetivo final

Permitir implantações reproduzíveis e seguras em qualquer ambiente.

```

## File: \examples\00-Conversation-Examples.md

```
# Conversation Examples
Versão: 1.0 (Draft)

## Objetivo

Apresentar exemplos completos de conversas que representam o comportamento esperado do Sopro.

---

# Cenário 1 - Coleta de informações

Usuário:
"Crie um ambiente Mercado."

Sopro:
"Qual é o endereço?"

Usuário:
"Av. Brasil, 1500."

Sopro:
"Ambiente criado."

---

# Cenário 2 - Interrupção e retomada

Usuário:
"Crie um lembrete."

Sopro:
"Sobre o que deseja ser lembrado?"

Usuário:
"Como está o clima?"

Sopro:
"Informa o clima."

Sopro:
"Voltando ao lembrete. Sobre o que deseja ser lembrado?"

---

# Cenário 3 - Referência contextual

Usuário:
"Renomeie para Mercado Central."

Sopro identifica o objeto da conversa atual sem solicitar nova identificação.

---

# Cenário 4 - Ambiguidade

Usuário:
"Crie um ambiente na Paulista."

Sopro:
"Encontrei várias opções. Qual delas você deseja utilizar?"

---

# Cenário 5 - Mudança de Skill

Usuário:
"Adicione leite à lista de compras."

Após concluir:

"Crie um lembrete para comprar amanhã."

Cada solicitação gera um novo plano no Planner, preservando a continuidade da conversa.

---

## Princípios demonstrados

- Aproveitamento de contexto.
- Mínimo de perguntas.
- Interrupções seguras.
- Retomada automática.
- Conversa natural.

```

## File: \examples\01-Examples-Home-Assistant.md

```
# Example - Home Assistant

Versão: 1.0 (Draft)

## Objetivo

Demonstrar o comportamento do Sopro quando a conversa ocorre dentro da tela principal.

---

## Princípios

- Fluxo guiado.
- Conversa contínua.
- Aproveitar contexto.
- Confirmar ações importantes.
- Retomar tarefas interrompidas.

---

## Exemplo 1 - Criar ambiente

Usuário:
"Crie um ambiente Mercado."

Sopro:
"Qual é o endereço?"

Usuário:
"Av. Brasil, 1500."

Sopro:
"Encontrei 'Av. Brasil, 1500'. Deseja utilizar este endereço?"

Usuário:
"Sim."

Sopro:
"Ambiente criado com sucesso."

---

## Exemplo 2 - Interrupção

Usuário:
"Crie um ambiente Academia."

Sopro:
"Qual é o endereço?"

Usuário:
"Como estará o clima amanhã?"

Sopro:
"Informa a previsão."

Sopro:
"Voltando ao ambiente Academia: qual é o endereço?"

---

## Exemplo 3 - Contexto

Usuário:
"Renomeie para Mercado Central."

O Sopro entende que o usuário está se referindo ao ambiente criado na conversa atual.

---

## Encerramento

No modo Home Assistant, o objetivo é concluir a tarefa com o menor esforço do usuário, mantendo contexto durante toda a conversa.

```

## File: \examples\02-Examples-Overlay.md

```
# Example - Overlay

Versão: 1.0 (Draft)

## Objetivo

Demonstrar o comportamento do Sopro quando iniciado pelo botão flutuante (Overlay).

---

## Princípios

- Fluxo rápido.
- Mínimo de perguntas.
- Não interromper o usuário.
- Não executar configurações complexas.

---

## Exemplo 1 - Criar ambiente

Usuário:
"Crie um ambiente Mercado."

Sopro:
"Ambiente 'Mercado' criado."

Observação:
Não pesquisa endereço automaticamente.

---

## Exemplo 2 - Lembrete

Usuário:
"Lembre-me de comprar leite."

Sopro:
"Quando devo lembrar você?"

---

## Exemplo 3 - Interrupção

Usuário:
"Como está o clima?"

Sopro responde e encerra a conversa.

---

## Encerramento

No modo Overlay, cada interação deve ser curta, objetiva e orientada à execução rápida.

```

## File: \skills\00-Create-Environment.md

```
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

```

## File: \skills\01-Update-Environment.md

```
# Skill - Update Environment
Versão: 1.0 (Draft)

## Objetivo

Atualizar informações de um ambiente existente.

---

## Responsabilidades

- Alterar nome.
- Alterar endereço.
- Alterar categoria.
- Alterar propriedades configuráveis.

---

## Não Responsabilidades

- Criar ambientes.
- Excluir ambientes.
- Executar automações.

---

## Entradas

| Campo | Obrigatório |
|--------|-------------|
| Ambiente | Sim |
| Alteração desejada | Sim |
| Novo valor | Sim |

---

## Estados

- WaitingEnvironment
- WaitingField
- WaitingValue
- Updating
- Completed
- Cancelled

---

## Fluxo

Receber intenção
↓

Identificar ambiente
↓

Identificar atributo
↓

Solicitar valor (se necessário)
↓

Validar
↓

Atualizar
↓

Confirmar alteração

---

## Tratamento de erros

- Ambiente inexistente.
- Valor inválido.
- Alteração não suportada.
- Cancelamento pelo usuário.

---

## Dependências

- Planner
- Conversation State
- Environment Repository

---

## Resultado

O ambiente é atualizado e as alterações ficam imediatamente disponíveis para o restante do sistema.

```

## File: \skills\02-Delete-Environment.md

```
# Skill - Delete Environment
Versão: 1.0 (Draft)

## Objetivo

Remover um ambiente existente do Sopro de forma segura.

---

## Responsabilidades

- Localizar o ambiente.
- Solicitar confirmação quando necessário.
- Excluir o ambiente.
- Garantir a consistência dos dados relacionados.

---

## Não Responsabilidades

- Criar ambientes.
- Editar ambientes.
- Restaurar ambientes excluídos.
- Executar automações.

---

## Entradas

| Campo | Obrigatório |
|--------|-------------|
| Ambiente | Sim |
| Confirmação | Sim |

---

## Estados

- WaitingEnvironment
- WaitingConfirmation
- Deleting
- Completed
- Cancelled

---

## Fluxo

Receber intenção
↓

Identificar ambiente
↓

Solicitar confirmação
↓

Excluir ambiente
↓

Retornar confirmação

---

## Tratamento de erros

- Ambiente inexistente.
- Ambiente em uso.
- Falha na exclusão.
- Cancelamento pelo usuário.

---

## Dependências

- Planner
- Conversation State
- Environment Repository

---

## Regras

- Exclusões devem exigir confirmação quando houver risco de perda de dados.
- A Skill deve informar claramente o impacto da exclusão.

---

## Resultado

O ambiente é removido do sistema e deixa de estar disponível para novas operações.

```

## File: \skills\03-Search-Address.md

```
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

```

## File: \skills\04-Weather.md

```
# Skill - Weather
Versão: 1.0 (Draft)

## Objetivo

Fornecer informações meteorológicas utilizando a localização informada ou inferida durante a conversa.

---

## Responsabilidades

- Consultar condições atuais.
- Consultar previsão.
- Interpretar referências como "aqui", "em casa" ou um ambiente salvo.
- Apresentar respostas em linguagem natural.

---

## Não Responsabilidades

- Salvar endereços.
- Criar ambientes.
- Emitir alertas automáticos.
- Monitorar mudanças climáticas continuamente.

---

## Entradas

| Campo | Obrigatório |
|--------|-------------|
| Localização | Não* |
| Data | Não |

*Quando omitida, a Skill tenta inferir a localização pelo contexto.

---

## Saídas

- Clima atual.
- Previsão para período solicitado.
- Solicitação de localização, quando necessária.

---

## Estados

- WaitingLocation
- ResolvingLocation
- FetchingWeather
- Completed
- Failed

---

## Fluxo

Receber solicitação
↓

Resolver localização
↓

Consultar serviço de clima
↓

Formatar resposta
↓

Responder ao usuário

---

## Tratamento de erros

- Localização desconhecida.
- Serviço indisponível.
- Data inválida.
- Consulta sem resultados.

---

## Dependências

- Planner
- Conversation State
- Search Address Skill (opcional)
- Weather Service

---

## Regras

- Reutilizar o contexto quando possível.
- Não perguntar novamente pela localização se ela já estiver disponível.
- Informar quando os dados estiverem desatualizados ou indisponíveis.

---

## Resultado

Disponibilizar informações meteorológicas de forma contextual e conversacional.

```

## File: \skills\05-Reminder.md

```
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

```

## File: \skills\06-Notification.md

```
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

```

## File: \skills\07-Shopping-List.md

```
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

```

## File: \skills\08-Routine.md

```
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

```

## File: \skills\09-Geofencing.md

```
# Skill - Geofencing
Versão: 1.0 (Draft)

## Objetivo

Executar ações quando o usuário entra, sai ou permanece em uma região geográfica.

---

## Responsabilidades

- Cadastrar regiões.
- Monitorar eventos de localização.
- Disparar Skills associadas.
- Ativar e desativar geofences.

---

## Não Responsabilidades

- Consultar endereços.
- Criar lembretes.
- Controlar dispositivos diretamente.

---

## Entradas

| Campo | Obrigatório |
|--------|-------------|
| Região | Sim |
| Raio | Sim |
| Evento (Entrar/Sair) | Sim |
| Ação | Sim |

---

## Estados

- WaitingRegion
- WaitingRadius
- WaitingAction
- Active
- Triggered
- Disabled
- Cancelled

---

## Fluxo

Receber solicitação
↓

Definir região
↓

Associar ação
↓

Salvar configuração
↓

Aguardar evento de localização
↓

Executar Skill configurada

---

## Tratamento de erros

- Região inválida.
- Permissão de localização negada.
- Evento duplicado.
- Falha ao executar a Skill.

---

## Dependências

- Planner
- Conversation State
- Geofencing Service
- Location Service
- Skill Registry

---

## Regras

- Toda ação deve estar vinculada a uma Skill.
- Evitar múltiplos disparos consecutivos para o mesmo evento.
- Respeitar permissões de localização do usuário.

---

## Resultado

Uma automação baseada em localização é criada e executada quando o evento geográfico ocorrer.

```
