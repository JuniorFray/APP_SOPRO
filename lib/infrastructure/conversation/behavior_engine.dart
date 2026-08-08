import 'dart:math';

import '../../core/constants/strings.dart';
import '../../core/constants/voice_content.dart';
import '../personalization/user_name_store.dart';

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
  String chainOffer(String envName);      // oferta de encadear gatilho pós-criação
  String chainAskTrigger(String envName); // pergunta o que lembrar no ambiente novo
  String get chainDeclined;               // usuário recusou a oferta de encadeamento
  // Etapa 3.1 — completar em vez de falhar: pergunta qual ambiente/gatilho quando
  // o citado não casa. Cita candidatos quando houver; senão pergunta aberta.
  String clarifyEnvironment(String? attempted, List<String> candidates);
  String clarifyTrigger(List<String> candidates);
  String environmentRadiusUpdated(String name, Object? meters);
  String environmentAddressUpdated(String name); // endereço/coords atualizados
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
  String shoppingItemAdded(String name);
  String shoppingItemRemoved(String name);
  String shoppingItemChecked(String name);
  String shoppingItemNotFound(String name);
  String shoppingItemPresent(String name, bool checked); // consulta: sim (+status)
  String shoppingItemAbsent(String name);                // consulta: não
  String shoppingListPending(List<String> items);        // "o que falta comprar"
  String shoppingListChecked(List<String> items);        // "o que já peguei"
  String shoppingListAll(List<String> items);            // "o que tem na lista"
  String get shoppingMarketWhich;                        // vários mercados: qual?

  // ── Clima ────────────────────────────────────────────────────────────
  // Resposta falada do clima atual. Recebe primitivos (persona desacoplada do
  // WeatherService): temp/descrição + condição/umidade/chuva + hora (tom) +
  // [place] opcional (quando o usuário pergunta de outra cidade). Saudação vem
  // sempre à frente; sorteios dão variação de tom e de dicas.
  String weatherNow({
    required double temp,
    required String description,
    String? condition,
    int? humidity,
    int? popPercent,
    required int hour,
    String? place,
  });
  // Previsão dos próximos dias. [days] já vem pronto (label do dia + min/max +
  // condição em pt-BR) — a persona só monta a fala com tom variado.
  String weatherForecast(
    List<({String label, int min, int max, String cond})> days, {
    required int hour,
    String? place,
  });
  String get weatherNoLocation;          // sem GPS conhecido ainda
  String get weatherPlaceNotFound;       // lugar nomeado não encontrado
  String get weatherError;               // falha ao consultar o provedor
  String get weatherChecking;            // falado ANTES da consulta (espera)
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
      VoiceContent.persona('couldNotFinishRetry');
  @override
  String partialFailure(int failed) =>
      VoiceContent.persona('partialFailure').replaceAll('{failed}', '$failed');

  @override
  String get askEnvironmentName => 'Qual o nome do ambiente?';
  @override
  String get noEnvironmentsYet => VoiceContent.persona('noEnvironmentsYet');
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
  // Etapa 3.1 — tom por horário nas frases de SUCESSO: _toneOpener(hora) na
  // frente, substituindo a interjeição fixa antiga ("Pronto!/Anotado!") para não
  // empilhar. Núcleo da frase preservado.
  String environmentCreated(String name) =>
      '${_toneOpener(DateTime.now().hour)}'
      '${VoiceContent.persona('environmentCreated').replaceAll('{name}', name)}';
  @override
  String environmentCreatedReady(String name) =>
      '${_toneOpener(DateTime.now().hour)}Ambiente $name criado.';
  @override
  String environmentCreatedWithReminder(String envName, String title) =>
      '${_toneOpener(DateTime.now().hour)}'
      'Ambiente $envName criado com o lembrete $title.';
  @override
  String environmentCreatedWithReminders(String envName, int count) =>
      '${_toneOpener(DateTime.now().hour)}'
      'Ambiente $envName criado com $count lembrete${count == 1 ? '' : 's'}.';
  // Encadeamento (Etapa 2) — oferta/condução de criar um gatilho logo após criar
  // o ambiente. Variações dão tom natural (mesmo padrão de _pick do clima).
  @override
  String chainOffer(String envName) => _pick(Random(), [
        'Quer que eu crie um gatilho aqui em $envName também?',
        'Quer deixar algum lembrete pra quando chegar em $envName?',
        'Posso já anotar um lembrete pra $envName. Quer?',
      ]);
  @override
  String chainAskTrigger(String envName) => _pick(Random(), [
        'O que você quer lembrar em $envName?',
        'Beleza! O que eu te lembro quando chegar em $envName?',
      ]);
  @override
  String get chainDeclined => _pick(Random(), const [
        'Tá certo, fica pra próxima.',
        'Beleza, sem lembrete então.',
      ]);
  @override
  String environmentRadiusUpdated(String name, Object? meters) =>
      'Feito! Raio de $name atualizado para $meters metros.';
  @override
  // Tom por horário na frente (mesmo padrão das frases de sucesso).
  String environmentAddressUpdated(String name) =>
      '${_toneOpener(DateTime.now().hour)}Endereço de $name atualizado.';
  @override
  String environmentRemoved(String name) =>
      VoiceContent.persona('environmentRemoved').replaceAll('{name}', name);
  @override
  String environmentNotFound(String name) =>
      VoiceContent.persona('environmentNotFound').replaceAll('{name}', name);
  @override
  String environmentNotFoundCreate(String name) =>
      VoiceContent.persona('environmentNotFoundCreate').replaceAll('{name}', name);
  @override
  String clarifyEnvironment(String? attempted, List<String> candidates) =>
      candidates.isEmpty
          ? 'Não encontrei esse ambiente. Qual ambiente você quis dizer?'
          : 'Não encontrei esse ambiente. Você quis dizer ${_orList(candidates)}? '
              'Me diga qual.';
  @override
  String clarifyTrigger(List<String> candidates) => candidates.isEmpty
      ? 'Não achei esse lembrete. Qual lembrete você quis dizer?'
      : 'Não achei esse lembrete. Tem ${_orList(candidates)}. Qual deles?';

  @override
  String get reminderRemoved => VoiceContent.persona('reminderRemoved');
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
      '${_toneOpener(DateTime.now().hour)}'
      'Vou te lembrar de $title quando chegar em $envName.';
  @override
  String reminderResolved(String title) =>
      'Feito! Lembrete $title marcado como resolvido.';
  @override
  String noRemindersInYet(String envName) => 'Nenhum lembrete em $envName ainda.';
  @override
  String noRemindersIn(String envName) => 'Nenhum lembrete em $envName.';
  @override
  String allRemindersRemoved(String envName) =>
      VoiceContent.persona('allRemindersRemoved').replaceAll('{env}', envName);
  @override
  String remindersListed(int n, String envName, String titles) =>
      'Você tem $n lembrete${n == 1 ? '' : 's'} em $envName: $titles.';
  @override
  String confirmRemoveReminder(String label) =>
      'Você deseja remover o lembrete $label?';

  @override
  String get marketNoMarket => AppStrings.marketVoiceNoMarket;
  @override
  String shoppingItemAdded(String name) => _pick(Random(), [
        'Adicionei $name à lista.',
        'Anotei, $name vai pra lista.',
        'Pronto, $name está na lista de compras.',
      ]);
  @override
  String shoppingItemRemoved(String name) => 'Pronto, tirei $name da lista.';
  @override
  String shoppingItemChecked(String name) => 'Feito, marquei $name como pego.';
  @override
  String shoppingItemNotFound(String name) => 'Não encontrei $name na lista.';
  @override
  String shoppingItemPresent(String name, bool checked) => checked
      ? 'Sim, $name está na lista e você já pegou.'
      : 'Sim, $name está na lista, ainda falta pegar.';
  @override
  String shoppingItemAbsent(String name) => 'Não, $name não está na lista.';
  @override
  String shoppingListPending(List<String> items) => items.isEmpty
      ? 'Você já pegou tudo, não falta nada.'
      : 'Ainda falta: ${_andList(items)}.';
  @override
  String shoppingListChecked(List<String> items) => items.isEmpty
      ? 'Você ainda não marcou nada como pego.'
      : 'Você já pegou: ${_andList(items)}.';
  @override
  String shoppingListAll(List<String> items) => items.isEmpty
      ? 'A lista está vazia.'
      : 'Na lista tem: ${_andList(items)}.';
  @override
  String get shoppingMarketWhich => 'De qual mercado?';

  // Clima atual, resposta DINÂMICA: saudação (sempre à frente) + núcleo
  // (temp/descrição, com [place] quando é outra cidade) + comentário de chuva
  // conforme chance/condição + dica de conforto (sol/calor/frio/umidade).
  // Sorteios dão variação de tom e de dicas a cada consulta.
  @override
  String weatherNow({
    required double temp,
    required String description,
    String? condition,
    int? humidity,
    int? popPercent,
    required int hour,
    String? place,
  }) {
    final t = temp.round();
    final r = Random();
    final cond = (condition ?? '').toLowerCase();
    final loc = (place != null && place.isNotEmpty) ? ' em $place' : '';

    // Núcleo: temperatura + descrição, com frases variadas.
    final corePool = [
      'agora está $t graus$loc, com $description',
      'tá fazendo $t graus$loc, $description',
      'o tempo$loc está em $t graus, $description',
      'estão $t graus$loc, com $description',
    ];
    // Lead opcional com reticências: dá um respiro natural (pausa) na fala do TTS.
    final lead = _pick(r, ['', 'deixa eu ver... ', 'olha só... ', 'então... ']);
    final core = corePool[r.nextInt(corePool.length)];
    var msg = _greeting(hour, r) +
        (lead.isEmpty ? _capFirst(core) : _capFirst(lead) + core);

    // Chuva: comenta conforme a chance (pop) e a condição do OWM.
    final p = popPercent ?? 0;
    final rainy = cond.contains('rain') ||
        cond.contains('thunder') ||
        cond.contains('drizzle');
    if (p >= 60 || rainy) {
      msg += _pick(r, [
        '. Alta chance de chuva${p > 0 ? ' ($p%)' : ''}, leva o guarda-chuva',
        '. Vai chover${p > 0 ? ' ($p% de chance)' : ''}, não esquece o guarda-chuva',
        '. Tempo de chuva${p > 0 ? ' ($p%)' : ''}, melhor sair prevenido',
      ]);
    } else if (p >= 30) {
      msg += _pick(r, [
        '. Pode pintar uma chuva ($p%), vale levar guarda-chuva',
        '. Chance média de chuva ($p%)',
      ]);
    } else if (p > 0) {
      msg += '. Baixa chance de chuva ($p%)';
    } else if (r.nextBool()) {
      msg += '. Sem chuva à vista';
    }

    // Conforto: sol forte, calor, frio ou umidade alta.
    final clearDay = cond.contains('clear') && hour >= 6 && hour <= 17;
    if (t >= 32) {
      msg += _pick(r, ['. Tá quente, bebe bastante água', '. Calorão, se hidrata bem']);
      if (clearDay) {
        msg += _pick(r, [' e capricha no protetor solar', '. E cuidado com o sol']);
      }
    } else if (clearDay && t >= 26) {
      msg += _pick(r, [
        '. Sol forte, não esquece o protetor',
        '. Bastante sol lá fora, se protege dele',
      ]);
    } else if (t <= 15) {
      msg += _pick(r, ['. Tá frio, leva um casaco', '. Friozinho, se agasalha']);
    } else if (humidity != null && humidity >= 85) {
      msg += '. O ar está bem úmido';
    }

    return '$msg.';
  }

  // Previsão dos próximos dias — intro variada + um trecho por dia.
  @override
  String weatherForecast(
    List<({String label, int min, int max, String cond})> days, {
    required int hour,
    String? place,
  }) {
    if (days.isEmpty) return weatherError;
    final r = Random();
    final loc = (place != null && place.isNotEmpty) ? ' para $place' : '';
    final intro = _pick(r, [
      'Previsão$loc pros próximos dias: ',
      'Olha a previsão$loc: ',
      'Nos próximos dias$loc: ',
    ]);
    final parts = days
        .map((d) => '${d.label}, de ${d.min} a ${d.max} graus, ${d.cond}')
        .join('; ');
    return '${_greeting(hour, r)}$intro$parts.';
  }

  @override
  String get weatherNoLocation =>
      'Ainda não sei sua localização pra checar o tempo.';
  @override
  String get weatherPlaceNotFound =>
      'Não encontrei esse lugar pra ver o tempo.';
  @override
  String get weatherError => 'Não consegui checar o tempo agora.';
  // Falado antes de disparar a consulta (rede pode demorar) — variações dão tom
  // natural. Fala não-awaitada no call site: roda em paralelo com a busca.
  @override
  String get weatherChecking => _pick(Random(), const [
        'Só um instante, consultando o tempo...',
        'Deixa eu ver o clima pra você...',
        'Um momento, checando o tempo...',
      ]);
}

