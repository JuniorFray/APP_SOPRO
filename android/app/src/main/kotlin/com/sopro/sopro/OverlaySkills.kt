package com.sopro.sopro

import com.sopro.sopro.logging.Logger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// OverlaySkills — Estágio 2 da reorganização do overlay de voz.
//
// Uma Skill por ação. Absorve o corpo de lógica que antes vivia espalhado entre
// executePlan, executeVoiceResult, routeDestructiveConfirm e
// performConfirmedDestructive, de modo que os 4 pontos passem a chamar A MESMA
// função. Espelha as Skills do lado Dart (voice_skills.dart).
//
// COMPORTAMENTAL-PRESERVADO: cada corpo aqui é cópia byte-a-byte da lógica que
// substitui (SQLite via helpers do serviço, mesma resposta falada, mesmos logs).
// As diferenças legítimas de contexto entre pipelines (ex.: prompt de parâmetro
// faltando com prosódia distinta) permanecem no chamador, não aqui.
//
// Os helpers de DB/fala do FloatingVoiceService continuam private: chegam aqui só
// como referências de função dentro do OverlaySkillContext (montado 1x no serviço).

// Dependências que as Skills usam. Montado uma vez pelo FloatingVoiceService.
class OverlaySkillContext(
    val scope: CoroutineScope,
    val writeEnvironment: (name: String, lat: Double, lon: Double, radius: Int) -> Boolean,
    val writeTrigger: (title: String, content: String, env: String) -> Boolean,
    val writeShopping: (items: List<String>, market: String) -> Boolean,
    // Etapa 2 — atualizações e lembrete por tempo (nativo, sem Flutter Engine).
    val updateTrigger: (env: String, title: String, newTitle: String?, content: String?) -> Boolean,
    val updateEnvironment: (name: String, radius: Int?) -> Boolean,
    // createReminder escreve o lembrete E agenda o alarme (ReminderScheduler).
    val createReminder: (title: String, scheduledAtMillis: Long, repeatRule: String,
                         repeatDays: String, alertMode: String) -> Boolean,
    val deleteEnvironment: (env: String) -> Boolean,
    val deleteTrigger: (env: String, title: String?) -> Boolean,
    val deleteAllEnvironments: () -> Int,
    val isBlockedName: (name: String) -> Boolean,
    val speak: (text: String) -> Unit,
    val endVoice: () -> Unit,
    val correlationId: () -> String?,
)

// ── Construtivas ─────────────────────────────────────────────────────────────

// Cria ambiente na localização já resolvida (GPS do plano). Corpo idêntico ao
// branch create_environment do loop de executePlan. Síncrono: roda DENTRO do loop
// IO do plano e devolve sucesso/falha (a fala é o resumo agregado do plano).
object CreateEnvironmentSkill {
    fun execute(name: String?, lat: Double, lon: Double, ctx: OverlaySkillContext): Boolean = when {
        name == null || ctx.isBlockedName(name) -> false
        lat == 0.0 && lon == 0.0                -> false // sem GPS não cria
        else -> ctx.writeEnvironment(name, lat, lon, 100)
    }
}

// Grava gatilho se ambiente e título presentes. Kernel único de escrita de
// gatilho, usado pelo loop de executePlan E pelo caminho legado create_trigger.
// content já chega com default "". Síncrono (chamado em IO).
object CreateTriggerSkill {
    fun execute(env: String?, title: String?, content: String, ctx: OverlaySkillContext): Boolean =
        if (env != null && title != null) ctx.writeTrigger(title, content, env) else false
}

// Grava itens no mercado escolhido. Kernel único de escrita de compras, usado
// pelo caminho de 1 mercado e pela confirmação de escolha de mercado. Síncrono.
object AddShoppingItemSkill {
    fun execute(items: List<String>, market: String, ctx: OverlaySkillContext): Boolean =
        ctx.writeShopping(items, market)
}

// ── Atualizações + lembrete por tempo (Etapa 2) ──────────────────────────────
// Espelham UpdateTriggerSkill / UpdateEnvironmentSkill / CreateReminderSkill do
// lado Dart (voice_skills.dart). Síncronas: rodam DENTRO do loop IO do plano e
// devolvem sucesso/falha (a fala é o resumo agregado do plano).

// Atualiza um lembrete existente (título e/ou conteúdo) por match parcial de título.
object UpdateTriggerSkill {
    fun execute(env: String?, title: String?, newTitle: String?, content: String?,
                ctx: OverlaySkillContext): Boolean =
        if (env != null && title != null) ctx.updateTrigger(env, title, newTitle, content)
        else false
}

// Atualiza um ambiente (por ora, o raio) e re-registra o geofence.
object UpdateEnvironmentSkill {
    fun execute(name: String?, radius: Int?, ctx: OverlaySkillContext): Boolean =
        if (name != null) ctx.updateEnvironment(name, radius) else false
}

