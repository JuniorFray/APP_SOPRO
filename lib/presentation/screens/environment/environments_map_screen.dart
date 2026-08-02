// EnvironmentsMapScreen — tela dedicada, em tela cheia, só com o mapa noturno
// (map_style_sopro.json) mostrando TODOS os ambientes cadastrados como
// marcadores interativos. Acessível pelo ícone de mapa na aba Ambientes.
//
// Reusa a lógica de marcadores do EnvironmentMarkersMixin (mesma de
// add_environment_screen). Diferença: aqui os marcadores são INTERATIVOS —
// tocar mostra um bottom sheet com o nome e um botão "Ver detalhes" que abre a
// EnvironmentDetailScreen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/strings.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/environment_entity.dart';
import '../../../infrastructure/location/location_guard.dart';
import '../../providers/database_provider.dart';
import '../../providers/location_providers.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/map/environment_markers_layer.dart';
import 'environment_detail_screen.dart';

class EnvironmentsMapScreen extends ConsumerStatefulWidget {
  const EnvironmentsMapScreen({super.key});

  @override
  ConsumerState<EnvironmentsMapScreen> createState() =>
      _EnvironmentsMapScreenState();
}

class _EnvironmentsMapScreenState extends ConsumerState<EnvironmentsMapScreen>
    with EnvironmentMarkersMixin<EnvironmentsMapScreen> {
  // Estilo do mapa (string) — asset:// não é confiável no maplibre_gl ^0.22.0.
  String? _mapStyleJson;
  ml.MapLibreMapController? _mapController;

  // Estilo de pin ativo (preferência global) — informado ao mixin.
  PinStyle _pinStyle = PinStyle.classic;
  @override
  PinStyle get markerPinStyle => _pinStyle;

  // Ambientes carregados uma vez (para resolver o toque → entidade → detalhe).
  List<EnvironmentEntity> _envs = const [];

  // Centro inicial: GPS conhecido → 1º ambiente → São Paulo (fallback urbano).
  double _centerLat = -23.5505;
  double _centerLon = -46.6333;

  bool _ready = false;
  // Visão do mapa: false = 2D (plano), true = 3D (prédios extrudados + tilt).
  bool _is3D = false;
  // Botão de localização em progresso (busca de fix GPS).
  bool _loadingLocation = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  // Carrega estilo do mapa, preferência de pin, ambientes e o centro inicial.
  Future<void> _init() async {
    final style = await rootBundle.loadString('assets/map_style_sopro.json');
    final pinStyle = await loadPinStyle();
    final envs = await ref.read(environmentRepositoryProvider).getAll();

    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('last_known_lat') ?? 0.0;
    final lon = prefs.getDouble('last_known_lon') ?? 0.0;
    if (lat != 0.0 || lon != 0.0) {
      _centerLat = lat;
      _centerLon = lon;
    } else if (envs.isNotEmpty) {
      _centerLat = envs.first.latitude;
      _centerLon = envs.first.longitude;
    }

    if (!mounted) return;
    setState(() {
      _mapStyleJson = style;
      _pinStyle = pinStyle;
      _envs = envs;
      _ready = true;
    });
  }

  // Toque no mapa: consulta a camada de ambientes no ponto tocado. Se houver um
  // marcador ali, abre o bottom sheet com o nome + "Ver detalhes".
  Future<void> _onMapClick(point, ml.LatLng coords) async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    final feats = await ctrl.queryRenderedFeatures(
        point, [EnvironmentMarkersMixin.kEnvLayerId], null);
    if (feats.isEmpty) return;
    final props = (feats.first as Map)['properties'] as Map?;
    final id = props?['id'] as String?;
    if (id == null) return;
    final env = _envs.where((e) => e.id == id).firstOrNull;
    if (env != null && mounted) _showEnvSheet(env);
  }

  // Bottom sheet simples: nome do ambiente + botão para o detalhe.
  void _showEnvSheet(EnvironmentEntity env) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => GlassSurface(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: AppColors.accent, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        env.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      pushScreen(context,
                          EnvironmentDetailScreen(environment: env));
                    },
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Ver detalhes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Alterna 2D <-> 3D: troca a visibilidade das camadas de prédio e inclina a
  // câmera (50° em 3D, plano em 2D). Mesma mecânica do add_environment.
  Future<void> _toggle3D() async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    final next = !_is3D;
    setState(() => _is3D = next);
    await ctrl.setLayerVisibility('building-3d', next);
    await ctrl.setLayerVisibility('building', !next);
    await ctrl.animateCamera(
      ml.CameraUpdate.tiltTo(next ? 50.0 : 0.0),
      duration: const Duration(milliseconds: 450),
    );
  }

  // Recentraliza a câmera na localização atual do usuário (só move a câmera —
  // esta tela não tem pin de seleção).
  Future<void> _onLocationButtonPressed() async {
    setState(() => _loadingLocation = true);
    final service = ref.read(nativeLocationServiceProvider);
    try {
      bool ok = await service.checkPermission();
      if (!ok) ok = await service.requestPermission();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(AppStrings.locationPermissionDenied),
            backgroundColor: AppTheme.backgroundElevated,
          ));
        }
        return;
      }
      if (!mounted) return;
      final pos = await getLocationWithGpsCheck(context, service);
      if (!mounted) return;
      if (pos != null) {
        await _mapController?.animateCamera(ml.CameraUpdate.newLatLngZoom(
            ml.LatLng(pos.latitude, pos.longitude), 16.0));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(AppStrings.locationError),
          backgroundColor: AppTheme.backgroundElevated,
        ));
      }
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  // Botão glass circular (mesmo visual dos controles do add_environment).
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
            width: size, height: size, child: Center(child: child)),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }

  // Botão de alternância 2D/3D — mostra o rótulo do PRÓXIMO estado.
  Widget _build3DButton() => _glassCircleButton(
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

  // Botão de localização atual — recentraliza no GPS.
  Widget _buildGpsButton() => _glassCircleButton(
        onTap: _loadingLocation ? null : _onLocationButtonPressed,
        tooltip: AppStrings.useCurrentLocation,
        child: _loadingLocation
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.textSecondary),
              )
            : const Icon(LucideIcons.locateFixed,
                color: AppColors.textSecondary, size: 20),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: const GlassSurface(
          borderRadius: BorderRadius.zero,
          edges: GlassEdges.bottom,
          child: SizedBox.expand(),
        ),
        title: const Text(
          'Mapa',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: !_ready
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 2.5,
                strokeCap: StrokeCap.round,
              ),
            )
          : Stack(children: [
              ml.MapLibreMap(
              styleString: _mapStyleJson!,
              initialCameraPosition: ml.CameraPosition(
                target: ml.LatLng(_centerLat, _centerLon),
                zoom: 13.0,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
              },
              onStyleLoadedCallback: () async {
                final c = _mapController;
                if (c == null) return;
                // Sprites base + fonte com TODOS os ambientes + camada interativa.
                await registerBaseEnvImages(c);
                await syncEnvironmentSource(c); // skipId null = desenha todos
                await addEnvironmentLayer(c, interactive: false);
                // Nudge de câmera: maplibre_gl renderiza o 1º frame incompleto.
                await c.animateCamera(
                  ml.CameraUpdate.zoomBy(0.01),
                  duration: const Duration(milliseconds: 1),
                );
              },
              onMapClick: _onMapClick,
              compassEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              myLocationEnabled: false,
              trackCameraPosition: false,
              ),
              // Controles flutuantes (canto inferior direito): 2D/3D + localização.
              Positioned(
                right: 16,
                bottom: 32,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _build3DButton(),
                    const SizedBox(height: 12),
                    _buildGpsButton(),
                  ],
                ),
              ),
            ]),
    );
  }
}
