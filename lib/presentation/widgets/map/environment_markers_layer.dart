// EnvironmentMarkersMixin — lógica COMPARTILHADA de desenhar todos os ambientes
// cadastrados como marcadores numa MapLibreMap.
//
// Extraída de add_environment_screen.dart (fluxo criar/editar) para ser reusada
// também pela tela dedicada de mapa (EnvironmentsMapScreen) — sem duplicar o
// código. Cada tela mistura este mixin, fornece o estilo de pin ativo
// (markerPinStyle) e chama registerBaseEnvImages → syncEnvironmentSource →
// addEnvironmentLayer no onStyleLoaded do mapa.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/database_provider.dart';

// Estilo do pin (Fase 1 — pins personalizados). GLOBAL, persistido em prefs.
//   classic → teardrop em PNG (verde = seleção / azul = existentes)
//   threeD  → plaquinha 3D (arte Sopro padrão OU foto do ambiente)
enum PinStyle { classic, threeD }

// Chave da preferência global do estilo do pin ('classic' | '3d').
const String kPinStylePref = 'map_pin_style';

// Lê o estilo do pin salvo (default clássico em erro/ausência).
Future<PinStyle> loadPinStyle() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kPinStylePref) == '3d'
        ? PinStyle.threeD
        : PinStyle.classic;
  } catch (_) {
    return PinStyle.classic;
  }
}

mixin EnvironmentMarkersMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  // Fonte GeoJSON + camada de símbolos dos ambientes existentes. Cada feature
  // carrega 'icon' (sprite data-driven), 'id' e 'name' (para o toque identificar
  // o ambiente na tela de mapa).
  static const String kEnvSrcId   = 'sopro_env_src';
  static const String kEnvLayerId = 'sopro_env_layer';
  bool _envSrcAdded   = false;
  bool _envLayerAdded = false;
  // Ambientes que já tiveram um sprite 3D próprio registrado ('env_pin_<id>').
  final Set<String> registeredEnvImages = {};

  // Estilo de pin ativo — a tela host informa (add_environment usa a seleção
  // atual; a tela de mapa usa a preferência global carregada).
  PinStyle get markerPinStyle;
  // Tamanho FIXO de todos os pins (âncora bottom, altura manda). 0.17 dá o mesmo
  // tamanho visual em clássico e 3D (PNGs ~512px).
  double get markerIconSize => 0.17;

  // Registra os sprites base usados pela camada de ambientes: teardrop azul
  // (clássico) e a plaquinha Sopro padrão (3D sem foto). Chamar no onStyleLoaded.
  Future<void> registerBaseEnvImages(ml.MapLibreMapController ctrl) async {
    await ctrl.addImage(
        'pin_teardrop_azul', await _loadAssetBytes('assets/pin_teardrop_azul.png'));
    await ctrl.addImage(
        'pin_3d_sopro', await _loadAssetBytes('assets/pin_3d_sopro.png'));
  }

  // Carrega TODOS os ambientes e monta a fonte GeoJSON. [skipId] pula um ambiente
  // (add_environment pula o em foco para não duplicar a seleção; a tela de mapa
  // passa null = desenha todos). No 3D com foto, registra o sprite próprio 1x.
  Future<void> syncEnvironmentSource(ml.MapLibreMapController ctrl,
      {String? skipId}) async {
    final envs = await ref.read(environmentRepositoryProvider).getAll();
    final is3d = markerPinStyle == PinStyle.threeD;
    final features = <Map<String, dynamic>>[];

    for (final e in envs) {
      if (e.id == skipId) continue;

      String icon;
      if (!is3d) {
        icon = 'pin_teardrop_azul'; // clássico: azul para todos os existentes
      } else if (e.pinImagePath != null && File(e.pinImagePath!).existsSync()) {
        icon = 'env_pin_${e.id}';
        if (!registeredEnvImages.contains(e.id)) {
          await ctrl.addImage(icon, await render3dPinBytes(e.pinImagePath));
          registeredEnvImages.add(e.id);
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
        // 'id'/'name' consumidos pelo toque na tela de mapa (queryRenderedFeatures).
        'properties': {'icon': icon, 'id': e.id, 'name': e.name},
      });
    }
    final fc = {'type': 'FeatureCollection', 'features': features};

    if (_envSrcAdded) {
      await ctrl.setGeoJsonSource(kEnvSrcId, fc);
    } else {
      await ctrl.addGeoJsonSource(kEnvSrcId, fc);
      _envSrcAdded = true;
    }
  }

  // Adiciona a camada de símbolos. [interactive] = false no add_environment (só
  // referência, o toque no mapa cria/move a seleção); true na tela de mapa.
  Future<void> addEnvironmentLayer(ml.MapLibreMapController ctrl,
      {required bool interactive}) async {
    if (_envLayerAdded) return;
    await ctrl.addSymbolLayer(kEnvSrcId, kEnvLayerId, _envLayerProps(),
        enableInteraction: interactive);
    _envLayerAdded = true;
  }

  // Remove a camada (mantém a fonte) — usado ao trocar de estilo de pin.
  Future<void> removeEnvironmentLayer(ml.MapLibreMapController ctrl) async {
    if (!_envLayerAdded) return;
    await ctrl.removeLayer(kEnvLayerId);
    _envLayerAdded = false;
  }

  // Propriedades da camada: sprite por feature ('icon'), âncora bottom, tamanho
  // FIXO. Opacidade < 1 no 3D diferencia dos pins de seleção sem mudar a cor.
  ml.SymbolLayerProperties _envLayerProps() {
    final is3d = markerPinStyle == PinStyle.threeD;
    return ml.SymbolLayerProperties(
      iconImage:           ['get', 'icon'],
      iconAnchor:          'bottom',
      iconAllowOverlap:    true,
      iconIgnorePlacement: true,
      iconOpacity:         is3d ? 0.85 : 1.0,
      iconSize:            markerIconSize,
    );
  }

  // ── Composição da plaquinha 3D (moldura + foto) ───────────────────────────
  // Compõe a plaquinha 3D como PNG. Sem foto → arte Sopro pronta. Com foto →
  // desenha a foto recortada num rounded-rect que preenche a moldura e sobrepõe
  // a moldura vazia por cima.
  Future<Uint8List> render3dPinBytes(String? userImagePath) async {
    if (userImagePath == null || !File(userImagePath).existsSync()) {
      final data = await rootBundle.load('assets/pin_3d_sopro.png');
      return data.buffer.asUint8List();
    }

    final frameData = await rootBundle.load('assets/pin_3d_frame.png');
    final frameImg  = await _decodeImage(frameData.buffer.asUint8List());
    final userImg   = await _decodeImage(await File(userImagePath).readAsBytes());

    // Dimensões nativas dos PNGs (395x512). Janela interna medida no canal alpha
    // da moldura (+ leve sangria sob a borda para não deixar fresta).
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

  // Retângulo-fonte para desenhar [iw]x[ih] cobrindo [dest] no estilo BoxFit.cover.
  Rect _coverSrcRect(double iw, double ih, Rect dest) {
    final da = dest.width / dest.height;
    final ia = iw / ih;
    if (ia > da) {
      final w = ih * da; // imagem mais larga → corta laterais
      return Rect.fromLTWH((iw - w) / 2, 0, w, ih);
    }
    final hh = iw / da; // imagem mais alta → corta topo/base
    return Rect.fromLTWH(0, (ih - hh) / 2, iw, hh);
  }

  // Lê os bytes crus de um asset PNG (sprite pronto, sem composição).
  Future<Uint8List> _loadAssetBytes(String asset) async {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List();
  }
}
