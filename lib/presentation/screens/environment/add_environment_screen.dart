import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/environment_entity.dart';
import '../../providers/database_provider.dart';
import '../../providers/location_providers.dart';

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

  const AddEnvironmentScreen({super.key, this.environment});

  @override
  ConsumerState<AddEnvironmentScreen> createState() =>
      _AddEnvironmentScreenState();
}

class _AddEnvironmentScreenState extends ConsumerState<AddEnvironmentScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _radiusController;
  final _searchCtrl = TextEditingController(); // campo de busca por endereço

  // Ponto selecionado pelo usuário no mapa; null enquanto nenhum foi tocado
  LatLng? _selectedPoint;
  bool _isSaving        = false;
  bool _loadingLocation = false;

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
    // Pré-preenche com os dados do ambiente ao editar; vazio ao criar
    _nameController = TextEditingController(
      text: widget.environment?.name ?? '',
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
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _radiusController.dispose();
    _searchCtrl.dispose();
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
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
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
                          ? Colors.white
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
            // Campo nome do ambiente
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextFormField(
                controller: _nameController,
                style: const TextStyle(color: AppTheme.textPrimary),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? AppStrings.environmentNameRequired
                    : null,
                decoration: _inputDecoration(
                  label: AppStrings.environmentNameLabel,
                  hint: AppStrings.environmentNameHint,
                ),
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

                  // ── Barra de busca por endereço (Nominatim) ─────────────────
                  // Posicionada no topo do mapa, à esquerda do botão de GPS
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 60, // espaço para o botão GPS
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Campo de busca
                        Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          color: AppTheme.backgroundElevated,
                          child: Row(
                            children: [
                              const SizedBox(width: 10),
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
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 13,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: AppStrings.searchAddressHint,
                                    hintStyle: TextStyle(
                                      color: AppTheme.textDisabled,
                                      fontSize: 13,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding:
                                        EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) => _searchAddress(),
                                  onChanged: (v) {
                                    // Limpa resultados ao apagar o campo
                                    if (v.isEmpty && _searchResults.isNotEmpty) {
                                      setState(() => _searchResults = []);
                                    }
                                  },
                                ),
                              ),
                              // Botão para limpar o campo
                              if (_searchCtrl.text.isNotEmpty)
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _searchCtrl.clear();
                                    _searchResults = [];
                                  }),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
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

                        // Lista de resultados da busca
                        if (_searchResults.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.backgroundSurface,
                              borderRadius: BorderRadius.circular(8),
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
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 12,
                                    ),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: TextFormField(
                controller: _radiusController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  return (n == null || n <= 0) ? AppStrings.radiusInvalid : null;
                },
                decoration: _inputDecoration(
                  label: AppStrings.radiusLabel,
                  suffix: 'm',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Busca um endereço via Nominatim (OpenStreetMap) e exibe os resultados.
  // Nominatim é gratuito e não exige API key; requer User-Agent identificado.
  Future<void> _searchAddress() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searchResults = [];
    });

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);

      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q':               query,
          'format':          'json',
          'limit':           '5',
          'addressdetails':  '0',
          'accept-language': 'pt-BR,pt',
        },
      );

      final request = await client.getUrl(uri);
      // Nominatim exige User-Agent para identificar o app — política de uso justo
      request.headers.set(
        'User-Agent',
        'Sopro/0.1 (Android; github.com/JuniorFray/APP_SOPRO)',
      );

      final response = await request.close();
      final body     = await response.transform(utf8.decoder).join();
      client.close();

      if (!mounted) return;

      final raw = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
      final results = raw
          .map((r) => _SearchResult(
                displayName: r['display_name'] as String? ?? '',
                lat: double.tryParse(r['lat'] as String? ?? '') ?? 0.0,
                lon: double.tryParse(r['lon'] as String? ?? '') ?? 0.0,
              ))
          .where((r) => r.lat != 0.0 && r.lon != 0.0)
          .toList();

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

    final entity = EnvironmentEntity(
      id: widget.environment?.id ?? '',
      name: _nameController.text.trim(),
      latitude: _selectedPoint!.latitude,
      longitude: _selectedPoint!.longitude,
      radiusMeters: double.parse(_radiusController.text),
      createdAt: widget.environment?.createdAt ?? DateTime.now(),
    );

    await ref.read(environmentRepositoryProvider).save(entity);

    if (mounted) Navigator.pop(context);
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    String? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffix,
      labelStyle: const TextStyle(color: AppTheme.textSecondary),
      hintStyle: const TextStyle(color: AppTheme.textDisabled),
      suffixStyle: const TextStyle(color: AppTheme.textSecondary),
      filled: true,
      fillColor: AppTheme.backgroundSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated.withOpacity(0.92),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
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
