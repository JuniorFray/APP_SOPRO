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
