import '../skills/base_skill.dart';
import '../skills/voice_skills.dart';

// Plugin System (mínimo viável) — registro/manifesto das Skills já existentes
// (voice_structure_doc/architecture/09-Plugin-System.md).
//
// Estágio 9: SEM carregamento dinâmico de verdade ainda. Só a ESTRUTURA de
// manifesto + registro, populada com as Skills criadas no Estágio 3. Serve de
// base para descoberta/enable-disable futuros, sem acoplar o núcleo.

// Categoria do plugin (spec 09). Hoje só `skill` é registrada.
enum PluginType { skill, provider, behavior, memory }

// Manifesto de um plugin (spec 09: id/name/version/type/entrypoint).
// [entrypoint] instancia a Skill sob demanda (Skill plugins).
class PluginManifest {
  final String id;
  final String name;
  final String description;
  final String version;
  final PluginType type;
  final BaseSkill Function() entrypoint;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.entrypoint,
    this.version = '1.0.0',
    this.type = PluginType.skill,
  });
}

// Registro simples em memória de plugins conhecidos.
class PluginManager {
  final Map<String, PluginManifest> _registry = {};

  // Registra (ou substitui) um manifesto por id.
  void register(PluginManifest manifest) => _registry[manifest.id] = manifest;

  // Todos os manifestos registrados.
  Iterable<PluginManifest> get all => _registry.values;

  // Manifesto por id (ou null).
  PluginManifest? byId(String id) => _registry[id];

  // Instancia a Skill de um plugin por id via seu entrypoint.
  BaseSkill? createSkill(String id) => _registry[id]?.entrypoint();
}

// Registro padrão — as Skills do Estágio 3. Cada manifesto reusa id/name/
// description da própria Skill como fonte única.
PluginManager buildDefaultPluginManager() {
  final pm = PluginManager();
  final factories = <BaseSkill Function()>[
    CreateEnvironmentSkill.new,
    CreateTriggerSkill.new,
    AddShoppingItemSkill.new,
    CreateReminderSkill.new,
    UpdateTriggerSkill.new,
    UpdateEnvironmentSkill.new,
    DeleteEnvironmentSkill.new,
    DeleteAllEnvironmentsSkill.new,
    DeleteTriggerSkill.new,
    DeleteAllTriggersSkill.new,
  ];
  for (final make in factories) {
    final skill = make();
    pm.register(PluginManifest(
      id: skill.id,
      name: skill.name,
      description: skill.description,
      entrypoint: make,
    ));
  }
  return pm;
}