// Cria um lembrete por TEMPO (data/hora), sem vínculo com localização.
// Faz o parse dos campos do Gemini (mesma semântica do CreateReminderSkill Dart)
// e delega a escrita+agendamento ao contexto (writeReminderToDb + ReminderScheduler).
object CreateReminderSkill {
    // internal: recebe PlanAction (tipo internal do serviço) — mesmo módulo.
    internal fun execute(a: FloatingVoiceService.PlanAction, ctx: OverlaySkillContext): Boolean {
        val title = a.str("title") ?: return false
        val date = a.str("date") ?: return false
        val time = a.str("time") ?: return false
        val millis = parseReminderMillis(date, time) ?: return false
        // Default "daily": lembrete sem mencao de repeticao vale todos os dias.
        val repeat = when (a.str("repeat_rule") ?: "daily") {
            "daily" -> "daily"; "weekly" -> "weekly"; else -> "none"
        }
        val days = a.str("repeat_days_of_week") ?: ""
        val alert = when (a.str("alert_mode") ?: "notification") {
            "alarm" -> "alarm"; "both" -> "both"; else -> "notification"
        }
        return ctx.createReminder(title, millis, repeat, days, alert)
    }

    // "AAAA-MM-DD" + "HH:mm" -> epoch millis (hora local). null se formato inválido.
    private fun parseReminderMillis(date: String, time: String): Long? = try {
        val d = date.split("-").map { it.toInt() }
        val t = time.split(":").map { it.toInt() }
        val cal = java.util.Calendar.getInstance()
        cal.set(d[0], d[1] - 1, d[2], t[0], t[1], 0)
        cal.set(java.util.Calendar.MILLISECOND, 0)
        cal.timeInMillis
    } catch (e: Exception) {
        null
    }
}

// ── Destrutivas ──────────────────────────────────────────────────────────────
// Cada uma expõe question() (string de confirmação, antes duplicada entre
// executeVoiceResult e routeDestructiveConfirm) e perform() (execução real, antes
// só em performConfirmedDestructive: IO → DB → log → fala → encerra o ciclo).

object DeleteEnvironmentSkill {
    fun question(env: String) = "Você deseja excluir o ambiente $env?"

    fun perform(env: String, ctx: OverlaySkillContext) {
        ctx.scope.launch(Dispatchers.IO) {
            val ok = ctx.deleteEnvironment(env)
            withContext(Dispatchers.Main) {
                if (ok) {
                    Logger.info("command_executed", feature = "floating_voice",
                        action = "execute", payload = mapOf("command" to "delete_environment"),
                        correlationId = ctx.correlationId())
                    ctx.speak(OverlayPersona.environmentRemoved(env))
                } else ctx.speak(OverlayPersona.environmentNotFound(env))
                ctx.endVoice()
            }
        }
    }
}

object DeleteAllEnvironmentsSkill {
    fun question() = "Você deseja excluir todos os ambientes e seus lembretes?"

    fun perform(ctx: OverlaySkillContext) {
        ctx.scope.launch(Dispatchers.IO) {
            val count = ctx.deleteAllEnvironments()
            withContext(Dispatchers.Main) {
                if (count > 0) {
                    Logger.info("command_executed", feature = "floating_voice",
                        action = "execute",
                        payload = mapOf("command" to "delete_all_environments",
                            "count" to count.toString()),
                        correlationId = ctx.correlationId())
                    ctx.speak(OverlayPersona.allEnvironmentsRemoved)
                } else ctx.speak(OverlayPersona.noEnvironmentsYet)
                ctx.endVoice()
            }
        }
    }
}

object DeleteTriggerSkill {
    // [removeAll] decidido pelo chamador — cada pipeline tem sua própria condição
    // (isNullOrEmpty vs == null). Só a STRING é centralizada aqui.
    fun question(env: String, title: String?, removeAll: Boolean) =
        if (removeAll) "Você deseja remover todos os lembretes de $env?"
        else "Você deseja remover o lembrete $title?"

    fun perform(env: String, title: String?, ctx: OverlaySkillContext) {
        ctx.scope.launch(Dispatchers.IO) {
            val ok = ctx.deleteTrigger(env, title)
            withContext(Dispatchers.Main) {
                if (ok) {
                    Logger.info("command_executed", feature = "floating_voice",
                        action = "execute", payload = mapOf("command" to "delete_trigger"),
                        correlationId = ctx.correlationId())
                    ctx.speak(if (title.isNullOrEmpty())
                        OverlayPersona.allRemindersRemoved(env)
                    else OverlayPersona.reminderRemoved)
                }
                ctx.endVoice()
            }
        }
    }
}

object DeleteAllTriggersSkill {
    fun question(env: String) = "Você deseja remover todos os lembretes de $env?"

    fun perform(env: String, ctx: OverlaySkillContext) {
        ctx.scope.launch(Dispatchers.IO) {
            val ok = ctx.deleteTrigger(env, null)
            withContext(Dispatchers.Main) {
                if (ok) {
                    Logger.info("command_executed", feature = "floating_voice",
                        action = "execute", payload = mapOf("command" to "delete_all_triggers"),
                        correlationId = ctx.correlationId())
                    ctx.speak(OverlayPersona.allRemindersRemoved(env))
                }
                ctx.endVoice()
            }
        }
    }
}
