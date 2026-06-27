// Todas as strings visíveis ao usuário centralizadas aqui.
// NUNCA use strings hardcoded em widgets — importe esta classe.
class AppStrings {
  AppStrings._();

  // Geral
  static const appName = 'Sopro';
  static const tagline = '"O sussurro certo. No lugar certo."';
  static const cancel = 'Cancelar';
  static const save = 'Salvar';
  static const delete = 'Excluir';
  static const confirm = 'Confirmar';
  static const errorGeneric = 'Algo deu errado. Tente novamente.';

  // Home
  static const homeTitle = 'Sopro';
  static const profileTooltip = 'Perfil';
  static const newEnvironment = 'Novo Ambiente';
  static const homeEmptyTitle = 'Nenhum ambiente ainda';
  static const homeEmptySubtitle =
      'Crie um local para começar a receber sussurros';

  // Environments
  static const addEnvironmentTitle = 'Novo Ambiente';
  static const environmentNameLabel = 'Nome do local';
  static const environmentNameHint = 'Ex: Casa, Trabalho, Academia';
  static const latitudeLabel = 'Latitude';
  static const longitudeLabel = 'Longitude';
  static const radiusLabel = 'Raio (metros)';
  static const radiusDefault = '100';
  static const environmentNameRequired = 'Informe o nome do local';
  static const latitudeInvalid = 'Latitude inválida (-90 a 90)';
  static const longitudeInvalid = 'Longitude inválida (-180 a 180)';
  static const radiusInvalid = 'Raio deve ser maior que 0';
  static const environmentDeleteConfirm =
      'Excluir este ambiente e todos os seus gatilhos?';
  static const triggers = 'gatilhos';
  static const noTriggers = 'sem gatilhos';

  // Triggers CRUD
  static const addTrigger            = 'Novo Gatilho';
  static const triggerTitleLabel     = 'Título do gatilho';
  static const triggerTitleHint      = 'Ex: Levar documento, Comprar leite';
  static const triggerContentLabel   = 'Conteúdo';
  static const triggerContentHint    = 'Detalhe o que você precisa lembrar...';
  static const triggerTitleRequired  = 'Informe o título do gatilho';
  static const triggerContentRequired = 'Informe o conteúdo do gatilho';
  static const triggerDeleteConfirm  = 'Excluir este gatilho?';
  static const triggersSection       = 'Gatilhos';
  static const noTriggersYet         = 'Sem gatilhos ainda';
  static const noTriggersHint        = 'Toque em + para adicionar o primeiro';

  // Background service
  static const backgroundServiceTitle   = 'Sopro ativo';
  static const backgroundServiceContent = 'Monitorando seus ambientes em segundo plano';

  // BLE Social — "Pessoas Aqui"
  static const peopleNearby            = 'Pessoas Aqui';
  static const bleScanning             = 'Procurando usuários Sopro próximos...';
  static const bleNoUsers              = 'Ninguém por aqui ainda';
  static const bleNoUsersHint          = 'Outros usuários Sopro aparecerão aqui';
  static const blePermissionDenied     = 'Permissão Bluetooth negada. Habilite nas configurações.';
  static const bleNotSupported         = 'Bluetooth não disponível neste dispositivo.';
  static const bleCardLoading          = 'Carregando cartão...';
  static const bleCardError            = 'Não foi possível carregar o cartão deste usuário.';
  static const bleUserLabel            = 'Usuário Sopro';
  static const bleAdvertising          = 'Visível para outros';
  static const bleNotAdvertising       = 'Invisível';
  static const bleSignalStrong         = 'Perto';
  static const bleSignalMedium         = 'Médio';
  static const bleSignalWeak           = 'Longe';
  static const bleNoProfileWarning     = 'Configure seu perfil para ser visto por outros';
  static const bleViewCard             = 'Ver cartão';
  static const bleClose                = 'Fechar';

  // Mapa de seleção de local
  static const mapTapInstruction = 'Toque no mapa para definir o local';
  static const useCurrentLocation = 'Usar localização atual';
  static const locationPermissionDenied =
      'Permissão de localização negada. Habilite nas configurações do dispositivo.';
  static const locationError =
      'Não foi possível obter sua localização. Tente novamente.';
}
