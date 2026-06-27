// BleEncounterEntity — registro de um encontro BLE com outro usuário Sopro.
//
// Um encontro é criado ou atualizado quando o ContextCard de outro dispositivo
// é recebido via GATT. O deviceId (MAC address BLE) é o identificador único:
// encontros repetidos com o mesmo dispositivo atualizam o registro em vez de
// criar duplicatas — mantém histórico limpo e respeita a privacidade.
class BleEncounterEntity {
  final String deviceId;     // MAC address BLE — chave do encontro
  final String displayName;  // Nome do ContextCard recebido
  final String role;         // Cargo profissional (pode estar vazio)
  final String company;      // Empresa ou organização (pode estar vazio)
  final String bio;          // Nota pessoal (pode estar vazio)
  final String tags;         // Interesses separados por vírgula (pode estar vazio)
  final DateTime encounteredAt; // Data/hora do último encontro com este dispositivo

  const BleEncounterEntity({
    required this.deviceId,
    required this.displayName,
    required this.role,
    required this.company,
    required this.bio,
    required this.tags,
    required this.encounteredAt,
  });

  // "Cargo · Empresa" — exibido na listagem de encontros
  String get occupationLine {
    if (role.isNotEmpty && company.isNotEmpty) return '$role · $company';
    if (role.isNotEmpty) return role;
    if (company.isNotEmpty) return company;
    return '';
  }

  // Inicial do nome para o avatar circular
  String get initial =>
      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
}