// Fachada do Behavior Engine — segura a persona ativa (hoje só a Assistant) e é
// o objeto que o resto do app consulta. Trocar de persona no futuro é trocar
// esta instância, sem mexer nos call sites.
class BehaviorEngine {
  final BehaviorPersona persona;
  const BehaviorEngine({this.persona = const AssistantPersona()});
}

// Capitaliza a 1ª letra (núcleo da frase de clima começa em minúscula).
String _capFirst(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

// Saudação pelo horário (sempre à frente da resposta de clima), com variação.
String _greeting(int hour, Random r) {
  // Faixas Etapa 3.1: manhã 6-11, comercial 11-19, noite 19-6 (madrugada inclusa).
  // Só as fronteiras mudaram; os pools (palavras da saudação) seguem iguais, então
  // weatherNow/weatherForecast continuam saudando normal — só desloca a hora.
  final pool = (hour >= 6 && hour < 11)
      ? ['Bom dia! ', 'Oi, bom dia! ', 'Opa! ']
      : (hour >= 11 && hour < 19)
          ? ['Boa tarde! ', 'Oi! ', 'Opa, boa tarde! ']
          : ['Boa noite! ', 'Oi! ', 'Opa! '];
  final greeting = pool[r.nextInt(pool.length)];
  // Personalização (Fase 3): quando há nome, insere-o na saudação em ALGUMAS
  // vezes (nextBool ~50%) — natural sem soar repetitivo. 'Bom dia! ' → 'Bom dia,
  // Fulano! '. Sem nome → saudação neutra, comportamento anterior intacto.
  final name = UserNameStore.current;
  if (name != null && r.nextBool()) {
    return greeting.replaceFirst('! ', ', $name! ');
  }
  return greeting;
}

// Etapa 3.1 (tom por horário) — abridor curto de tom para as frases de SUCESSO,
// pelas mesmas 3 faixas: manhã (6-11) acolhedor, comercial (11-19) objetivo/seco
// (às vezes vazio), noite (19-6) tranquilo. Separado de _greeting (que segue com
// saudação completa no clima) pra poder ser objetivo no comercial sem alterar o
// weatherNow/weatherForecast.
String _toneOpener(int hour) {
  final r = Random();
  if (hour >= 6 && hour < 11) {
    return _pick(r, const ['Bom dia! ', 'Oi, bom dia! ', 'Ótimo, bom dia! ']);
  }
  if (hour >= 11 && hour < 19) {
    return _pick(r, const ['', 'Certo! ', 'Feito! ']);
  }
  return _pick(r, const ['Boa noite! ', 'Tranquilo. ', 'Prontinho. ']);
}

// Junta itens em linguagem natural pt-BR: "A", "A ou B", "A, B ou C".
String _orList(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  return '${items.sublist(0, items.length - 1).join(', ')} ou ${items.last}';
}

// Sorteia um trecho de fala dentre variações (dá tom diferente a cada consulta).
String _pick(Random r, List<String> options) => options[r.nextInt(options.length)];

// Junta itens em linguagem natural pt-BR com "e": "A", "A e B", "A, B e C".
// Usado nas listas de compras faladas (leitura natural, não itens crus colados).
String _andList(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  return '${items.sublist(0, items.length - 1).join(', ')} e ${items.last}';
}
