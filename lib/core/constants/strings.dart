// Todas as strings visíveis ao usuário centralizadas aqui.
// NUNCA use strings hardcoded em widgets — importe esta classe.
class AppStrings {
  AppStrings._();

  // Geral
  static const appName = 'Sopro';
  static const tagline = '"O sussurro certo. No lugar certo."';
  static const cancel = 'Cancelar';
  static const undo   = 'Desfazer';
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
  static const bleWhatsApp             = 'Conversar no WhatsApp';
  static const bleWhatsAppError        = 'Não foi possível abrir o WhatsApp';

  // Onboarding — 4 passos que explicam o valor antes de pedir cada permissão
  static const obSkip          = 'Pular';
  static const obNext          = 'Próximo';
  static const obFinish        = 'Ir para o app';
  static const obContinueAnyway = 'Continuar assim mesmo';

  // Passo 0: Boas-vindas
  static const obWelcomeTitle = 'Bem-vindo ao Sopro';
  static const obWelcomeBody  =
      'Imagine ter alguém que sussurra exatamente o que você precisa saber '
      'no momento em que você chega num lugar. É isso que o Sopro faz.';

  // Passo 1: Localização
  static const obLocationTitle = 'Memória de lugar';
  static const obLocationBody  =
      'Sopro detecta quando você entra num lugar cadastrado e aciona seus lembretes '
      'automaticamente. Seu GPS fica no dispositivo — '
      'nenhuma posição é enviada para servidores.';
  static const obLocationBtn   = 'Permitir localização';

  // Passo 2: Notificações
  static const obNotifTitle = 'Sussurros discretos';
  static const obNotifBody  =
      'As notificações são o meio pelo qual o Sopro fala com você — '
      'sem precisar abrir o app. Apenas seus lembretes. '
      'Nenhuma notificação de marketing.';
  static const obNotifBtn    = 'Permitir notificações';
  // Exibida quando o usuário nega a permissão de notificações
  static const obNotifDenied =
      'Sem notificações, o Sopro não consegue entregar seus sussurros. '
      'Você pode habilitar depois em Configurações do sistema.';

  // Passo 3: Bluetooth
  static const obBleTitle = 'Pessoas ao redor';
  static const obBleBody  =
      'Detecta outros usuários Sopro próximos e permite trocar '
      'cartões diretamente entre dispositivos — '
      'nada é enviado pela internet.';
  static const obBleBtn    = 'Permitir Bluetooth';
  // Exibida quando o usuário nega as permissões BLE
  static const obBleDenied =
      'Sem Bluetooth, a função "Pessoas aqui" não estará disponível. '
      'Você pode habilitar depois nas Configurações do dispositivo.';

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
  static const profilePhone          = 'WhatsApp / Telefone';
  static const profilePhoneHint      = 'Ex: 11999998888 (apenas dígitos)';
  static const profileSectionContact = 'Contato';
  static const profileVisible        = 'Visível para outros';
  static const profileVisibleDesc    =
      'Outros usuários Sopro próximos poderão ver seu cartão.';
  static const profileSave           = 'Salvar perfil';
  static const profileSaved          = 'Perfil salvo com sucesso!';
  static const profileNameRequired   = 'Informe pelo menos um nome';
  static const profileSectionIdentity   = 'Identidade';
  static const profileSectionContext    = 'Contexto';
  static const profileSectionPrivacy    = 'Privacidade';

  // Histórico de encontros BLE
  static const encountersTitle       = 'Pessoas que encontrei';
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

  // Busca de endereço por Nominatim (OpenStreetMap)
  static const searchAddressHint = 'Buscar endereço ou lugar...';
  static const searchError = 'Não foi possível buscar o endereço. Tente novamente.';

