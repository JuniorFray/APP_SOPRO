import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/pin_image_store.dart';
import '../../../domain/entities/environment_entity.dart';
import '../../../infrastructure/geocoding/geocoding_repository.dart';
import '../../../infrastructure/voice/environment_type_classifier.dart';
import '../../../infrastructure/location/location_guard.dart';
import '../../providers/database_provider.dart';
import '../../providers/location_providers.dart';
import '../../providers/voice_providers.dart';
import '../../widgets/glass_surface.dart';

// Estilo do pin escolhido na tela do mapa (Fase 1 — pins personalizados).
//   classic → teardrop em PNG (verde = seleção / azul = existentes)
//   threeD  → plaquinha 3D (arte Sopro padrão OU foto do ambiente)
enum PinStyle { classic, threeD }

// Chave de persistência do estilo do pin (GLOBAL). A FOTO é por ambiente (banco).
const String _kPinStylePref = 'map_pin_style'; // 'classic' | '3d'

// Tela de criação OU edição de Environment com mapa interativo.
//
// Modo criação: [environment] == null — campos em branco, submit gera UUID novo.
// Modo edição:  [environment] != null — campos pré-preenchidos, mapa centrado
//   na localização existente, submit faz upsert com o mesmo ID (atualização).
//
// O usuário pode:
//   - Tocar no mapa para posicionar o pin
//   - Buscar um endereço via Nominatim (OpenStreetMap, gratuito, sem API key)
//   - Usar "Localização atual" para centrar o mapa na posição GPS real
class AddEnvironmentScreen extends ConsumerStatefulWidget {
  // null = criação de novo ambiente; não-null = edição de ambiente existente
  final EnvironmentEntity? environment;
  // Nome pré-preenchido quando criado via comando de voz (Sprint V2-Voz)
  final String? initialName;
  // Posição GPS pré-definida quando enviado via voz (Sprint V2-VoicePro).
  // Centra o mapa e posiciona o pin automaticamente sem clique do usuário.
  final LatLng? initialPosition;

  // Modo "só localização" (Sprint F3-3): ambiente já criado por voz sem coords.
  // Quando preenchido, _submit() atualiza o ambiente existente (id) apenas com
  // lat/lon/raio, em vez de criar um novo.
  final String? pendingEnvironmentId;
  final String? pendingEnvironmentName;

  const AddEnvironmentScreen({
    super.key,
    this.environment,
    this.initialName,
    this.initialPosition,
    this.pendingEnvironmentId,
    this.pendingEnvironmentName,
  });

  @override
  ConsumerState<AddEnvironmentScreen> createState() =>
      _AddEnvironmentScreenState();
}

