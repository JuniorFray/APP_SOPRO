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
