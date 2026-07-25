import '../../core/constants/strings.dart';

// Behavior Engine — ponto ÚNICO de onde saem as respostas faladas do assistente.
//
// Formaliza voice_structure_doc/architecture/00-Behavior-Engine.md: centraliza
// tom/persona das respostas, mantendo as Skills focadas na lógica. Antes essas
// frases estavam soltas e espalhadas (literais em _speak(...) pelo home_tab).
//
// Estágio 6 (comportamento-preservado): NENHUM texto muda. Só se cria o ponto
// único — as frases inline viraram métodos da persona (texto verbatim) e as que
// já viviam em AppStrings passam a ser acessadas pela persona (fonte única de
// acesso). Assim, ajustar o tom depois é editar a persona, sem caçar string por
// string. A troca de persona (Minimal/Friendly/...) vem depois; hoje só existe
// a "Assistant" (padrão), idêntica ao comportamento atual.

// Contrato de uma persona: identidade + frases faladas. Interpolações e
// pluralizações são reproduzidas exatamente como estavam no código original.
abstract class BehaviorPersona {
  String get id;

  // ── Erros / não entendi ──────────────────────────────────────────────
  String get notUnderstood;              // 'Não entendi.'
  String get notUnderstoodRepeat;        // 'Não entendi, pode repetir?'
  String get notUnderstoodWhichRepeat;   // 'Não entendi qual. Pode repetir?'
  String get addressNotUnderstood;       // 'Não entendi o endereço.'
  String get didNotUnderstand;           // AppStrings.voiceDidNotUnderstand
  String get noSpeechHeard;              // AppStrings.voiceNoSpeechHeard
  String get operationCancelled;         // AppStrings.voiceOperationCancelled
  String get couldNotFinishRetry;        // 'Não consegui concluir agora. ...'
  String partialFailure(int failed);     // 'Fiz a maior parte. $failed ...'

  // ── Ambientes ────────────────────────────────────────────────────────
  String get askEnvironmentName;         // 'Qual o nome do ambiente?'
  String get noEnvironmentsYet;          // 'Você ainda não tem nenhum local ...'
  String get environmentNotFoundGeneric; // 'Não encontrei esse ambiente.'
  String get noEnvsToDelete;             // AppStrings.voiceNoEnvsToDelete
  String get allEnvsDeleted;             // AppStrings.voiceAllEnvsDeleted
  String environmentCount(int n);
  String alreadyHaveEnvironment(String name);
  String environmentCreated(String name);        // 'Ambiente $name criado.'
  String environmentCreatedReady(String name);    // 'Pronto! Ambiente $name criado.'
  String environmentCreatedWithReminder(String envName, String title);
  String environmentCreatedWithReminders(String envName, int count);
  String environmentRadiusUpdated(String name, Object? meters);
  String environmentRemoved(String name);
  String environmentNotFound(String name);        // sem "Quer criar agora?"
  String environmentNotFoundCreate(String name);  // com "Quer criar agora?"

  // ── Lembretes / gatilhos ─────────────────────────────────────────────
  String get reminderRemoved;            // 'Lembrete removido.'
  String get reminderNotFound;           // 'Não encontrei esse lembrete.'
  String get askPendingWhichEnv;         // 'Pendências de qual ambiente?'
  String get askWhichReminderTap;        // 'Qual lembrete você quer remover? ...'
  String get askWhichEnvToRemoveReminder;// 'De qual ambiente você quer remover ...'
  String reminderSaved(String title, String envName);
  String reminderResolved(String title);
  String noRemindersInYet(String envName);
  String noRemindersIn(String envName);
  String allRemindersRemoved(String envName);
  String remindersListed(int n, String envName, String titles);
  String confirmRemoveReminder(String label);

  // ── Compras ──────────────────────────────────────────────────────────
  String get marketNoMarket;             // AppStrings.marketVoiceNoMarket
}

// Persona padrão — reproduz exatamente o que o app já falava.
class AssistantPersona implements BehaviorPersona {
  const AssistantPersona();

  @override
  String get id => 'assistant';