  // Tela de Configurações
  static const settingsTitle          = 'Configurações';
  static const settingsTooltip        = 'Configurações';
  static const settingsBleSection     = 'Pessoas próximas';
  static const settingsBleVisible     = 'Visível para outros';
  static const settingsBleVisibleDesc =
      'Outros usuários Sopro próximos podem ver seu cartão';
  static const settingsBleTxPower     = 'Alcance de detecção';
  static const settingsBleTxPowerDesc = 'Distância aproximada de detecção por outros';
  static const bleTxPowerMin          = 'Mínima ~2m';
  static const bleTxPowerLow          = 'Baixa ~5m';
  static const bleTxPowerMed          = 'Média ~10m';
  static const bleTxPowerHigh         = 'Alta ~20m+';
  static const settingsNotifSection     = 'Notificações';
  static const settingsNotifEnabled     = 'Notificações de gatilhos';
  static const settingsNotifEnabledDesc =
      'Receber sussurros ao entrar nos seus ambientes';
  static const settingsDataSection    = 'Dados';
  static const settingsMyProfile      = 'Meu perfil';
  static const settingsMyEncounters   = 'Pessoas que encontrei';
  static const settingsAboutSection   = 'Sobre o Sopro';
  static const settingsVersion        = 'Versão';
  static const settingsAppVersion     = '0.1.0';
  static const settingsSourceCode     = 'github.com/JuniorFray/APP_SOPRO';
  static const settingsAppDesc        =
      '"O sussurro certo. No lugar certo." — memória física contextual, 100% on-device.';

  // Notificações avançadas (som e frequência)
  static const settingsNotifSound        = 'Som nas notificações';
  static const settingsNotifSoundDesc    = 'Toca som ao receber um sussurro';
  static const settingsNotifCooldown     = 'Frequência';
  static const settingsNotifCooldownDesc = 'Intervalo mínimo entre notificações';

  // Perfil — foto
  static const profilePhotoTooltip = 'Alterar foto do perfil';
  // Bottom sheet de seleção de fonte da foto
  static const profilePhotoOptions = 'Foto do perfil';
  static const profilePhotoCamera  = 'Tirar foto';
  static const profilePhotoGallery = 'Escolher da galeria';

  // Toggle de compartilhamento de WhatsApp (Perfil — seção Privacidade)
  static const profileShareWhatsApp     = 'Compartilhar WhatsApp';
  static const profileShareWhatsAppDesc =
      'Inclui seu número no cartão trocado com pessoas próximas';
  static const profilePhoneHelperOn  = 'Será incluído no seu cartão';
  static const profilePhoneHelperOff = 'Salvo, mas não compartilhado';

  // Edição de ambiente e gatilho
  static const editEnvironmentTitle = 'Editar Ambiente';
  static const editTriggerTitle     = 'Editar Gatilho';
  static const editTooltip          = 'Editar';

  // ── Voz (Sprint V2-Voz) ─────────────────────────────────────────────────
  static const voiceSection            = 'Interação por voz';
  static const voiceAudioResponse      = 'Resposta em áudio';
  static const voiceAudioResponseDesc  = 'Sopro fala a confirmação da ação reconhecida';
  static const voiceTextResponse       = 'Resposta em texto';
  static const voiceTextResponseDesc   = 'Exibe a confirmação na tela';
  static const voiceSpeechRate         = 'Velocidade da fala';
  static const voiceRateSlow           = 'Lenta';
  static const voiceRateNormal         = 'Normal';
  static const voiceRateFast           = 'Rápida';
  // Sprint V2-GeminiAudio: gravação substituiu STT on-device
  static const voiceListeningTitle     = 'Gravando...';
  static const voiceListeningHint      = 'Solte para processar';
  static const voiceHoldToSpeak        = 'Segure o botão para falar';
  static const voiceResultTitle        = 'Ação reconhecida';
  static const voiceConfirm            = 'Confirmar';
  static const voiceRetry              = 'Tentar novamente';
  static const voiceClose              = 'Fechar';
  static const voiceNotAvailable       = 'Reconhecimento de voz não disponível neste dispositivo';
  static const voicePermissionDenied   = 'Permissão de microfone necessária para usar a voz';
  static const voiceExamples           =
      '"Lembra de ligar para o médico quando eu chegar em casa"\n'
      '"Cria um ambiente aqui chamado Mercado"\n'
      '"O que tenho pendente em Trabalho?"';
  static const voiceIntentCreate       = 'Criar gatilho';
  static const voiceIntentEnv          = 'Criar ambiente';
  static const voiceIntentResolve      = 'Marcar como resolvido';
  static const voiceIntentList         = 'Ver pendências do ambiente';
  static const voiceIntentFallback     = 'Criar gatilho com texto livre';
  static const voiceMicTooltip         = 'Falar';
  static const voiceFillHint           = 'Ditando...';
  // Exibido enquanto o Gemini processa a transcrição (spinner)
  static const voiceProcessing         = 'Processando...';
  // Label do campo editável de transcrição no estado de resultado
  static const voiceTranscriptLabel    = 'O que você disse';
  // Tooltip do botão de re-análise no campo de transcrição
  static const voiceReanalyze         = 'Re-analisar';

