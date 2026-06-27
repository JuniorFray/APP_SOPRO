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
// O usuário toca no mapa para posicionar o pin ou usa "Localização atual"
// para centrar o mapa na posição GPS real (via MethodChannel nativo).
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

  // Ponto selecionado pelo usuário no mapa; null enquanto nenhum foi tocado
  LatLng? _selectedPoint;
  bool _isSaving        = false;
  bool _loadingLocation = false;

  // Controlador do mapa — permite mover o centro programaticamente (ex: GPS)
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
                      // Callback de toque: atualiza o pin de seleção
                      onTap: (_, point) =>
                          setState(() => _selectedPoint = point),
                    ),
                    children: [
                      // Camada de tiles do OpenStreetMap (gratuito, sem API key)
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        // userAgentPackageName é obrigatório pela política do OSM
                        userAgentPackageName: 'com.sopro.sopro',
                      ),
                      // Pin de localização selecionada
                      if (_selectedPoint != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedPoint!,
                              // Anchor no topo do ícone para alinhar a ponta com o ponto
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

                  // Coordenadas do ponto selecionado (feedback visual)
                  if (_selectedPoint != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: Center(
                        child: _MapChip(
                          label:
                              '${_selectedPoint!.latitude.toStringAsFixed(5)}, '
                              '${_selectedPoint!.longitude.toStringAsFixed(5)}',
                          monospace: true,
                        ),
                      ),
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

  // Obtém a posição real via GPS nativo e centraliza o mapa no ponto obtido.
  // Pede permissão se ainda não foi concedida.
  Future<void> _onLocationButtonPressed() async {
    setState(() => _loadingLocation = true);

    final service = ref.read(nativeLocationServiceProvider);

    try {
      // Verifica permissão; solicita ao sistema se necessário
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
        // Zoom 16 mostra ~200 m de raio — adequado para criar geofences pequenos
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
      // Ao editar: mantém o ID original para fazer upsert (atualização)
      // Ao criar: string vazia → repositório gera UUID novo
      id: widget.environment?.id ?? '',
      name: _nameController.text.trim(),
      latitude: _selectedPoint!.latitude,
      longitude: _selectedPoint!.longitude,
      radiusMeters: double.parse(_radiusController.text),
      // Ao editar: preserva a data de criação original
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
      filled: true,
      fillColor: AppTheme.backgroundSurface,
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppTheme.backgroundElevated),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppTheme.accent),
      ),
      errorBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.red),
      ),
    );
  }
}

// Chip semi-transparente sobreposto ao mapa para instruções e coordenadas
class _MapChip extends StatelessWidget {
  final String label;
  final bool monospace;

  const _MapChip({required this.label, this.monospace = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          // ignore: deprecated_member_use
          color: AppTheme.backgroundElevated.withOpacity(0.92),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: monospace ? 11 : 13,
            fontFamily: monospace ? 'monospace' : null,
          ),
        ),
      ),
    );
  }
}
