/// Raios de borda do Sopro.
/// Todos os BorderRadius.circular() devem referenciar esta classe.
abstract final class AppRadius {
  static const double none   =  0;
  static const double xs     =  2;  // dots de progresso, drag handles
  static const double sm     =  4;  // indicadores de passo do onboarding
  static const double md     =  8;  // snackbars, container de busca de endereço
  static const double lg     = 10;  // caixas de aviso, containers de ícone em Settings
  static const double icon   = 12;  // containers de emoji dos cards de ambiente
  static const double input  = 14;  // campos de texto (TextFormField)
  static const double card   = 20;  // cards — premium radius, consistente com button
  static const double button = 20;  // botões ElevatedButton e badges
  static const double badge  = 20;  // alias semântico de button para pills e chips
  static const double sheet  = 24;  // topo dos bottom sheets (BorderRadius.vertical)
}
