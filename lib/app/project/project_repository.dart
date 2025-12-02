import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../canvas/canvas_layer.dart';
import '../../canvas/canvas_settings.dart';
import '../psd/psd_importer.dart';
import '../psd/psd_exporter.dart';
import 'project_binary_codec.dart';
import 'project_document.dart';
import 'recent_projects_index.dart';

class ProjectRepository {
  ProjectRepository._();

  static final ProjectRepository instance = ProjectRepository._();

  Directory? _projectDirectory;
  RecentProjectsIndex? _recentIndex;
  final _WebProjectStore? _webStore = kIsWeb ? _WebProjectStore() : null;

  static const String _folderName = 'MisaRin';

  Future<Directory> _ensureProjectDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('Project directory is not available on web.');
    }
    if (_projectDirectory != null) {
      return _projectDirectory!;
    }
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(p.join(base.path, _folderName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _projectDirectory = directory;
    _recentIndex = RecentProjectsIndex(directory);
    return directory;
  }

  Future<ProjectDocument> saveDocument(ProjectDocument document) async {
    if (kIsWeb) {
      return _saveDocumentOnWeb(document);
    }
    final Directory directory = await _ensureProjectDirectory();
    final String fileName = document.path == null
        ? _buildFileName(document)
        : p.basename(document.path!);
    final String absolutePath = p.join(directory.path, fileName);
    final ProjectDocument resolved = document.copyWith(
      path: absolutePath,
      updatedAt: DateTime.now(),
    );
    final Uint8List binary = ProjectBinaryCodec.encode(resolved);
    final File file = File(absolutePath);
    await file.writeAsBytes(binary, flush: true);
    await _recentIndex?.touch(absolutePath);
    return resolved;
  }

  Future<ProjectDocument> saveDocumentAs(
    ProjectDocument document,
    String absolutePath,
  ) async {
    if (kIsWeb) {
      throw UnsupportedError('Web 当前不支持“另存为”本地项目文件。');
    }
    await _ensureProjectDirectory();
    final File file = File(absolutePath);
    await file.parent.create(recursive: true);
    final ProjectDocument resolved = document.copyWith(
      path: absolutePath,
      updatedAt: DateTime.now(),
    );
    final Uint8List binary = ProjectBinaryCodec.encode(resolved);
    await file.writeAsBytes(binary, flush: true);
    await _recentIndex?.touch(absolutePath);
    return resolved;
  }

  Future<ProjectDocument> loadDocument(String path) async {
    if (kIsWeb) {
      return _loadDocumentOnWeb(path);
    }
    await _ensureProjectDirectory();
    final File file = File(path);
    final Uint8List bytes = await file.readAsBytes();
    final ProjectDocument document = ProjectBinaryCodec.decode(
      bytes,
      path: path,
    );
    await _recentIndex?.touch(path);
    return document;
  }

  Future<ProjectDocument> loadDocumentFromBytes(Uint8List bytes) async {
    if (!kIsWeb) {
      throw UnsupportedError('仅 Web 平台支持从字节流加载项目文件。');
    }
    final ProjectDocument decoded = ProjectBinaryCodec.decode(bytes);
    final String fileName = _buildFileName(decoded);
    final String virtualPath = _buildVirtualPath(fileName);
    final ProjectDocument resolved = decoded.copyWith(path: virtualPath);
    await _webStore!.write(virtualPath, resolved, lastOpened: DateTime.now());
    return resolved;
  }

  Future<List<ProjectSummary>> listRecentProjects() async {
    if (kIsWeb) {
      return _webStore!.listRecentProjects();
    }
    final List<ProjectSummary> summaries = <ProjectSummary>[];
    await for (final ProjectSummary summary in streamRecentProjects()) {
      summaries.add(summary);
    }
    return summaries;
  }

  Stream<ProjectSummary> streamRecentProjects() async* {
    if (kIsWeb) {
      yield* _webStore!.streamRecentProjects();
      return;
    }
    await _ensureProjectDirectory();
    final List<_IndexedEntry> entries = await _loadIndexEntries();
    entries.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    for (final _IndexedEntry entry in entries) {
      final File file = File(entry.path);
      if (!await file.exists()) {
        await _recentIndex?.remove(entry.path);
        continue;
      }
      try {
        final Uint8List bytes = await file.readAsBytes();
        final ProjectSummary summary = ProjectBinaryCodec.decodeSummary(
          bytes,
          path: entry.path,
          lastOpened: entry.lastOpened,
        );
        yield summary;
      } catch (_) {
        // ignore malformed entries
      }
    }
  }

  Future<List<StoredProjectInfo>> listStoredProjects() async {
    if (kIsWeb) {
      return _webStore!.listStoredProjects();
    }
    final List<StoredProjectInfo> items = <StoredProjectInfo>[];
    await for (final StoredProjectInfo info in streamStoredProjects()) {
      items.add(info);
    }
    items.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return items;
  }

  Stream<StoredProjectInfo> streamStoredProjects() async* {
    if (kIsWeb) {
      yield* _webStore!.streamStoredProjects();
      return;
    }
    final Directory directory = await _ensureProjectDirectory();
    await for (final FileSystemEntity entity in directory.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      if (p.extension(entity.path).toLowerCase() != '.rin') {
        continue;
      }
      final File file = entity;
      final DateTime modified = await file.lastModified();
      final int size = await file.length();
      String displayName = p.basename(file.path);
      ProjectSummary? summary;
      try {
        final Uint8List bytes = await file.readAsBytes();
        summary = ProjectBinaryCodec.decodeSummary(
          bytes,
          path: file.path,
          lastOpened: modified,
        );
        displayName = summary.name;
      } catch (_) {
        // ignore malformed projects, keep fallback name
      }
      yield StoredProjectInfo(
        path: file.path,
        fileName: p.basename(file.path),
        displayName: displayName,
        fileSize: size,
        lastModified: modified,
        summary: summary,
      );
    }
  }

  Future<void> deleteProject(String path) async {
    if (kIsWeb) {
      await _webStore!.delete(path);
      return;
    }
    await _ensureProjectDirectory();
    final File file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    await _recentIndex?.remove(path);
  }

  Future<List<_IndexedEntry>> _loadIndexEntries() async {
    if (kIsWeb) {
      return _webStore!.loadIndexEntries();
    }
    final List<_IndexedEntry> entries = <_IndexedEntry>[];
    final List<RecentProjectRecord> raw =
        await (_recentIndex?.entries() ??
            Future<List<RecentProjectRecord>>.value(
              const <RecentProjectRecord>[],
            ));
    for (final RecentProjectRecord entry in raw) {
      entries.add(_IndexedEntry(entry.path, entry.lastOpened));
    }
    return entries;
  }

  String _buildFileName(ProjectDocument document) {
    final String sanitizedName = document.name
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    final String namePart = sanitizedName.isEmpty ? 'project' : sanitizedName;
    return '${document.id}_$namePart.rin';
  }

  String _buildVirtualPath(String fileName) {
    return 'web_projects/$fileName';
  }

  Future<ProjectDocument> _saveDocumentOnWeb(ProjectDocument document) async {
    final String fileName = document.path == null
        ? _buildFileName(document)
        : p.basename(document.path!);
    final String virtualPath = document.path ?? _buildVirtualPath(fileName);
    final ProjectDocument resolved = document.copyWith(
      path: virtualPath,
      updatedAt: DateTime.now(),
    );
    await _webStore!.write(virtualPath, resolved);
    return resolved;
  }

  Future<ProjectDocument> _loadDocumentOnWeb(String path) async {
    return _webStore!.read(path);
  }

  Future<ProjectDocument> createDocumentFromSettings(
    CanvasSettings settings, {
    String name = '未命名项目',
  }) async {
    if (!kIsWeb) {
      await _ensureProjectDirectory();
    }
    return ProjectDocument.newProject(settings: settings, name: name);
  }

  Future<ProjectDocument> importPsd(String path) async {
    if (kIsWeb) {
      throw UnsupportedError('Web 暂不支持导入 PSD 文件。');
    }
    await _ensureProjectDirectory();
    const PsdImporter importer = PsdImporter();
    return importer.importFile(path);
  }

  Future<ProjectDocument> importPsdFromBytes(
    Uint8List bytes, {
    String? fileName,
  }) async {
    final String? displayName = fileName == null || fileName.trim().isEmpty
        ? null
        : p.basenameWithoutExtension(fileName);
    const PsdImporter importer = PsdImporter();
    return importer.importBytes(bytes, displayName: displayName);
  }

  Future<void> exportDocumentAsPsd({
    required ProjectDocument document,
    required String path,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Web 暂不支持导出 PSD 文件。');
    }
    const PsdExporter exporter = PsdExporter();
    await exporter.export(document, path);
  }

  Future<ProjectDocument> createDocumentFromImage(
    String path, {
    String? name,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Web 暂不支持从本地路径读取图像。');
    }
    await _ensureProjectDirectory();
    final File file = File(path);
    if (!await file.exists()) {
      throw Exception('文件不存在：$path');
    }
    final Uint8List bytes = await file.readAsBytes();
    final _DecodedImage decoded = await _decodeImageBytes(bytes);
    final String resolvedName = _resolveImageName(
      name ?? p.basenameWithoutExtension(path),
      fallback: '导入图像',
    );
    return _buildDocumentFromDecodedImage(decoded, resolvedName);
  }

  Future<ProjectDocument> createDocumentFromImageBytes(
    Uint8List bytes, {
    String? name,
  }) async {
    if (!kIsWeb) {
      await _ensureProjectDirectory();
    }
    final _DecodedImage decoded = await _decodeImageBytes(bytes);
    final String resolvedName = _resolveImageName(name, fallback: '剪贴板图像');
    return _buildDocumentFromDecodedImage(decoded, resolvedName);
  }

  String _resolveImageName(String? raw, {required String fallback}) {
    final String? trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return fallback;
    }
    return trimmed;
  }

  Future<_DecodedImage> _decodeImageBytes(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    final ByteData? pixelData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    codec.dispose();
    if (pixelData == null) {
      image.dispose();
      throw Exception('无法读取图像像素数据');
    }
    final Uint8List rgba = Uint8List.fromList(pixelData.buffer.asUint8List());
    final _DecodedImage result = _DecodedImage(
      width: image.width,
      height: image.height,
      rgba: rgba,
    );
    image.dispose();
    return result;
  }

  ProjectDocument _buildDocumentFromDecodedImage(
    _DecodedImage decoded,
    String name,
  ) {
    final CanvasSettings settings = CanvasSettings(
      width: decoded.width.toDouble(),
      height: decoded.height.toDouble(),
      backgroundColor: const ui.Color(0xFFFFFFFF),
      creationLogic: CanvasCreationLogic.multiThread,
    );

    final ProjectDocument base = ProjectDocument.newProject(
      settings: settings,
      name: name,
    );

    final List<CanvasLayerData> layers = <CanvasLayerData>[
      base.layers.first,
      base.layers.length > 1
          ? base.layers[1].copyWith(
              name: name,
              bitmap: decoded.rgba,
              bitmapWidth: decoded.width,
              bitmapHeight: decoded.height,
              clearFill: true,
            )
          : CanvasLayerData(
              id: generateLayerId(),
              name: name,
              bitmap: decoded.rgba,
              bitmapWidth: decoded.width,
              bitmapHeight: decoded.height,
            ),
    ];

    return base.copyWith(layers: layers);
  }
}

