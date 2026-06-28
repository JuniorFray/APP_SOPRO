-- Tabela de eventos do app Sopro enviados pelo AppLogger.
-- Execute no Supabase SQL Editor para criar a tabela antes de usar o AppLogger.

CREATE TABLE IF NOT EXISTS app_logs (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id   TEXT        NOT NULL,                  -- UUID gerado localmente no 1o uso
  event_type  TEXT        NOT NULL,                  -- Ex: geofence_enter, trigger_fired
  payload     JSONB       NOT NULL DEFAULT '{}',     -- Metadados do evento
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices para filtragem eficiente
CREATE INDEX IF NOT EXISTS idx_app_logs_device_id   ON app_logs(device_id);
CREATE INDEX IF NOT EXISTS idx_app_logs_event_type  ON app_logs(event_type);
CREATE INDEX IF NOT EXISTS idx_app_logs_created_at  ON app_logs(created_at);