class _AddEnvironmentScreenState extends ConsumerState<AddEnvironmentScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _radiusController;
  final _searchCtrl       = TextEditingController(); // campo de busca por endereço
  final _searchFocusNode  = FocusNode();             // isola foco do campo de busca

  // Ponto selecionado pelo usuário no mapa; null enquanto nenhum foi tocado
  LatLng? _selectedPoint;
  bool _isSaving        = false;
  bool _loadingLocation = false;
  // GPS "aquecendo": true SÓ no ramo de criação sem posição pré-definida,
  // enquanto busca um fix fresco para last_known_lat/lon. NÃO bloqueia a busca —
  // apenas mostra "Localizando..." no campo. false nos modos edição e
  // initialPosition (voz), que já têm coords confiáveis.
  bool _gpsWarming      = false;
  // true enquanto o AudioRecorder está gravando para preencher o nome
  bool _recordingName   = false;
  // Timer de auto-stop para gravação de nome (7 s máximo)
  Timer? _nameRecordTimer;
  // Debounce de 400 ms para evitar buscas a cada tecla digitada
  Timer? _searchDebounce;

  // Estado da busca por endereço via Nominatim
  bool _searching = false;
  List<_SearchResult> _searchResults = [];

  // Estilo do mapa carregado como string via rootBundle — asset:// não é
  // confiável em maplibre_gl ^0.22.0.
  String? _mapStyleJson;

  // Controlador do mapa MapLibre — atribuído em onMapCreated
  ml.MapLibreMapController? _mapController;
  // Pin de seleção renderizado como imagem (Symbol nativo do mapa).
  ml.Symbol?  _pinSymbol;

  // Pins dos ambientes já existentes — camada de símbolos com fonte GeoJSON.
  // Cada feature carrega a propriedade 'icon' com o nome do sprite a usar
  // (por ambiente no 3D, único no clássico) — icon-image data-driven.
  static const String _envSrcId   = 'sopro_env_src';
  static const String _envLayerId = 'sopro_env_layer';
  bool _envSrcAdded   = false;
  bool _envLayerAdded = false;

  // Tamanho FIXO de todos os pins (sem escala por zoom). Todos os PNGs têm
  // ~512px de altura → um único iconSize dá o MESMO tamanho visual em clássico
  // e 3D (âncora bottom, altura manda). Calibrado ~40% maior que antes.
  static const double _pinIconSize = 0.17;

  // ── Estilo do pin (Fase 1) — estilo GLOBAL, foto POR AMBIENTE ─────────────
  // Estilo atual (clássico/3D) persistido globalmente em SharedPreferences.
  PinStyle _pinStyle = PinStyle.classic;
  // Foto do pin do ambiente sendo criado/editado (null → arte Sopro padrão).
  // Em edição inicia com widget.environment.pinImagePath; em criação fica só em
  // memória até o _submit persistir (o ambiente ainda não existe no banco).
  String? _pinImagePath;
  // Ambientes existentes que tiveram um sprite 3D próprio registrado ('env_pin_<id>').
  final Set<String> _registeredEnvImages = {};
  // Evita re-registrar as imagens antes das prefs de estilo terem sido lidas.
  bool _pinPrefsLoaded = false;

  // ID do ambiente sendo criado/editado, pré-gerado para servir de nome do
  // sprite de seleção e do arquivo de foto; reaproveitado no _submit.
  late final String _envId = widget.environment?.id.isNotEmpty == true
      ? widget.environment!.id
      : const Uuid().v4();

  // ID efetivo do ambiente atual (modo só-localização usa o pendente).
  String get _currentEnvId => _pendingEnvId ?? _envId;
  // O ambiente já existe no banco? (edição ou modo só-localização) → persiste a
  // foto na hora. Criação nova → segura a foto até o _submit.
  bool get _envPersisted => widget.environment != null || _pendingEnvId != null;

  // Centro inicial do mapa: São Paulo (referência urbana padrão para o Brasil)
  static const _defaultCenter = LatLng(-23.5505, -46.6333);

  // Valor do slider de raio (50–1000 m), sincronizado com _radiusController
  double _radiusSlider = 100.0;

  // Modo de visualização do mapa: false = 2D (topo), true = 3D (prédios extrudados).
  bool _is3D = false;

  // Sprint F3-3 — modo "só localização": id/nome do ambiente criado por voz sem
  // coords. Definidos via construtor; quando != null, _submit atualiza o existente.
  String? _pendingEnvId;
  String? _pendingEnvName;

  // Fase 4 — resultado da confirmação "Este é um mercado?" (null = não perguntado).
  // Alimenta isMarket ao salvar em _submit.
  bool? _resolvedIsMarket;

  @override
  void initState() {
    super.initState();
    // Sprint F3-3 — modo só-localização recebido via construtor (onResume do home).
    // Sem leitura global de SharedPreferences aqui: evita sequestrar uma criação
    // manual nova com um pending antigo.
    _pendingEnvId   = widget.pendingEnvironmentId;
    _pendingEnvName = widget.pendingEnvironmentName;

    // Foto do pin: em edição parte do valor salvo no ambiente; em criação null.
    _pinImagePath = widget.environment?.pinImagePath;
    // Estilo (clássico/3D) é global e persistido localmente. Assíncrono;
    // onStyleLoaded garante a leitura antes de registrar as imagens.
    _loadPinPrefs();

    // Carrega o estilo do mapa como string — asset:// não é
    // confiável em maplibre_gl ^0.22.0.
    rootBundle.loadString('assets/map_style_sopro.json').then((json) {
      if (mounted) setState(() => _mapStyleJson = json);
    });

    // Pré-preenche com os dados do ambiente ao editar; initialName (voz) ao criar;
    // pendingEnvironmentName no modo só-localização; vazio caso contrário
    _nameController = TextEditingController(
      text: widget.environment?.name ??
          widget.initialName ??
          widget.pendingEnvironmentName ??
          '',
    );
    final initialRadius = widget.environment != null
        ? widget.environment!.radiusMeters
        : (double.tryParse(AppStrings.radiusDefault) ?? 100.0);
    _radiusSlider = initialRadius.clamp(50.0, 1000.0);
    _radiusController = TextEditingController(text: _radiusSlider.toInt().toString());

    if (widget.environment != null) {
      // Posiciona o pin na localização existente
      _selectedPoint = LatLng(
        widget.environment!.latitude,
        widget.environment!.longitude,
      );
      // Centraliza o mapa após o primeiro frame (controller não está pronto no initState)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController?.animateCamera(
            ml.CameraUpdate.newLatLngZoom(
              ml.LatLng(_selectedPoint!.latitude, _selectedPoint!.longitude),
              15.0));
        }
      });
    } else if (widget.initialPosition != null) {
      // GPS pré-obtido via comando de voz — posiciona pin sem clique do usuário
      _selectedPoint = widget.initialPosition;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController?.animateCamera(
            ml.CameraUpdate.newLatLngZoom(
              ml.LatLng(widget.initialPosition!.latitude,
                  widget.initialPosition!.longitude),
              15.0));
        }
      });
    } else {
      // Modo criação sem posição pré-definida: centraliza e pina no último GPS salvo.
      // Chave sem prefixo "flutter." — o plugin Dart já remove o prefixo automaticamente.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          final prefs = await SharedPreferences.getInstance();
          final lat = prefs.getDouble('last_known_lat') ?? 0.0;
          final lon = prefs.getDouble('last_known_lon') ?? 0.0;
          if (lat != 0.0 && lon != 0.0 && mounted) {
            final pos = LatLng(lat, lon);
            setState(() => _selectedPoint = pos);
            _mapController?.animateCamera(
              ml.CameraUpdate.newLatLngZoom(
                ml.LatLng(pos.latitude, pos.longitude), 15.0));
          }
        } catch (_) {}
      });
      // Atualiza SharedPreferences com GPS fresco ANTES da primeira busca possível
      // — sem isso, last_known_lat/lon pode estar zerado/antigo e a busca por
      // lugar vem sem viés (resultados de cidade errada). _gpsWarming sinaliza o
      // campo de busca ("Localizando...") sem bloquear a digitação.
      _gpsWarming = true;
      _warmUpCurrentGps();
    }
  }

  // Aquece last_known_lat/lon com um fix GPS fresco. Chamado SÓ no ramo de
  // criação sem posição pré-definida. Timeout de 4s no getCurrentPosition: GPS
  // lento (indoor) não trava a liberação do campo. Encerra _gpsWarming em
  // sucesso, erro OU timeout — nunca deixa o indicador preso. A busca nunca é
  // bloqueada; enquanto aquece usa o valor salvo (mesmo antigo) como fallback.
  Future<void> _warmUpCurrentGps() async {
    final locSvc = ref.read(nativeLocationServiceProvider);
    try {
      final enabled = await locSvc.isLocationEnabled();
      if (enabled) {
        final pos = await locSvc
            .getCurrentPosition()
            .timeout(const Duration(seconds: 4), onTimeout: () => null);
        if (pos != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('last_known_lat', pos.latitude);
          await prefs.setDouble('last_known_lon', pos.longitude);
          // Recentraliza no fix fresco só se o usuário ainda não escolheu ponto
          // (não sequestra um toque no mapa nem um resultado já selecionado).
          if (mounted && _selectedPoint == null) {
            final point = LatLng(pos.latitude, pos.longitude);
            setState(() => _selectedPoint = point);
            await _updateMapPin(point);
            _mapController?.animateCamera(
              ml.CameraUpdate.newLatLngZoom(
                ml.LatLng(point.latitude, point.longitude), 15.0));
          }
        }
      }
    } catch (_) {
      // GPS indisponível / erro de canal — segue com o valor salvo como fallback.
    } finally {
      if (mounted) setState(() => _gpsWarming = false);
    }
  }

  @override
  void dispose() {
    _nameRecordTimer?.cancel();
    _searchDebounce?.cancel();
    _mapController?.dispose();
    ref.read(voiceServiceProvider).cancelRecording();
    _nameController.dispose();
    _radiusController.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Teclado aberto? Esconde o cluster inferior (card de raio + controles) para
    // não brigar com o campo de texto que está sendo digitado.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      // Sem AppBar: o mapa é protagonista full-bleed (atrás da status bar e do
      // rodapé). resizeToAvoidBottomInset falso evita o teclado empurrar o mapa.
      resizeToAvoidBottomInset: false,
      body: Form(
        key: _formKey,
        child: Stack(
          children: [
            // ── Mapa full-screen ─────────────────────────────────────────────
            Positioned.fill(child: _buildMap()),

            // ── Gradientes de legibilidade (não bloqueiam gestos do mapa) ─────
            const Positioned(
              top: 0, left: 0, right: 0,
              child: IgnorePointer(child: _TopScrim()),
            ),
            const Positioned(
              bottom: 0, left: 0, right: 0,
              child: IgnorePointer(child: _BottomScrim()),
            ),

            // ── Topo flutuante: voltar + campos glass (nome / busca) ──────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: _buildFloatingTop(context),
            ),

            // ── Instrução central quando nenhum ponto selecionado ────────────
            if (_selectedPoint == null)
              const Positioned(
                bottom: 260, left: 16, right: 16,
                child: _MapChip(label: AppStrings.mapTapInstruction),
              ),

            // ── Cluster inferior: controles do mapa + card de raio ───────────
            // Um único bloco ancorado na base. Some (desliza + fade) com teclado.
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: IgnorePointer(
                ignoring: keyboardOpen,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  offset: keyboardOpen ? const Offset(0, 1.4) : Offset.zero,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: keyboardOpen ? 0 : 1,
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Controles do mapa empilhados, alinhados à direita,
                          // logo acima do card de raio.
                          Padding(
                            padding: const EdgeInsets.only(right: 16, bottom: 12),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildPinStyleButton(),
                                  const SizedBox(height: 12),
                                  _build3DButton(),
                                  const SizedBox(height: 12),
                                  _buildGpsButton(),
                                ],
                              ),
                            ),
                          ),
                          // Card glass único: raio de ação + slider + salvar.
                          _buildBottomCard(context),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mapa MapLibre vetorial com estilo noturno custom. Aguarda o estilo carregar
  // como string (asset:// não é confiável). Lógica de pin/câmera preservada.
  Widget _buildMap() {
    if (_mapStyleJson == null) return const SizedBox.expand();
    return ml.MapLibreMap(
      styleString: _mapStyleJson!,
      initialCameraPosition: ml.CameraPosition(
        target: ml.LatLng(
          _defaultCenter.latitude,
          _defaultCenter.longitude,
        ),
        zoom: 13.0,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
      },
      onStyleLoadedCallback: () async {
        // Garante que o estilo/imagem persistidos já foram lidos antes de
        // registrar os sprites (evita registrar o 3D com o path ainda nulo).
        await _ensurePinPrefs();
        // Registra os sprites dos dois estilos (clássico verde/azul + 3D).
        await _registerPinImages();

        // Camada GeoJSON com os ambientes já cadastrados (tamanho fixo).
        await _ensureEnvData();
        await _addEnvLayer();

        if (_selectedPoint != null) {
          await _updateMapPin(_selectedPoint!);
        }

        // maplibre_gl renderiza o primeiro frame escuro/incompleto (surface
        // OpenGL stale) até haver um movimento de câmera que force o redesenho.
        // Nudge imperceptível de zoom acorda o mapa.
        await _mapController?.animateCamera(
          ml.CameraUpdate.zoomBy(0.01),
          duration: const Duration(milliseconds: 1),
        );
      },
      onMapClick: (point, coordinates) {
        final latLng = LatLng(coordinates.latitude, coordinates.longitude);
        setState(() {
          _selectedPoint = latLng;
          _searchResults = [];
        });
        _updateMapPin(latLng);
      },
      compassEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      myLocationEnabled: false,
      trackCameraPosition: false,
    );
  }

  // Topo flutuante sobre o mapa: botão voltar glass + cartões glass de nome e
  // busca. A lista de resultados aparece logo abaixo do campo de busca.
  Widget _buildFloatingTop(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Linha do botão voltar (spinner de salvamento à direita).
            Row(
              children: [
                _glassCircleButton(
                  onTap: () => Navigator.pop(context),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  child: const Icon(LucideIcons.arrowLeft,
                      color: AppColors.textPrimary, size: 20),
                ),
                const Spacer(),
                if (_isSaving)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textPrimary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Sprint F3-3 — banner do modo só-localização (ambiente por voz).
            if (_pendingEnvId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Icon(Icons.edit_location_alt,
                        color: AppColors.accent, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Definindo localização de: ${_pendingEnvName ?? ''}',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            // Cartão glass: nome do local.
            GlassSurface(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: _buildNameField(),
            ),
            const SizedBox(height: 10),
            // Cartão glass: busca de endereço.
            GlassSurface(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: _buildSearchField(),
            ),
            // Resultados da busca — fundo opaco legível sobre o mapa.
            if (_searchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: AppColors.backgroundCard,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _searchResults.take(4).map((r) {
                    return ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      leading: const Icon(Icons.location_on_outlined,
                          color: AppColors.accent, size: 18),
                      title: Text(
                        r.displayName,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _selectResult(r),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Campo de nome do ambiente — borderless para o vidro do cartão aparecer.
  // (somente leitura no modo só-localização)
  Widget _buildNameField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextFormField(
        controller: _nameController,
        readOnly: _pendingEnvId != null,
        textCapitalization: TextCapitalization.words,
        validator: (v) => (v == null || v.trim().isEmpty)
            ? AppStrings.environmentNameRequired
            : null,
        style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: AppStrings.environmentNameLabel,
          hintText: _recordingName
              ? AppStrings.voiceFillHint
              : AppStrings.environmentNameHint,
          hintStyle:
              AppTypography.bodySmall.copyWith(color: AppColors.textDisabled),
          labelStyle:
              AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          floatingLabelStyle: AppTypography.caption.copyWith(
            color: AppColors.accent,
            fontWeight: FontWeight.w600,
          ),
          // Sem preenchimento/borda: o cartão glass já é o container.
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          suffixIcon: _recordingName
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.mic_outlined,
                      color: AppColors.accent, size: 20),
                  tooltip: AppStrings.voiceMicTooltip,
                  onPressed: _recordForName,
                ),
        ),
      ),
    );
  }

  // Campo de busca por endereço — borderless dentro do cartão glass.
  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      child: Row(
        children: [
          (_searching || _gpsWarming)
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                )
              : const Icon(LucideIcons.search,
                  color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocusNode,
              style:
                  AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: _gpsWarming
                    ? AppStrings.searchLocatingHint
                    : AppStrings.searchAddressHint,
                hintStyle:
                    AppTypography.bodyMedium.copyWith(color: AppColors.textDisabled),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchAddress(),
              onChanged: _onSearchChanged,
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _searchCtrl.clear();
                _searchResults = [];
              }),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.clear, size: 16, color: AppColors.textDisabled),
              ),
            ),
        ],
      ),
    );
  }

  // Botão glass circular reutilizável (voltar / controles do mapa).
  Widget _glassCircleButton({
    required Widget child,
    required VoidCallback? onTap,
    String? tooltip,
    double size = 44,
  }) {
    final btn = GestureDetector(
      onTap: onTap,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(size / 2),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: child),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }

  Future<void> _updateMapPin(LatLng point) async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    final mlPoint = ml.LatLng(point.latitude, point.longitude);

    if (_pinSymbol != null) {
      await ctrl.removeSymbol(_pinSymbol!);
      _pinSymbol = null;
    }

    final is3d = _pinStyle == PinStyle.threeD;
    _pinSymbol = await ctrl.addSymbol(ml.SymbolOptions(
      geometry:   mlPoint,
      // Clássico: teardrop verde (seleção). 3D: plaquinha da foto do ambiente
      // atual (ou arte Sopro se sem foto). Tamanho FIXO, igual aos existentes.
      iconImage:  is3d ? _selPinImageName : 'pin_teardrop_verde',
      iconSize:   _pinIconSize,
      iconAnchor: 'bottom',
    ));

    await ctrl.animateCamera(
      ml.CameraUpdate.newLatLng(mlPoint));
  }

  // Nome do sprite do pin de seleção no modo 3D (plaquinha da foto atual).
  static const String _selPinImageName = 'pin_sel_3d';

  // ── Registro de sprites ───────────────────────────────────────────────────
  // Registra os sprites base. Clássico: teardrop verde (seleção) e azul
  // (existentes), assets PNG diretos. 3D: plaquinha padrão Sopro + a plaquinha
  // de seleção (composta com a foto do ambiente atual, se houver).
  Future<void> _registerPinImages() async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    await ctrl.addImage('pin_teardrop_verde',
        await _loadAssetBytes('assets/pin_teardrop_verde.png'));
    await ctrl.addImage('pin_teardrop_azul',
        await _loadAssetBytes('assets/pin_teardrop_azul.png'));
    await ctrl.addImage('pin_3d_sopro',
        await _loadAssetBytes('assets/pin_3d_sopro.png'));
    await _reloadSelectionImage();
  }

  // Recompõe e registra o sprite da plaquinha de seleção 3D com a foto atual do
  // ambiente sendo criado/editado (ou arte Sopro padrão se sem foto).
  Future<void> _reloadSelectionImage() async {
    await _mapController?.addImage(
        _selPinImageName, await _render3dPinBytes(_pinImagePath));
  }

  // Lê os bytes crus de um asset PNG (sprite pronto, sem composição).
  Future<Uint8List> _loadAssetBytes(String asset) async {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List();
  }

  // ── Camada GeoJSON dos ambientes existentes ───────────────────────────────
  // Monta a fonte de pontos e, no modo 3D, registra um sprite por ambiente que
  // tenha foto ('env_pin_<id>'). Cada feature carrega a propriedade 'icon' com o
  // nome do sprite — o icon-image da camada é data-driven (['get','icon']).
  // Pula o próprio ambiente em edição/só-localização (evita duplicar a seleção).
  Future<void> _ensureEnvData() async {
    final ctrl = _mapController;
    if (ctrl == null) return;

    final envs = await ref.read(environmentRepositoryProvider).getAll();
    final skipId = widget.environment?.id ?? _pendingEnvId;
    final is3d = _pinStyle == PinStyle.threeD;
    final features = <Map<String, dynamic>>[];

    for (final e in envs) {
      if (e.id == skipId) continue; // não duplica o ambiente em foco

      String icon;
      if (!is3d) {
        icon = 'pin_teardrop_azul'; // clássico: azul para todos os existentes
      } else if (e.pinImagePath != null && File(e.pinImagePath!).existsSync()) {
        // 3D com foto: registra (uma vez) o sprite próprio do ambiente.
        icon = 'env_pin_${e.id}';
        if (!_registeredEnvImages.contains(e.id)) {
          await ctrl.addImage(icon, await _render3dPinBytes(e.pinImagePath));
          _registeredEnvImages.add(e.id);
        }
      } else {
        icon = 'pin_3d_sopro'; // 3D sem foto: plaquinha padrão Sopro
      }

      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [e.longitude, e.latitude], // GeoJSON = [lon, lat]
        },
        'properties': {'icon': icon},
      });
    }
    final fc = {'type': 'FeatureCollection', 'features': features};

    if (_envSrcAdded) {
      await ctrl.setGeoJsonSource(_envSrcId, fc);
    } else {
      await ctrl.addGeoJsonSource(_envSrcId, fc);
      _envSrcAdded = true;
    }
  }

  // Adiciona a camada de símbolos dos ambientes. icon-image data-driven (lê a
  // propriedade 'icon' de cada feature); tamanho FIXO igual ao pin de seleção.
  // Sem interação (o toque no mapa continua criando/movendo a seleção).
  Future<void> _addEnvLayer() async {
    final ctrl = _mapController;
    if (ctrl == null || _envLayerAdded) return;
    await ctrl.addSymbolLayer(_envSrcId, _envLayerId, _envLayerProps(),
        enableInteraction: false);
    _envLayerAdded = true;
  }

  // Remove a camada de símbolos (mantém a fonte) — usado ao trocar de estilo.
  Future<void> _removeEnvLayer() async {
    final ctrl = _mapController;
    if (ctrl == null || !_envLayerAdded) return;
    await ctrl.removeLayer(_envLayerId);
    _envLayerAdded = false;
  }

  // Propriedades da camada: sprite por feature ('icon'), âncora bottom, tamanho
  // FIXO. Opacidade < 1 no 3D diferencia dos pins de seleção sem mudar a cor.
  ml.SymbolLayerProperties _envLayerProps() {
    final is3d = _pinStyle == PinStyle.threeD;
    return ml.SymbolLayerProperties(
      iconImage:           ['get', 'icon'],
      iconAnchor:          'bottom',
      iconAllowOverlap:    true,
      iconIgnorePlacement: true,
      iconOpacity:         is3d ? 0.85 : 1.0,
      iconSize:            _pinIconSize,
    );
  }

  // ── Composição da plaquinha 3D (moldura + foto) ───────────────────────────
  // Compõe a plaquinha 3D como PNG. Sem foto → usa a arte Sopro pronta. Com foto
  // → desenha a foto recortada num rounded-rect que preenche o interior da
  // moldura e sobrepõe a moldura vazia por cima.
  Future<Uint8List> _render3dPinBytes(String? userImagePath) async {
    // Caso simples: arte padrão Sopro (ponta já encostada na borda inferior).
    if (userImagePath == null || !File(userImagePath).existsSync()) {
      final data = await rootBundle.load('assets/pin_3d_sopro.png');
      return data.buffer.asUint8List();
    }

    // Moldura vazia + imagem do usuário decodificadas para composição no canvas.
    final frameData = await rootBundle.load('assets/pin_3d_frame.png');
    final frameImg  = await _decodeImage(frameData.buffer.asUint8List());
    final userImg   = await _decodeImage(await File(userImagePath).readAsBytes());

    // Dimensões nativas dos PNGs (395x512). Janela interna medida no canal alpha
    // da moldura (bbox do buraco transparente) + leve sangria sob a borda para
    // não deixar fresta entre a foto e a moldura.
    const double fw = 395.0, fh = 512.0;
    const inner = Rect.fromLTRB(38 - 6, 24 - 6, 348 + 6, 368 + 6);

    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder, const Rect.fromLTWH(0, 0, fw, fh));

    // 1) Foto do usuário POR BAIXO, recortada em rounded-rect (cover-fit).
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(inner, const Radius.circular(26)));
    final src = _coverSrcRect(
        userImg.width.toDouble(), userImg.height.toDouble(), inner);
    canvas.drawImageRect(
      userImg, src, inner,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    // 2) Moldura 3D por cima (interior transparente revela a foto).
    canvas.drawImageRect(
      frameImg,
      Rect.fromLTWH(0, 0, frameImg.width.toDouble(), frameImg.height.toDouble()),
      const Rect.fromLTWH(0, 0, fw, fh),
      Paint(),
    );

    final pic   = recorder.endRecording();
    final img   = await pic.toImage(fw.round(), fh.round());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  // Decodifica bytes PNG/JPG para ui.Image (para desenho no canvas).
  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  // Retângulo-fonte para desenhar [iw]x[ih] cobrindo [dest] no estilo BoxFit.cover
  // (recorta o excesso do lado mais longo, centralizado).
  Rect _coverSrcRect(double iw, double ih, Rect dest) {
    final da = dest.width / dest.height;
    final ia = iw / ih;
    if (ia > da) {
      final w = ih * da;                       // imagem mais larga → corta laterais
      return Rect.fromLTWH((iw - w) / 2, 0, w, ih);
    }
    final hh = iw / da;                         // imagem mais alta → corta topo/base
    return Rect.fromLTWH(0, (ih - hh) / 2, iw, hh);
  }

  // ── Persistência do estilo (GLOBAL) + aplicação no mapa ───────────────────
  // Lê o estilo salvo (clássico/3D é preferência global). A FOTO é por ambiente
  // (vem do banco), não daqui. Marca _pinPrefsLoaded para _ensurePinPrefs.
  Future<void> _loadPinPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _pinStyle = prefs.getString(_kPinStylePref) == '3d'
          ? PinStyle.threeD
          : PinStyle.classic;
    } catch (_) {
      // Falha de leitura → mantém o default (clássico).
    } finally {
      _pinPrefsLoaded = true;
    }
  }

  // Garante que _loadPinPrefs terminou antes de registrar os sprites (corrige a
  // corrida entre o carregamento assíncrono das prefs e o style-load do mapa).
  Future<void> _ensurePinPrefs() async {
    if (_pinPrefsLoaded) return;
    await _loadPinPrefs();
  }

  // Troca o estilo do pin (clássico/3D — global), persiste e re-renderiza no
  // mapa sem sair da tela: recalcula a camada dos existentes e o pin de seleção.
  Future<void> _setPinStyle(PinStyle style) async {
    if (style == _pinStyle) return;
    setState(() => _pinStyle = style);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kPinStylePref, style == PinStyle.threeD ? '3d' : 'classic');
    await _reapplyPins();
  }

  // Recompõe a fonte/camada dos existentes (recalcula 'icon' por feature) e o
  // pin de seleção conforme o estilo/foto atuais.
  Future<void> _reapplyPins() async {
    await _ensureEnvData();
    await _removeEnvLayer();
    await _addEnvLayer();
    if (_selectedPoint != null) await _updateMapPin(_selectedPoint!);
  }

  // Escolhe a foto do pin DO AMBIENTE atual (image_picker + cópia local). Se o
  // ambiente já existe no banco, persiste na hora; se é criação nova, segura em
  // memória até o _submit. Atualiza o mapa imediatamente.
  Future<bool> _pickPinImage() async {
    final path = await PinImageStore.pickForEnvironment(
      _currentEnvId,
      previousPath: _pinImagePath,
    );
    if (path == null) return false; // usuário cancelou
    _pinImagePath = path;
    if (_envPersisted) {
      await ref
          .read(environmentRepositoryProvider)
          .updatePinImagePath(_currentEnvId, path);
    }
    await _onPinImageChanged();
    return true;
  }

  // Remove a foto do ambiente atual (volta à arte Sopro padrão).
  Future<void> _removePinImage() async {
    await PinImageStore.remove(_pinImagePath);
    _pinImagePath = null;
    if (_envPersisted) {
      await ref
          .read(environmentRepositoryProvider)
          .updatePinImagePath(_currentEnvId, null);
    }
    await _onPinImageChanged();
  }

  // Após trocar/remover a foto: garante estilo 3D, recompõe o sprite de seleção
  // e o sprite da feature do ambiente (se existente), e reaplica no mapa.
  Future<void> _onPinImageChanged() async {
    if (_pinStyle != PinStyle.threeD) {
      setState(() => _pinStyle = PinStyle.threeD);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPinStylePref, '3d');
    }
    await _reloadSelectionImage();
    // Ambiente existente: força recompor o sprite próprio na próxima montagem.
    if (_envPersisted) _registeredEnvImages.remove(_currentEnvId);
    await _reapplyPins();
    if (mounted) setState(() {}); // atualiza preview no sheet, se aberto
  }

  // Abre o bottom sheet glass de seleção de estilo do pin.
  Future<void> _openPinStyleSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PinStyleSheet(
        initialStyle: _pinStyle,
        hasUserImage: _pinImagePath != null,
        classicThumbAsset: 'assets/pin_teardrop_verde.png',
        render3d: () => _render3dPinBytes(_pinImagePath),
        onSelectClassic: () => _setPinStyle(PinStyle.classic),
        onSelect3D:      () => _setPinStyle(PinStyle.threeD),
        onPickImage:     _pickPinImage,
        onRemoveImage:   _removePinImage,
      ),
    );
  }

  // Botão de localização atual — glass mini FAB
  // Alterna 2D <-> 3D: troca a visibilidade das camadas de prédio e inclina a
  // câmera (50° em 3D, plano em 2D). No-op se o controlador ainda não existe.
  Future<void> _toggle3D() async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    final next = !_is3D;
    setState(() => _is3D = next);
    // Extrusão só em 3D; fill chapado só em 2D (evita sobreposição de desenho).
    await ctrl.setLayerVisibility('building-3d', next);
    await ctrl.setLayerVisibility('building', !next);
    // Inclina/desinclina preservando centro e zoom atuais.
    await ctrl.animateCamera(
      ml.CameraUpdate.tiltTo(next ? 50.0 : 0.0),
      duration: const Duration(milliseconds: 450),
    );
  }

  // Botão glass circular que abre o seletor de estilo do pin — ícone mapPin
  // monocromático (sem coral), padrão dos demais controles do mapa.
  Widget _buildPinStyleButton() {
    return _glassCircleButton(
      onTap: _openPinStyleSheet,
      tooltip: AppStrings.pinStyleTooltip,
      child: const Icon(LucideIcons.mapPin,
          color: AppColors.textSecondary, size: 20),
    );
  }

  // Botão glass circular que alterna a visão 2D/3D — monocromático, sem coral.
  Widget _build3DButton() {
    return _glassCircleButton(
      onTap: _toggle3D,
      tooltip: _is3D ? AppStrings.map2D : AppStrings.map3D,
      child: Text(
        _is3D ? '2D' : '3D',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  // Botão glass circular de localização atual — ícone Lucide monocromático.
  Widget _buildGpsButton() {
    return _glassCircleButton(
      onTap: _loadingLocation ? null : _onLocationButtonPressed,
      tooltip: AppStrings.useCurrentLocation,
      child: _loadingLocation
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textSecondary,
              ),
            )
          : const Icon(LucideIcons.locateFixed,
              color: AppColors.textSecondary, size: 20),
    );
  }

  // Card glass único flutuante no rodapé: raio de ação + slider + salvar.
  Widget _buildBottomCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header UPPERCASE — padrão de seção do app.
              Text(
                AppStrings.radiusActionLabel.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textDisabled,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: AppSpacing.gap6),
              // Valor grande — acompanha o slider.
              Text(
                '${_radiusSlider.toInt()} ${AppStrings.radiusUnitLong}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              // Slider premium: trilho gradiente pink→azul, thumb glass.
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  overlayColor: const Color(0x33E03050),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 16),
                  thumbShape: const _GlassThumb(),
                  trackShape: const _GradientTrack(),
                ),
                child: Slider(
                  value: _radiusSlider,
                  min: 50,
                  max: 1000,
                  onChanged: (v) => setState(() {
                    _radiusSlider = v;
                    _radiusController.text = v.toInt().toString();
                  }),
                ),
              ),
              // Labels discretas nas pontas do slider (mín / máx).
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(
                      '50 ${AppStrings.radiusUnitShort}',
                      style: TextStyle(
                          color: AppColors.textDisabled, fontSize: 11),
                    ),
                    Spacer(),
                    Text(
                      '1000 ${AppStrings.radiusUnitShort}',
                      style: TextStyle(
                          color: AppColors.textDisabled, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Botão Salvar — pill coral com glow (desabilitado sem ponto).
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  // Botão Salvar — pill coral gradiente com glow; desabilitado sem ponto.
  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: (_selectedPoint != null && !_isSaving) ? _submit : null,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _selectedPoint != null
                  ? const [Color(0xFFE03050), Color(0xFFE03050)]
                  : const [Color(0x66E03050), Color(0x66E03050)],
            ),
            borderRadius: BorderRadius.circular(AppRadius.button),
            boxShadow: _selectedPoint != null
                ? const [
                    BoxShadow(
                      color: Color(0x40E03050),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: _isSaving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  AppStrings.save,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }

  // Grava 7 s de áudio e usa Gemini para transcrever o nome do ambiente.
  // Toque no mic inicia; auto-para após 7 s. Toque novamente cancela.
  Future<void> _recordForName() async {
    if (_recordingName) {
      // Segundo toque: cancela gravação em andamento
      _nameRecordTimer?.cancel();
      ref.read(voiceServiceProvider).cancelRecording();
      if (mounted) setState(() => _recordingName = false);
      return;
    }

    final service = ref.read(voiceServiceProvider);
    final ok = await service.startRecording();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.voiceNotAvailable)),
      );
      return;
    }
    setState(() => _recordingName = true);

    // Para automaticamente após 7 s e transcreve via Gemini
    _nameRecordTimer = Timer(const Duration(seconds: 7), () async {
      final path = await service.stopRecording();
      if (!mounted) return;
      setState(() => _recordingName = false);
      if (path == null) return;
      // HOTFIX 1 — sem fala detectada, não chama o Gemini (evita transcrição vazia)
      if (!service.speechDetected) return;
      // transcribeAudio usa o Gemini para extrair apenas o texto falado
      final transcript = await service.transcribeAudio(path);
      if (!mounted || transcript == null || transcript.isEmpty) return;
      setState(() {
        // Capitaliza a inicial do nome ditado
        _nameController.text =
            transcript[0].toUpperCase() + transcript.substring(1);
      });
    });
  }

  // Busca um endereço via GeocodingRepository (cascata: cache → Geocoder nativo → Photon).
  Future<void> _searchAddress() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching     = true;
      _searchResults = [];
    });

    try {
      final results = await _fetchGeocodingService(query);
      if (!mounted) return;
      setState(() => _searchResults = results);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.searchError),
          backgroundColor: AppTheme.backgroundElevated,
        ),
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // Delega a busca ao GeocodingRepository (cache → Geocoder nativo → Photon).
  // Queries de estabelecimento (1 palavra, sem número) são enriquecidas com
  // contexto de localização via reverse geocoding para melhorar a precisão.
  // Converte GeocodingResult para o tipo interno _SearchResult.
  Future<List<_SearchResult>> _fetchGeocodingService(String query) async {
    final repo = ref.read(geocodingRepositoryProvider);
    final enrichedQuery = await _enrichQueryWithLocation(query, repo);
    final results = await repo.search(enrichedQuery);
    debugPrint('[GeocodingScreen] query=$query enriched=$enrichedQuery results=${results.length}');
    return results
        .map((r) => _SearchResult(
              displayName: r.displayName,
              lat: r.lat,
              lon: r.lon,
            ))
        .toList();
  }

  // O Photon já usa lat/lon como bias de proximidade.
  // Enriquecimento causava encoding corrompido e sufixos incorretos.
  Future<String> _enrichQueryWithLocation(
      String query, GeocodingRepository repo) async {
    return query;
  }

  // Debounce de 800 ms: só dispara _searchAddress() após o usuário parar de digitar.
  // Limpa os resultados imediatamente ao esvaziar o campo.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.isEmpty && _searchResults.isNotEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 800), () {
      if (value.length >= 4) _searchAddress();
    });
  }

  // Seleciona um resultado da busca: move o mapa e posiciona o pin
  Future<void> _selectResult(_SearchResult result) async {
    final point = LatLng(result.lat, result.lon);
    setState(() {
      _selectedPoint  = point;
      _searchResults  = [];
    });
    _searchCtrl.clear();
    await _updateMapPin(point);
    _mapController?.animateCamera(
      ml.CameraUpdate.newLatLngZoom(
        ml.LatLng(point.latitude, point.longitude), 15.0));
  }

  // Obtém a posição real via GPS nativo e centraliza o mapa no ponto obtido.
  Future<void> _onLocationButtonPressed() async {
    setState(() => _loadingLocation = true);

    final service = ref.read(nativeLocationServiceProvider);

    try {
      bool hasPermission = await service.checkPermission();
      if (!hasPermission) {
        hasPermission = await service.requestPermission();
      }

      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.locationPermissionDenied),
            backgroundColor: AppTheme.backgroundElevated,
          ),
        );
        return;
      }

      if (!mounted) return;
      final pos = await getLocationWithGpsCheck(context, service);
      if (!mounted) return;

      if (pos != null) {
        final point = LatLng(pos.latitude, pos.longitude);
        setState(() => _selectedPoint = point);
        await _updateMapPin(point);
        _mapController?.animateCamera(
          ml.CameraUpdate.newLatLngZoom(
            ml.LatLng(point.latitude, point.longitude), 16.0));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.locationError),
            backgroundColor: AppTheme.backgroundElevated,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedPoint == null) return;

    setState(() => _isSaving = true);

    try {
      // Sprint F3-3 — modo só-localização: atualiza o ambiente já criado por voz
      // apenas com coords + raio; não cria novo nem altera nome/createdAt.
      if (_pendingEnvId != null) {
        final repo = ref.read(environmentRepositoryProvider);
        final existing = await repo.getById(_pendingEnvId!);
        if (existing != null) {
          final updated = EnvironmentEntity(
            id:           existing.id,
            name:         existing.name,
            latitude:     _selectedPoint!.latitude,
            longitude:    _selectedPoint!.longitude,
            radiusMeters: double.tryParse(_radiusController.text) ?? 100.0,
            createdAt:    existing.createdAt,
            isMarket:     existing.isMarket,
            // Foto do pin já persistida via updatePinImagePath; preserva no upsert.
            pinImagePath: _pinImagePath ?? existing.pinImagePath,
          );
          await repo.save(updated);
          try {
            await ref
                .read(nativeGeofenceServiceProvider)
                .addSingleGeofence(updated);
          } catch (e) {
            debugPrint('[AddEnvironmentScreen] Falha geofence: $e');
          }
        }
        _pendingEnvId = null;
        if (mounted) Navigator.pop(context);
        return;
      }

      // ID pré-gerado no initState (_envId): mesmo valor usado no nome do arquivo
      // da foto do pin e no registro do geofence nativo.
      final id = _envId;

      // Fase 4 — só para ambiente NOVO: se o nome sugere um mercado, confirmar
      // ("Sim" pré-selecionado) antes de persistir. Nome que não sugere mercado
      // salva direto com isMarket=false (fallback silencioso). Ao editar, o tipo
      // atual é preservado; a correção fica no environment_detail_screen.
      if (widget.environment == null && _resolvedIsMarket == null) {
        final envName = _nameController.text.trim();
        _resolvedIsMarket =
            EnvironmentTypeClassifier.suggestsMarket(envName)
                ? await _confirmMarket(envName)
                : false;
      }

      final entity = EnvironmentEntity(
        id:           id,
        name:         _nameController.text.trim(),
        latitude:     _selectedPoint!.latitude,
        longitude:    _selectedPoint!.longitude,
        radiusMeters: double.tryParse(_radiusController.text) ?? 100.0,
        createdAt:    widget.environment?.createdAt ?? DateTime.now(),
        // Definido na Fase 4 pelo classificador + confirmação; preserva ao editar.
        isMarket:     _resolvedIsMarket ?? widget.environment?.isMarket ?? false,
        // Foto do pin: escolhida na tela (nova) ou herdada do ambiente (edição).
        pinImagePath: _pinImagePath,
      );

      await ref.read(environmentRepositoryProvider).save(entity);

      // Registra/atualiza o geofence nativo imediatamente após salvar.
      // Sem isso, o ambiente só seria monitorado após o próximo startup do app.
      try {
        await ref
            .read(nativeGeofenceServiceProvider)
            .addSingleGeofence(entity);
      } catch (e) {
        // Falha silenciosa: o GPS stream do GeofenceManager ainda monitora em foreground
        debugPrint('[AddEnvironmentScreen] Falha geofence nativo: $e');
      }

      if (mounted) Navigator.pop(context);
    } catch (e, st) {
      debugPrint('[AddEnvironmentScreen] Erro ao salvar: $e\n$st');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Diálogo de confirmação "Este é um mercado?" com "Sim" pré-selecionado
  // (botão em destaque/coral). Retorna true (Sim) ou false (Não).
  Future<bool> _confirmMarket(String envName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        title: const Text(
          AppStrings.marketConfirmTitle,
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          AppStrings.marketConfirmBody,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              AppStrings.marketConfirmNo,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          // "Sim" pré-selecionado como ação padrão/destacada.
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            autofocus: true,
            child: const Text(AppStrings.marketConfirmYes),
          ),
        ],
      ),
    );
    return result ?? true; // dispensar o diálogo mantém o padrão "Sim"
  }

}

