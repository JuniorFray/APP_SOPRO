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
