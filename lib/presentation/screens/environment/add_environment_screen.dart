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
import '../../providers/database_provider.dart';
import '../../providers/location_providers.dart';
import '../../providers/voice_providers.dart';
import '../../widgets/sopro_text_field.dart';

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

  bool get _isEditing => widget.environment != null;

  @override
  void initState() {
    super.initState();
    // Pré-preenche com os dados do ambiente ao editar; initialName (voz) ao criar; vazio caso contrário
    _nameController = TextEditingController(
      text: widget.environment?.name ?? widget.initialName ?? '',
    );
    _radiusController = TextEditingController(
      text: widget.environment != null
          ? widget.environment!.radiusMeters.toStringAsFixed(0)
          : AppStrings.radiusDefault,
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
      // Atualiza SharedPreferences com GPS fresco para garantir coords corretas na busca
      ref.read(nativeLocationServiceProvider).getCurrentPosition().then((pos) async {
        if (pos != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('last_known_lat', pos.latitude);
          await prefs.setDouble('last_known_lon', pos.longitude);
        }
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _nameRecordTimer?.cancel();
    _searchDebounce?.cancel();
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
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        // Título diferente conforme o modo de uso
        title: Text(
          _isEditing
              ? AppStrings.editEnvironmentTitle
              : AppStrings.addEnvironmentTitle,
        ),
        actions: [
          _isSaving
              ? const Padding(
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
              : TextButton(
                  // Salvar só habilitado quando um ponto foi selecionado
                  onPressed: _selectedPoint != null ? _submit : null,
                  child: Text(
                    AppStrings.save,
                    style: TextStyle(
                      color: _selectedPoint != null
                          ? AppColors.textPrimary
                          : AppTheme.textDisabled,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Campo nome do ambiente com botão de microfone para ditar o nome
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
              child: SoproTextField(
                controller: _nameController,
                label: AppStrings.environmentNameLabel,
                hint: _recordingName
                    ? AppStrings.voiceFillHint
                    : AppStrings.environmentNameHint,
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? AppStrings.environmentNameRequired
                    : null,
                suffixIcon: _recordingName
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.sm),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.accent,
                          ),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.mic_outlined,
                            color: AppTheme.accent, size: 20),
                        tooltip: AppStrings.voiceMicTooltip,
                        onPressed: _recordForName,
                      ),
              ),
            ),

            // Campo de busca por endereço + lista de resultados (fora do mapa)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    color: AppTheme.backgroundElevated,
                    child: Row(
                      children: [
                        const SizedBox(width: AppSpacing.gap10),
                        _searching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.accent,
                                ),
                              )
                            : const Icon(
                                Icons.search,
                                color: AppTheme.textSecondary,
                                size: 18,
                              ),
                        const SizedBox(width: AppSpacing.gap6),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            focusNode: _searchFocusNode,
                            style: AppTypography.bodyMedium.copyWith(color: AppTheme.textPrimary),
                            decoration: InputDecoration(
                              hintText: AppStrings.searchAddressHint,
                              hintStyle: AppTypography.bodyMedium.copyWith(color: AppTheme.textDisabled),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: AppSpacing.gap10),
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
                              padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                              child: Icon(
                                Icons.clear,
                                size: 16,
                                color: AppTheme.textDisabled,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundSurface,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _searchResults.take(4).map((r) {
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            leading: const Icon(
                              Icons.location_on_outlined,
                              color: AppTheme.accent,
                              size: 18,
                            ),
                            title: Text(
                              r.displayName,
                              style: AppTypography.bodySmall.copyWith(color: AppTheme.textPrimary),
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

            // Mapa interativo (ocupa a maior parte da tela)
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _defaultCenter,
                      initialZoom: 12.0,
                      // Callback de toque: atualiza o pin e limpa busca
                      onTap: (_, point) => setState(() {
                        _selectedPoint = point;
                        _searchResults = [];
                      }),
                    ),
                    children: [
                      // Camada de tiles do OpenStreetMap (gratuito, sem API key)
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.sopro.sopro',
                      ),
                      // Pin de localização selecionada
                      if (_selectedPoint != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedPoint!,
                              // Anchor no topo do ícone para alinhar com o ponto
                              alignment: Alignment.topCenter,
                              child: const Icon(
                                Icons.location_pin,
                                color: AppTheme.accent,
                                size: 44,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  // Instrução exibida enquanto nenhum ponto está selecionado
                  if (_selectedPoint == null)
                    const Positioned(
                      bottom: 72,
                      left: 16,
                      right: 16,
                      child: _MapChip(label: AppStrings.mapTapInstruction),
                    ),

                  // Botão "Localização atual" — usa GPS nativo via MethodChannel
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: FloatingActionButton.small(
                      onPressed: _loadingLocation ? null : _onLocationButtonPressed,
                      backgroundColor: AppTheme.backgroundElevated,
                      tooltip: AppStrings.useCurrentLocation,
                      child: _loadingLocation
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.textSecondary,
                              ),
                            )
                          : const Icon(
                              Icons.my_location,
                              color: AppTheme.textSecondary,
                            ),
                    ),
                  ),
                ],
              ),
            ),

            // Campo raio com sufixo "m"
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
              child: SoproTextField(
                controller: _radiusController,
                label: AppStrings.radiusLabel,
                suffixText: 'm',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  return (n == null || n <= 0) ? AppStrings.radiusInvalid : null;
                },
              ),
            ),
          ],
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

      final pos = await service.getCurrentPosition();
      if (!mounted) return;

      if (pos != null) {
        final point = LatLng(pos.latitude, pos.longitude);
        setState(() => _selectedPoint = point);
        _mapController.move(point, 16.0);
      } else {
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