// Trilho gradiente pink→azul para o slider premium
class _GradientTrack extends SliderTrackShape with BaseSliderTrackShape {
  const _GradientTrack();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    final radius = Radius.circular(trackRect.height / 2);

    // Trilho inativo (fundo)
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = const Color(0x33FFFFFF),
    );

    // Porção ativa: gradiente pink → azul
    final activeRect = Rect.fromLTRB(
        trackRect.left, trackRect.top, thumbCenter.dx, trackRect.bottom);
    if (activeRect.width > 0) {
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFFF6B82), AppColors.accent],
          ).createShader(trackRect),
      );
    }
  }
}

// Thumb glass com glow rosa para o slider premium
class _GlassThumb extends SliderComponentShape {
  const _GlassThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(24, 24);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;

    // Glow externo
    canvas.drawCircle(
      center,
      14,
      Paint()
        ..color = const Color(0x33FF6B82)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Fundo glass ultra-translúcido
    canvas.drawCircle(center, 11, Paint()..color = const Color(0x0DFFFFFF));

    // Borda rosa sutil
    canvas.drawCircle(
      center,
      11,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x66FF6B82) // pink 40%
        ..strokeWidth = 1.5,
    );

    // Reflexo interno (canto superior esquerdo)
    canvas.drawCircle(
      Offset(center.dx - 2, center.dy - 2),
      3,
      Paint()..color = const Color(0x4DFFFFFF), // white 30%
    );
  }
}