  @override
  String get notUnderstood => 'Não entendi.';
  @override
  String get notUnderstoodRepeat => 'Não entendi, pode repetir?';
  @override
  String get notUnderstoodWhichRepeat => 'Não entendi qual. Pode repetir?';
  @override
  String get addressNotUnderstood => 'Não entendi o endereço.';
  @override
  String get didNotUnderstand => AppStrings.voiceDidNotUnderstand;
  @override
  String get noSpeechHeard => AppStrings.voiceNoSpeechHeard;
  @override
  String get operationCancelled => AppStrings.voiceOperationCancelled;
  @override
  String get couldNotFinishRetry =>
      'Não consegui concluir agora. Pode tentar de novo?';
  @override
  String partialFailure(int failed) => 'Fiz a maior parte. $failed não deram certo.';

  @override
  String get askEnvironmentName => 'Qual o nome do ambiente?';
  @override
  String get noEnvironmentsYet => 'Você ainda não tem nenhum local cadastrado.';
  @override
  String get environmentNotFoundGeneric => 'Não encontrei esse ambiente.';
  @override
  String get noEnvsToDelete => AppStrings.voiceNoEnvsToDelete;
  @override
  String get allEnvsDeleted => AppStrings.voiceAllEnvsDeleted;
  @override
  String environmentCount(int n) =>
      'Você tem $n local${n == 1 ? '' : 'is'} cadastrado${n == 1 ? '' : 's'}.';
  @override
  String alreadyHaveEnvironment(String name) => 'Você já tem o ambiente $name.';
  @override
  String environmentCreated(String name) => 'Ambiente $name criado.';
  @override
  String environmentCreatedReady(String name) => 'Pronto! Ambiente $name criado.';
  @override
  String environmentCreatedWithReminder(String envName, String title) =>
      'Anotado! Ambiente $envName criado com o lembrete $title.';
  @override
  String environmentCreatedWithReminders(String envName, int count) =>
      'Pronto! Ambiente $envName criado com '
      '$count lembrete${count == 1 ? '' : 's'}.';
  @override
  String environmentRadiusUpdated(String name, Object? meters) =>
      'Feito! Raio de $name atualizado para $meters metros.';
  @override
  String environmentRemoved(String name) => 'Ambiente $name removido.';
  @override
  String environmentNotFound(String name) => 'Não encontrei o ambiente $name.';
  @override
  String environmentNotFoundCreate(String name) =>
      'Não encontrei o ambiente $name. Quer criar agora?';

  @override
  String get reminderRemoved => 'Lembrete removido.';
  @override
  String get reminderNotFound => 'Não encontrei esse lembrete.';
  @override
  String get askPendingWhichEnv => 'Pendências de qual ambiente?';
  @override
  String get askWhichReminderTap =>
      'Qual lembrete você quer remover? Toque em um deles.';
  @override
  String get askWhichEnvToRemoveReminder =>
      'De qual ambiente você quer remover um lembrete?';
  @override
  String reminderSaved(String title, String envName) =>
      'Anotado! Vou te lembrar de $title quando chegar em $envName.';
  @override
  String reminderResolved(String title) =>
      'Feito! Lembrete $title marcado como resolvido.';
  @override
  String noRemindersInYet(String envName) => 'Nenhum lembrete em $envName ainda.';
  @override
  String noRemindersIn(String envName) => 'Nenhum lembrete em $envName.';
  @override
  String allRemindersRemoved(String envName) =>
      'Todos os lembretes de $envName removidos.';
  @override
  String remindersListed(int n, String envName, String titles) =>
      'Você tem $n lembrete${n == 1 ? '' : 's'} em $envName: $titles.';
  @override
  String confirmRemoveReminder(String label) =>
      'Você deseja remover o lembrete $label?';

  @override
  String get marketNoMarket => AppStrings.marketVoiceNoMarket;
}

// Fachada do Behavior Engine — segura a persona ativa (hoje só a Assistant) e é
// o objeto que o resto do app consulta. Trocar de persona no futuro é trocar
// esta instância, sem mexer nos call sites.
class BehaviorEngine {
  final BehaviorPersona persona;
  const BehaviorEngine({this.persona = const AssistantPersona()});
}
