import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/entities/environment_entity.dart';
import '../../../infrastructure/geocoding/geocoding_repository.dart';
import '../../../infrastructure/location/location_guard.dart';
import '../../providers/database_provider.dart';
import '../../providers/location_providers.dart';
import '../../providers/voice_providers.dart';
import '../../widgets/glass_surface.dart';
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

  const AddEnvironmentScreen({
    super.key,
    this.environment,
    this.initialName,
    this.initialPosition,
  });

  @override
  ConsumerState<AddEnvironmentScreen> createState() =>
      _AddEnvironmentScreenState();
}

class _AddEnvironmentScreenState extends ConsumerState<AddEnvironmentScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _radiusController;
  final _searchCtrl       = TextEditingController(); // campo de busca por endereço
  final _searchFocusNode  = FocusNode();             // isola foco do campo de busca

  // Ponto selecionado pelo usuário no mapa; null enquanto nenhum foi tocado
  LatLng? _selectedPoint;
  bool _isSaving        = false;
  bool _loadingLocation = false;
  // true enquanto o AudioRecorder está gravando para preencher o nome
  bool _recordingName   = false;
  // Timer de auto-stop para gravação de nome (7 s máximo)
  Timer? _nameRecordTimer;
  // Debounce de 400 ms para evitar buscas a cada tecla digitada
  Timer? _searchDebounce;

  // Estado da busca por endereço via Nominatim
  bool _searching = false;
  List<_SearchResult> _searchResults = [];

  // Controlador do mapa — permite mover o centro programaticamente
  final _mapController = MapController();

  // Centro inicial do mapa: São Paulo (referência urbana padrão para o Brasil)
  static const _defaultCenter = LatLng(-23.5505, -46.6333);

  // Animação de pulso do marcador de mapa
  late final AnimationController _markerPulseCtrl;
  late final Animation<double>   _markerPulseAnim;

  // Valor do slider de raio (50–1000 m), sincronizado com _radiusController
  double _radiusSlider = 100.0;

  bool get _isEditing => widget.environment != null;

  @override
  void initState() {
    super.initState();
    // Pré-preenche com os dados do ambiente ao editar; initialName (voz) ao criar; vazio caso contrário
    _nameController = TextEditingController(
      text: widget.environment?.name ?? widget.initialName ?? '',
    );
    final initialRadius = widget.environment != null
        ? widget.environment!.radiusMeters
        : (double.tryParse(AppStrings.radiusDefault) ?? 100.0);
    _radiusSlider = initialRadius.clamp(50.0, 1000.0);
    _radiusController = TextEditingController(text: _radiusSlider.toInt().toString());

    // Pulso animado do pin de localização no mapa
    _markerPulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _markerPulseAnim = Tween<double>(begin: 0.6, end: 1.2).animate(
      CurvedAnimation(parent: _markerPulseCtrl, curve: Curves.easeInOut),
    );
    if (widget.environment != null) {
      // Posiciona o pin na localização existente
      _selectedPoint = LatLng(
        widget.environment!.latitude,
        widget.environment!.longitude,
      );
      // Centraliza o mapa após o primeiro frame (MapController não está pronto no initState)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(_selectedPoint!, 15.0);
      });
    } else if (widget.initialPosition != null) {
      // GPS pré-obtido via comando de voz — posiciona pin sem clique do usuário
      _selectedPoint = widget.initialPosition;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(widget.initialPosition!, 15.0);
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
            _mapController.move(pos, 15.0);
          }
        } catch (_) {}
      });
      // Atualiza SharedPreferences com GPS fresco para garantir coords corretas na busca.
      // Só tenta se GPS estiver ligado — evita chamada desnecessária ao FusedProvider.
      final locSvc = ref.read(nativeLocationServiceProvider);
      locSvc.isLocationEnabled().then((enabled) {
        if (!enabled) return;
        locSvc.getCurrentPosition().then((pos) async {
          if (pos != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble('last_known_lat', pos.latitude);
            await prefs.setDouble('last_known_lon', pos.longitude);
          }
        }).catchError((_) {});
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _nameRecordTimer?.cancel();
    _searchDebounce?.cancel();
    _markerPulseCtrl.dispose();
    ref.read(voiceServiceProvider).cancelRecording();
    _nameController.dispose();
    _radiusController.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.backgroundPrimary,
      appBar: _buildAppBar(),
      body: Form(
        key: _formKey,
        child: Stack(
          children: [
            // Mapa full-screen — ocupa toda a área do body
            Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _defaultCenter,
                  initialZoom: 12.0,
                  onTap: (_, point) => setState(() {
                    _selectedPoint = point;
                    _searchResults = [];
                  }),
                ),
                children: [
                  // Tiles Carto Dark Matter
                  TileLayer(
                    urlTemplate:
                        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.sopro.sopro',
                  ),
                  // Marcador animado
                  if (_selectedPoint != null)
                    AnimatedBuilder(
                      animation: _markerPulseAnim,
                      builder: (_, __) => MarkerLayer(
                        markers: [
                          Marker(
                            point: _selectedPoint!,
                            alignment: Alignment.topCenter,
                            child: _buildMarker(),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Card glass superior: nome + busca (flutua sobre o mapa)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopCard(context),
            ),

            // Instrução central quando nenhum ponto selecionado
            if (_selectedPoint == null)
              const Positioned(
                bottom: 220,
                left: 16,
                right: 16,
                child: _MapChip(label: AppStrings.mapTapInstruction),
              ),

            // Botão GPS — canto inferior direito acima do painel
            Positioned(
              bottom: 210,
              right: 12,
              child: _buildGpsButton(),
            ),

            // Painel glass inferior: raio + slider + salvar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomPanel(context),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      // Liquid Glass — delega ao primitivo central GlassSurface.
      flexibleSpace: const GlassSurface(
        borderRadius: BorderRadius.zero,
        edges: GlassEdges.bottom,
        child: SizedBox.expand(),
      ),
      title: Text(
        _isEditing ? AppStrings.editEnvironmentTitle : AppStrings.addEnvironmentTitle,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      actions: [
        if (_isSaving)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textPrimary,
              ),
            ),
          )
        else
          TextButton(
            onPressed: _selectedPoint != null ? _submit : null,
            child: Text(
              AppStrings.save,
              style: TextStyle(
                color: _selectedPoint != null
                    ? AppColors.textPrimary
                    : AppColors.textDisabled,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  // Card glass flutuante com campo de nome e busca de endereço
  Widget _buildTopCard(BuildContext context) {
    return GlassSurface(
      borderRadius: BorderRadius.zero,
      edges: GlassEdges.bottom,
      child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Campo de nome do ambiente
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? AppStrings.environmentNameRequired
                        : null,
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: AppStrings.environmentNameLabel,
                      hintText: _recordingName
                          ? AppStrings.voiceFillHint
                          : AppStrings.environmentNameHint,
                      hintStyle: AppTypography.bodySmall
                          .copyWith(color: AppColors.textDisabled),
                      labelStyle: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                      floatingLabelStyle: AppTypography.caption.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                      filled: true,
                      fillColor: const Color(0x1AFFFFFF),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: const BorderSide(
                            color: AppColors.border, width: 0.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: const BorderSide(
                            color: AppColors.accent, width: 1.5),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: const BorderSide(
                            color: AppColors.danger, width: 1.0),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: const BorderSide(
                            color: AppColors.danger, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
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
                  const SizedBox(height: 10),
                  // Campo de busca por endereço
                  Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF),
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      border:
                          Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        _searching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent,
                                ),
                              )
                            : const Icon(Icons.search,
                                color: AppColors.textSecondary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            focusNode: _searchFocusNode,
                            style: AppTypography.bodyMedium
                                .copyWith(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              hintText: AppStrings.searchAddressHint,
                              hintStyle: AppTypography.bodyMedium
                                  .copyWith(color: AppColors.textDisabled),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12),
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
                              child: Icon(Icons.clear,
                                  size: 16,
                                  color: AppColors.textDisabled),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Resultados da busca
                  if (_searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundCard,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border:
                            Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _searchResults.take(4).map((r) {
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12),
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
          ),
    );
  }

  // Pin animado com halo + pulso
  Widget _buildMarker() {
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        // Anel de pulso animado
        Positioned(
          bottom: 36,
          child: Transform.scale(
            scale: _markerPulseAnim.value,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border:
                    Border.all(color: const Color(0x80FF6B82), width: 2),
              ),
            ),
          ),
        ),
        // Halo fixo
        Positioned(
          bottom: 36,
          child: Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x33FF6B82),
            ),
          ),
        ),
        // Ícone do pin com sombra rosa
        const Icon(
          Icons.location_pin,
          color: Color(0xFFFF6B82),
          size: 44,
          shadows: [
            Shadow(
              color: Color(0x66FF6B82),
              blurRadius: 12,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ],
    );
  }

  // Botão de localização atual — glass mini FAB
  Widget _buildGpsButton() {
    return FloatingActionButton.small(
      onPressed: _loadingLocation ? null : _onLocationButtonPressed,
      backgroundColor: AppColors.backgroundCard,
      tooltip: AppStrings.useCurrentLocation,
      heroTag: 'gps_fab',
      child: _loadingLocation
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textSecondary,
              ),
            )
          : const Icon(Icons.my_location, color: AppColors.textSecondary),
    );
  }

  // Painel glass inferior: raio + slider premium + botão salvar
  Widget _buildBottomPanel(BuildContext context) {
    return GlassSurface(
      borderRadius: BorderRadius.zero,
      edges: GlassEdges.top,
      child: SafeArea(
        top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Raio: label + valor numérico
                  Row(
                    children: [
                      Text(
                        AppStrings.radiusLabel,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      Text(
                        '${_radiusSlider.toInt()} m',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  // Slider premium: trilho gradiente pink→azul, thumb glass
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      overlayColor: const Color(0x33FF6B82),
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
                  const SizedBox(height: 12),
                  // Botão Salvar — gradiente pink-red, desabilitado sem ponto
                  SizedBox(
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
                                ? const [Color(0xFFFF6178), Color(0xFFF04666)]
                                : const [Color(0x66FF6178), Color(0x66F04666)],
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.button),
                          boxShadow: _selectedPoint != null
                              ? const [
                                  BoxShadow(
                                    color: Color(0x40FF4566),
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
                  ),
                  const SizedBox(height: 4),
                ],
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
  void _selectResult(_SearchResult result) {
    final point = LatLng(result.lat, result.lon);
    setState(() {
      _selectedPoint  = point;
      _searchResults  = [];
    });
    _searchCtrl.clear();
    _mapController.move(point, 15.0);
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
        _mapController.move(point, 16.0);
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

    // Gera o UUID aqui para que seja conhecido antes e depois do save(),
    // permitindo registrar o geofence nativo com o ID correto.
    final id = widget.environment?.id.isNotEmpty == true
        ? widget.environment!.id
        : const Uuid().v4();

    final entity = EnvironmentEntity(
      id: id,
      name: _nameController.text.trim(),
      latitude: _selectedPoint!.latitude,
      longitude: _selectedPoint!.longitude,
      radiusMeters: double.parse(_radiusController.text),
      createdAt: widget.environment?.createdAt ?? DateTime.now(),
    );

    await ref.read(environmentRepositoryProvider).save(entity);

    // Registra/atualiza o geofence nativo imediatamente após salvar.
    // Sem isso, o ambiente só seria monitorado após o próximo startup do app.
    try {
      await ref.read(nativeGeofenceServiceProvider).addSingleGeofence(entity);
    } catch (e) {
      // Falha silenciosa: o GPS stream do GeofenceManager ainda monitora em foreground
      debugPrint('[AddEnvironmentScreen] Falha ao registrar geofence nativo: $e');
    }

    if (mounted) Navigator.pop(context);
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
            colors: [Color(0xFFFF6B82), Color(0xFF4F8CFF)],
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
