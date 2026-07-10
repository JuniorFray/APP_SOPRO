package com.sopro.sopro.logging

// Níveis de severidade. Ordem crescente: TRACE < DEBUG < INFO < WARN < ERROR < FATAL.
// ordinal do enum reflete a ordem — usado em shouldEmit() do Logger.
enum class LogLevel(val label: String) {
    TRACE("TRACE"),
    DEBUG("DEBUG"),
    INFO("INFO"),
    WARN("WARN"),
    ERROR("ERROR"),
    FATAL("FATAL"),
}