  // ── Voz — fluxo sem confirmação (Sprint V2-VoicePro) ─────────────────────
  // Prefixo do snackbar de sucesso ao criar gatilho por voz
  static const voiceTriggerSavedIn     = 'Gatilho criado em';
  // Mensagem ao desativar gatilho por voz
  static const voiceTriggerDeactivated = 'Desativado';
  // Mensagem quando o gatilho não é encontrado para resolução
  static const voiceTriggerNotFound    = 'Gatilho não encontrado';
  // Título do seletor de ambiente quando o Gemini não encontra o local
  static const voiceEnvPickerTitle     = 'Em qual ambiente?';
  // Título do seletor quando o usuário pede pendências de um local
  static const voiceEnvPickerAction    = 'Pendências de qual ambiente?';
  // Título da lista inline de gatilhos (listar_triggers)
  static const voiceTriggerListTitle   = 'Pendências';
  // Exibido quando o ambiente não tem gatilhos ativos
  static const voiceNoTriggersPending  = 'Nenhum gatilho ativo neste ambiente';

  // ── Onboarding — passo 4: overlay (V3) ───────────────────────────────────
  // Passo opcional que informa sobre o botão flutuante global previsto para V3
  static const obOverlayTitle = 'Acesso rápido (em breve)';
  static const obOverlayBody  =
      'Na próxima versão, o Sopro terá um botão flutuante que aparece em '
      'qualquer tela do celular — sem precisar abrir o app. '
      'Você pode habilitar essa permissão agora ou depois nas Configurações.';
  static const obOverlayBtn   = 'Entendido';

  // ── Voz — novos intents (Sprint V2-VoicePro Etapa 1) ─────────────────────
  // Tooltip exibido ao tocar rapidamente o botão (sem segurar)
  static const voiceHoldToRecord   = 'Segure para gravar';
  // Exibido quando o usuário solta antes de 500 ms (gravação muito curta)
  static const voiceHoldLonger     = 'Segure por mais tempo para gravar';

  // ── Voz — FIX 1/2 (auto-save GPS + env not found) ────────────────────────
  // Prefixo do snackbar ao criar ambiente por voz via GPS
  static const voiceEnvCreated          = 'Ambiente criado';
  // Snackbar quando ambiente E gatilho são criados juntos
  static const voiceEnvAndTriggerCreated = 'Ambiente e gatilho salvos';
  // Fragmento usado no título do sheet quando ambiente não existe
  static const voiceEnvNotExists        = 'ainda não existe';
  // Botão primário do sheet "ambiente não existe"
  static const voiceCreateEnvNow        = 'Criar ambiente agora';
  // Botão secundário do sheet "ambiente não existe"
  static const voiceChooseOther         = 'Escolher outro';
  // Título do sheet que lista todos os ambientes (list_environments)
  static const voiceEnvListTitle   = 'Meus locais';
  // Prefixo do snackbar ao atualizar ambiente por voz
  static const voiceEnvUpdated     = 'Ambiente atualizado';
  // Lembrete exibido após abrir AddEnvironmentScreen via create_environment_with_trigger
  static const voicePendingTriggers = 'Após salvar, adicione o gatilho:';

  // ── Voz — exclusão por voz (Sprint V2-VoicePro-Etapa3) ───────────────────
  // Título do sheet de confirmação para excluir ambiente
  static const voiceDeleteEnvTitle   = 'Excluir ambiente?';
  // Confirmação excluída de todos gatilhos do ambiente
  static const voiceDeleteAllTitle   = 'Remover todos os gatilhos?';
  // Título do picker quando múltiplos triggers correspondem à busca
  static const voiceDeletePickerTitle = 'Qual desses você quer remover?';
  // Snackbar após excluir ambiente com sucesso
  static const voiceEnvDeleted       = 'Ambiente excluído';
  // Snackbar após remover gatilho individual com sucesso
  static const voiceTriggerDeleted   = 'Gatilho removido';
  // Snackbar após remover todos os gatilhos de um ambiente
  static const voiceAllTriggersDeleted = 'Gatilhos removidos';
  // Snackbar quando o gatilho buscado não é encontrado
  static const voiceTriggerDeleteNotFound = 'Gatilho não encontrado. Tente outro nome.';
  // Snackbar quando o ambiente não é encontrado para exclusão
  static const voiceEnvNotFoundForDelete  = 'Ambiente não encontrado';
}
