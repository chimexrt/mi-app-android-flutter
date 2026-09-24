import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
  home: const Galeria(),
));

class Galeria extends StatefulWidget {
  const Galeria({super.key});
  @override
  State<Galeria> createState() => _GaleriaState();
}

class _GaleriaState extends State<Galeria> {
  List<AssetEntity> todas = [], _listaActual = [];
  List<AssetPathEntity> albums = [];
  List<String> favs = [];
  bool cargando = true;
  int _tab = 0, _fotoIdx = -1;
  AssetPathEntity? _album;

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    favs = (await SharedPreferences.getInstance()).getStringList('favoritos') ?? [];
    final p = await PhotoManager.requestPermissionExtend();
    if (p.isAuth || p.hasAccess) {
      albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      if (albums.isNotEmpty) {
        todas = await albums.first.getAssetListPaged(page: 0, size: 2000);
        todas.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
      }
    }
    setState(() => cargando = false);
  }

  String _fecha(DateTime d) {
    final t = DateTime.now(), td = DateTime(t.year, t.month, t.day), d2 = DateTime(d.year, d.month, d.day);
    if (d2 == td) return 'Hoy';
    if (d2 == td.subtract(const Duration(days: 1))) return 'Ayer';
    return '${d.day} ${['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'][d.month - 1]}';
  }

  Widget _img(AssetEntity f, {BoxFit b = BoxFit.cover}) => FutureBuilder<File?>(
    future: f.file, builder: (_, s) => s.hasData ? Image.file(s.data!, fit: b) : const SizedBox());

  Future<void> _toggleFav(AssetEntity f) async {
    setState(() => favs.contains(f.id) ? favs.remove(f.id) : favs.add(f.id));
    (await SharedPreferences.getInstance()).setStringList('favoritos', favs);
  }

  Future<void> _eliminar(AssetEntity f) async {
    final c = await showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Eliminar'), actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
      ]));
    if (c != true) return;
    await PhotoManager.editor.deleteWithIds([f.id]);
    setState(() {
      favs.remove(f.id); todas.removeWhere((x) => x.id == f.id);
      if (_listaActual.isNotEmpty) _fotoIdx = _fotoIdx >= _listaActual.length ? _listaActual.length - 1 : _fotoIdx;
    });
    (await SharedPreferences.getInstance()).setStringList('favoritos', favs);
  }

  Future<void> _editar() async {
    final f = await _listaActual[_fotoIdx].file;
    if (f == null) return;
    final r = await ImageCropper().cropImage(sourcePath: f.path);
    if (r != null) { await PhotoManager.editor.saveImageWithPath(r.path); _init(); }
  }

  Widget _mini(AssetEntity f, List<AssetEntity> ctx) => GestureDetector(
    onTap: () => setState(() { _listaActual = ctx; _fotoIdx = ctx.indexOf(f); }),
    child: Stack(fit: StackFit.expand, children: [
      _img(f), if (favs.contains(f.id)) const Positioned(top: 4, right: 4, child: Icon(Icons.favorite, color: Colors.red, size: 20))
    ]),
  );

  Widget _btn(IconData i, String t, VoidCallback a, {Color? c}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [IconButton(icon: Icon(i, color: c), onPressed: a), Text(t, style: const TextStyle(fontSize: 12))]
  );

  Widget _vistaIndiv() {
    final f = _listaActual[_fotoIdx];
    var c = f.relativePath?.replaceAll(RegExp(r'/$'), '') ?? '';
    c = c.contains('/') ? c.split('/').last : (c.isEmpty ? 'Mi Galería' : c);
    return Scaffold(
      appBar: AppBar(title: Text(c), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _fotoIdx = -1))),
      body: SafeArea(child: Column(children: [
        Expanded(child: InteractiveViewer(child: _img(f, b: BoxFit.contain))),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: () => setState(() => _fotoIdx = (_fotoIdx - 1 + _listaActual.length) % _listaActual.length)),
          Text('${_fotoIdx + 1} / ${_listaActual.length}'),
          IconButton(icon: const Icon(Icons.arrow_forward_ios), onPressed: () => setState(() => _fotoIdx = (_fotoIdx + 1) % _listaActual.length)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _btn(Icons.edit, 'Editar', _editar),
          _btn(Icons.favorite, 'Me gusta', () => _toggleFav(f), c: favs.contains(f.id) ? Colors.red : null),
          _btn(Icons.delete, 'Eliminar', () => _eliminar(f)),
        ])
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cargando) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_fotoIdx != -1) return _vistaIndiv();

    final isFotos = _tab == 0;
    final Map<String, List<AssetEntity>> grupos = {};
    if (isFotos && _album == null) {
      for (var f in todas) { grupos.putIfAbsent(_fecha(f.createDateTime), () => []).add(f); }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_album?.name ?? (isFotos ? 'Fotos' : 'Álbumes')),
        leading: _album != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _album = null)) : null,
      ),
      body: Stack(children: [
        if (_album != null) FutureBuilder<List<AssetEntity>>(
          future: _album!.getAssetListPaged(page: 0, size: 2000),
          builder: (_, s) => GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
            itemCount: s.data?.length ?? 0, itemBuilder: (_, i) => _mini(s.data![i], s.data!),
          ),
        )
        else if (isFotos) ListView.builder(
          padding: const EdgeInsets.only(bottom: 80), itemCount: grupos.length,
          itemBuilder: (_, i) {
            final k = grupos.keys.elementAt(i), f = grupos[k]!;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.all(12), child: Text(k, style: const TextStyle(fontWeight: FontWeight.bold))),
              GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
                itemCount: f.length, itemBuilder: (_, j) => _mini(f[j], todas))
            ]);
          },
        )
        else GridView.builder(
          padding: const EdgeInsets.only(bottom: 80, left: 10, right: 10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: albums.length,
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => setState(() => _album = albums[i]),
            child: FutureBuilder<int>(future: albums[i].assetCountAsync, builder: (_, s) => Column(children: [
                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: FutureBuilder<List<AssetEntity>>(
                  future: albums[i].getAssetListPaged(page: 0, size: 1),
                  builder: (_, s2) => s2.hasData && s2.data!.isNotEmpty ? _img(s2.data!.first) : Container(color: Colors.grey)))),
                Text(albums[i].name, overflow: TextOverflow.ellipsis),
                Text('${s.data ?? 0}', style: const TextStyle(color: Colors.grey, fontSize: 12))
            ])),
          ),
        ),
        if (_album == null) Positioned(
          bottom: 20, left: 0, right: 0,
          child: SafeArea(child: Center(child: Container(
            padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(30)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (int i = 0; i < 2; i++) GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(color: _tab == i ? Colors.grey[700] : null, borderRadius: BorderRadius.circular(20)),
                  child: Text(i == 0 ? 'Fotos' : 'Álbumes', style: TextStyle(color: _tab == i ? Colors.white : Colors.grey)))
              )
            ]),
          ))),
        )
      ]),
    );
  }
}