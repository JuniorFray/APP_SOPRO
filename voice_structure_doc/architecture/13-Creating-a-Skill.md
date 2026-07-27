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