// Gradiente superior (preto→transparente) — legibilidade dos elementos que
// flutuam sobre o mapa. Envolvido em IgnorePointer no uso para não bloquear gestos.
class _TopScrim extends StatelessWidget {
  const _TopScrim();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x66000000), Color(0x00000000)], // preto ~40% → transparente
        ),
      ),
    );
  }
}

// Gradiente inferior (transparente→preto) — legibilidade do card de raio.
class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x73000000)], // transparente → preto ~45%
        ),
      ),
    );
  }
}

// Chip flutuante sobre o mapa com texto informativo
class _MapChip extends StatelessWidget {
  final String label;

  const _MapChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.gap6),
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated.withOpacity(0.92),
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Text(
          label,
          style: AppTypography.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

// ── Bottom sheet glass de seleção de estilo do pin (Fase 1) ─────────────────
// Duas opções lado a lado com miniatura REAL do pin. A opção selecionada ganha
// borda coral. Quando 3D está ativo, mostra a linha de imagem (escolher/remover).
class _PinStyleSheet extends StatefulWidget {
  final PinStyle initialStyle;
  final bool hasUserImage;
  final String classicThumbAsset; // teardrop verde (miniatura via Image.asset)
  final Future<Uint8List> Function() render3d;
  final Future<void> Function() onSelectClassic;
  final Future<void> Function() onSelect3D;
  final Future<bool> Function() onPickImage;
  final Future<void> Function() onRemoveImage;

  const _PinStyleSheet({
    required this.initialStyle,
    required this.hasUserImage,
    required this.classicThumbAsset,
    required this.render3d,
    required this.onSelectClassic,
    required this.onSelect3D,
    required this.onPickImage,
    required this.onRemoveImage,
  });

  @override
  State<_PinStyleSheet> createState() => _PinStyleSheetState();
}

class _PinStyleSheetState extends State<_PinStyleSheet> {
  late PinStyle _style;
  late bool _hasImage;
  Uint8List? _thumb3d;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _style    = widget.initialStyle;
    _hasImage = widget.hasUserImage;
    _loadThumb();
  }

  // Renderiza a miniatura 3D real (mesma composição que vai ao mapa).
  Future<void> _loadThumb() async {
    final bytes = await widget.render3d();
    if (mounted) setState(() => _thumb3d = bytes);
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    final ok = await widget.onPickImage();
    if (ok) {
      _hasImage = true;
      _style    = PinStyle.threeD;
      await _loadThumb();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    await widget.onRemoveImage();
    _hasImage = false;
    await _loadThumb();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      edges: GlassEdges.top,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Alça (grabber) do sheet.
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header UPPERCASE — padrão de seção do app.
              Text(
                AppStrings.pinStyleTitle.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textDisabled,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 14),
              // Duas opções lado a lado.
              Row(
                children: [
                  Expanded(
                    child: _PinChoiceCard(
                      label: AppStrings.pinStyleClassic,
                      selected: _style == PinStyle.classic,
                      // Miniatura real: teardrop verde (asset direto).
                      thumb: Image.asset(widget.classicThumbAsset,
                          fit: BoxFit.contain),
                      onTap: () {
                        setState(() => _style = PinStyle.classic);
                        widget.onSelectClassic();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PinChoiceCard(
                      label: AppStrings.pinStyle3D,
                      selected: _style == PinStyle.threeD,
                      // Miniatura real: plaquinha composta (bytes) ou spinner.
                      thumb: _thumb3d == null
                          ? const Center(
                              child: SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textDisabled),
                              ),
                            )
                          : Image.memory(_thumb3d!, fit: BoxFit.contain),
                      onTap: () {
                        setState(() => _style = PinStyle.threeD);
                        widget.onSelect3D();
                      },
                    ),
                  ),
                ],
              ),
              // Linha de imagem — só quando o estilo 3D está selecionado.
              if (_style == PinStyle.threeD) ...[
                const SizedBox(height: 18),
                Text(
                  AppStrings.pinImageLabel.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textDisabled,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Preview pequeno da imagem atual (ou vazio → arte padrão).
                    if (_hasImage && _thumb3d != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: Image.memory(_thumb3d!, width: 40, height: 52,
                              fit: BoxFit.contain),
                        ),
                      ),
                    // Botão escolher imagem.
                    Expanded(
                      child: GestureDetector(
                        onTap: _busy ? null : _pick,
                        child: Container(
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0x0DFFFFFF),
                            borderRadius: BorderRadius.circular(AppRadius.button),
                            border: Border.all(color: AppColors.border, width: 1),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.accent),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.image,
                                        color: AppColors.textSecondary, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      AppStrings.pinImageChoose,
                                      style: AppTypography.bodyMedium.copyWith(
                                          color: AppColors.textPrimary),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Ação remover imagem (volta à arte Sopro padrão).
                if (_hasImage)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton.icon(
                      onPressed: _busy ? null : _remove,
                      icon: const Icon(LucideIcons.trash2,
                          color: AppColors.textSecondary, size: 16),
                      label: Text(
                        AppStrings.pinImageRemove,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Card de uma opção de pin: miniatura real (~72px) + label. Borda coral quando
// selecionado; borda de vidro padrão caso contrário.
class _PinChoiceCard extends StatelessWidget {
  final String label;
  final bool selected;
  final Widget thumb; // miniatura real (~72px) — asset ou bytes compostos
  final VoidCallback onTap;

  const _PinChoiceCard({
    required this.label,
    required this.selected,
    required this.thumb,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 72, child: thumb),
            const SizedBox(height: 10),
            Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Resultado de busca retornado pelo Nominatim
class _SearchResult {
  final String displayName;
  final double lat;
  final double lon;

  const _SearchResult({
    required this.displayName,
    required this.lat,
    required this.lon,
  });
}
