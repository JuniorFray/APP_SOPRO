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

  // Onboarding — 4 passos que explicam o valor antes de pedir cada permissão
  static const obSkip   = 'Pular';
  static const obNext   = 'Próximo';
  static const obFinish = 'Ir para o app';

  // Passo 0: Boas-vindas
  static const obWelcomeTitle = 'Bem-vindo ao Sopro';
  static const obWelcomeBody  =
      'Imagine ter alguém que sussurra exatamente o que você precisa saber '
      'no momento em que você chega num lugar. É isso que o Sopro faz.';

  // Passo 1: Localização
  static const obLocationTitle = 'Memória de lugar';
  static const obLocationBody  =
      'Sopro detecta quando você entra num local salvo e aciona seus lembretes '
      'automaticamente. Seu GPS é usado apenas para geofences locais — '
      'nenhuma posição é enviada para servidores.';
  static const obLocationBtn   = 'Permitir localização';

  // Passo 2: Notificações
  static const obNotifTitle = 'Sussurros discretos';
  static const obNotifBody  =
      'As notificações são o meio pelo qual o Sopro fala com você — '
      'sem precisar abrir o app. Apenas seus lembretes. '
      'Nenhuma notificação de marketing.';
  static const obNotifBtn   = 'Permitir notificações';

  // Passo 3: Bluetooth
  static const obBleTitle = 'Pessoas ao redor';
  static const obBleBody  =
      'Detecta outros usuários Sopro próximos via Bluetooth e permite trocar '
      'cartões de contexto diretamente entre dispositivos — '
      'nada é enviado pela internet.';
  static const obBleBtn   = 'Permitir Bluetooth';

  // Tela de Perfil
  static const profileTitle          = 'Meu Perfil';
  static const profileName           = 'Nome';
  static const profileNameHint       = 'Como você quer ser chamado';
  static const profileRole           = 'Cargo';
  static const profileRoleHint       = 'Ex: Desenvolvedor, Designer, Estudante';
  static const profileCompany        = 'Empresa / Organização';
  static const profileCompanyHint    = 'Ex: Google, USP, Freelancer';
  static const profileInterests      = 'Interesses';
  static const profileInterestsHint  = 'Ex: tecnologia, música, café';
  static const profileNote           = 'Nota pessoal';
  static const profileNoteHint       = 'O que você está fazendo aqui? O que busca?';
  static const profileVisible        = 'Visível para outros';
  static const profileVisibleDesc    =
      'Outros usuários Sopro próximos poderão ver seu cartão via Bluetooth.';
  static const profileSave           = 'Salvar perfil';
  static const profileSaved          = 'Perfil salvo com sucesso!';
  static const profileNameRequired   = 'Informe pelo menos um nome';
  static const profileSectionIdentity   = 'Identidade';
  static const profileSectionContext    = 'Contexto';
  static const profileSectionPrivacy    = 'Privacidade';

  // Histórico de encontros BLE
  static const encountersTitle       = 'Encontros';
  static const encountersEmpty       = 'Nenhum encontro registrado';
  static const encountersEmptyHint   =
      'Usuários Sopro com quem você trocar cartões aparecem aqui';
  static const encounterDeleteBtn    = 'Remover';
  static const encounterClearAll     = 'Limpar histórico';
  static const encounterClearConfirm = 'Remover todos os encontros do histórico?';

  // Mapa de seleção de local
  static const mapTapInstruction = 'Toque no mapa para definir o local';
  static const useCurrentLocation = 'Usar localização atual';
  static const locationPermissionDenied =
      'Permissão de localização negada. Habilite nas configurações do dispositivo.';
  static const locationError =
      'Não foi possível obter sua localização. Tente novamente.';

  // Tela de Configurações
  static const settingsTitle          = 'Configurações';
  static const settingsTooltip        = 'Configurações';
  static const settingsBleSection     = 'Bluetooth Social';
  static const settingsBleVisible     = 'Visível para outros';
  static const settingsBleVisibleDesc =
      'Outros usuários Sopro próximos podem ver seu cartão via Bluetooth';
  static const settingsNotifSection     = 'Notificações';
  static const settingsNotifEnabled     = 'Notificações de gatilhos';
  static const settingsNotifEnabledDesc =
      'Receber sussurros ao entrar nos seus ambientes';
  static const settingsDataSection    = 'Dados';
  static const settingsMyProfile      = 'Meu perfil';
  static const settingsMyEncounters   = 'Encontros BLE';
  static const settingsAboutSection   = 'Sobre o Sopro';
  static const settingsVersion        = 'Versão';
  static const settingsAppVersion     = '0.1.0';
  static const settingsSourceCode     = 'github.com/JuniorFray/APP_SOPRO';
  static const settingsAppDesc        =
      '"O sussurro certo. No lugar certo." — memória física contextual, 100% on-device.';

  // Edição de ambiente e gatilho
  static const editEnvironmentTitle = 'Editar Ambiente';
  static const editTriggerTitle     = 'Editar Gatilho';
  static const editTooltip          = 'Editar';
}
