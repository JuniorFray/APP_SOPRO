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