class _DecodedImage {
  const _DecodedImage({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;
}

class _IndexedEntry {
  const _IndexedEntry(this.path, this.lastOpened);

  final String path;
  final DateTime lastOpened;
}

class StoredProjectInfo {
  const StoredProjectInfo({
    required this.path,
    required this.fileName,
    required this.displayName,
    required this.fileSize,
    required this.lastModified,
    this.summary,
  });

  final String path;
  final String fileName;
  final String displayName;
  final int fileSize;
  final DateTime lastModified;
  final ProjectSummary? summary;
}

class _WebProjectStore {
  final Map<String, _WebStoredProject> _projects =
      <String, _WebStoredProject>{};
  final Map<String, DateTime> _recentEntries = <String, DateTime>{};

  Future<void> write(
    String path,
    ProjectDocument document, {
    DateTime? lastOpened,
  }) async {
    final DateTime updatedAt = document.updatedAt;
    final Uint8List bytes = ProjectBinaryCodec.encode(document);
    _projects[path] = _WebStoredProject(bytes: bytes, lastModified: updatedAt);
    _touch(path, lastOpened ?? updatedAt);
  }

  Future<ProjectDocument> read(String path) async {
    final _WebStoredProject? stored = _projects[path];
    if (stored == null) {
      throw Exception('未在当前浏览器会话中找到项目：$path');
    }
    final ProjectDocument document = ProjectBinaryCodec.decode(
      stored.bytes,
      path: path,
    );
    _touch(path, DateTime.now());
    return document;
  }

  Future<void> delete(String path) async {
    _projects.remove(path);
    _recentEntries.remove(path);
  }

  Future<List<ProjectSummary>> listRecentProjects() async {
    final List<ProjectSummary> summaries = <ProjectSummary>[];
    await for (final ProjectSummary summary in streamRecentProjects()) {
      summaries.add(summary);
    }
    return summaries;
  }

  Stream<ProjectSummary> streamRecentProjects() async* {
    final List<_IndexedEntry> entries = await loadIndexEntries();
    for (final _IndexedEntry entry in entries) {
      final _WebStoredProject? stored = _projects[entry.path];
      if (stored == null) {
        continue;
      }
      try {
        final ProjectSummary summary = ProjectBinaryCodec.decodeSummary(
          stored.bytes,
          path: entry.path,
          lastOpened: entry.lastOpened,
        );
        yield summary;
      } catch (_) {
        // ignore malformed data
      }
    }
  }

  Future<List<StoredProjectInfo>> listStoredProjects() async {
    final List<StoredProjectInfo> items = <StoredProjectInfo>[];
    await for (final StoredProjectInfo info in streamStoredProjects()) {
      items.add(info);
    }
    return items;
  }

  Stream<StoredProjectInfo> streamStoredProjects() async* {
    final List<MapEntry<String, _WebStoredProject>> entries = _projects.entries
        .toList(growable: false);
    entries.sort(
      (a, b) => b.value.lastModified.compareTo(a.value.lastModified),
    );
    for (final MapEntry<String, _WebStoredProject> entry in entries) {
      final _WebStoredProject stored = entry.value;
      ProjectSummary? summary;
      String displayName = p.basename(entry.key);
      try {
        summary = ProjectBinaryCodec.decodeSummary(
          stored.bytes,
          path: entry.key,
          lastOpened: stored.lastModified,
        );
        displayName = summary.name;
      } catch (_) {
        // ignore broken payloads, keep fallback name
      }
      yield StoredProjectInfo(
        path: entry.key,
        fileName: p.basename(entry.key),
        displayName: displayName,
        fileSize: stored.bytes.length,
        lastModified: stored.lastModified,
        summary: summary,
      );
    }
  }

  Future<List<_IndexedEntry>> loadIndexEntries() async {
    final List<_IndexedEntry> entries = _recentEntries.entries
        .map((entry) => _IndexedEntry(entry.key, entry.value))
        .toList(growable: false);
    entries.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return entries;
  }

  void _touch(String path, DateTime timestamp) {
    _recentEntries[path] = timestamp;
  }
}

class _WebStoredProject {
  const _WebStoredProject({required this.bytes, required this.lastModified});

  final Uint8List bytes;
  final DateTime lastModified;
}
