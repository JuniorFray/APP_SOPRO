// VoiceOverlayService — STUB para V3.
//
// Este arquivo reserva o nome e a intenção do serviço.
// Em V3, um overlay flutuante (System Alert Window) exibirá o botão de microfone
// sobre qualquer app aberto, permitindo usar a voz sem precisar abrir o Sopro.
//
// Pré-requisitos V3:
//   - Permissão SYSTEM_ALERT_WINDOW concedida via Settings.ACTION_MANAGE_OVERLAY_PERMISSION
//     (o usuário é redirecionado para as Configurações do sistema — não é um diálogo padrão)
//   - Serviço Android do tipo WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
//   - Flutter: nenhum suporte nativo a overlays — precisará de MethodChannel dedicado
//     (ex: com.sopro.sopro/overlay) que gerencie o WindowManager na camada Kotlin
//
// Enquanto este stub existir, NÃO instanciar esta classe em produção.
// Qualquer uso deve ser guardado por verificação de canDrawOverlays().

// ignore_for_file: unused_element
class VoiceOverlayService {
  // Construtor privado — não instanciar em V2
  VoiceOverlayService._();
}
