// Níveis de severidade disponíveis no Logger.
// Ordem crescente: trace < debug < info < warn < error < fatal.
enum LogLevel {
  trace,
  debug,
  info,
  warn,
  error,
  fatal;

  // Rótulo em maiúsculas para serialização e exibição.
  String get label => name.toUpperCase();
}
