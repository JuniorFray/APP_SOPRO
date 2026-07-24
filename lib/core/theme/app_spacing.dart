/// Escala de espaçamento e dimensões fixas do Sopro (grade de 4pt).
/// Use para padding, margin, gap e SizedBox — não declare valores numéricos
/// diretamente nos widgets.
abstract final class AppSpacing {
  // ── Escala principal (grade 4pt) ───────────────────────────────────────────
  static const double xxs =  4;   // gaps mínimos e margem de botão secundário
  static const double xs  =  8;   // gaps entre ícone e texto, separadores
  static const double sm  = 12;   // padding interno de containers menores
  static const double md  = 16;   // padding horizontal padrão de tela
  static const double lg  = 20;   // padding horizontal de sheets
  static const double xl  = 24;   // padding horizontal do rodapé de onboarding
  static const double xxl = 32;   // padding horizontal das páginas de onboarding

  // ── Ritmo de seções (dashboards / telas com blocos titulados) ──────────────
  static const double section  = 32;  // espaço vertical fixo ENTRE seções
  static const double titleGap  = 12;  // espaço entre título de seção e conteúdo

  // ── Valores fora da grade usados nas telas ─────────────────────────────────
  static const double gap6  =  6;  // gap título→subtitle em sheets e cards
  static const double gap10 = 10;  // padding lateral da barra de busca
  static const double gap14 = 14;  // padding vertical de botões (ElevatedButton)
  static const double gap36 = 36;  // gap pós-ícone nas páginas de onboarding

  // ── Dimensões de componentes ───────────────────────────────────────────────
  static const double iconContainerSm = 36;  // containers de ícone nos pickers
  static const double iconContainerMd = 40;  // containers de ícone em Settings
  static const double iconContainerLg = 44;  // leading dos cards de ambiente
  static const double fab             = 64;  // diâmetro do FAB de voz
  static const double onboardingIcon  = 88;  // container do ícone no onboarding
}
