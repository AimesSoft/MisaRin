import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:misa_rin/utils/io_shim.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../backend/rgba_utils.dart';
import '../../canvas/canvas_layer.dart';
import '../../canvas/canvas_settings.dart';
import '../psd/psd_importer.dart';
import '../psd/psd_exporter.dart';
import '../sai2/sai2_importer.dart';
import '../sai2/sai2_exporter.dart';
import '../utils/svg_rasterizer.dart';
import 'project_binary_codec.dart';
import 'project_document.dart';
import 'recent_projects_index.dart';

class ProjectRepository {
  ProjectRepository._();

  static final ProjectRepository instance = ProjectRepository._();

  Directory? _projectDirectory;
  Directory? _autoSaveDirectory;
  RecentProjectsIndex? _recentIndex;

  static const String _folderName = 'MisaRin';
  static const String _autoSaveFolderName = 'autosaves';

  Future<Directory> _ensureProjectDirectory() async {
    if (_projectDirectory != null) {
      return _projectDirectory!;
    }
    final base = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(p.join(base.path, _folderName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _projectDirectory = directory;
    _recentIndex = RecentProjectsIndex(directory);
    return directory;
  }

  Future<Directory> _ensureAutoSaveDirectory() async {
    if (_autoSaveDirectory != null) {
      return _autoSaveDirectory!;
    }
    final Directory root = await _ensureProjectDirectory();
    final Directory directory = Directory(
      p.join(root.path, _autoSaveFolderName),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _autoSaveDirectory = directory;
    await _migrateLegacyAutoSaves(root, directory);
    return directory;
  }

  Future<void> _migrateLegacyAutoSaves(Directory root, Directory target) async {
    try {
      await for (final FileSystemEntity entity in root.list(
        recursive: false,
        followLinks: false,
      )) {
        if (entity is! File) {
          continue;
        }
        if (p.extension(entity.path).toLowerCase() != '.rin') {
          continue;
        }
        final String fileName = p.basename(entity.path);
        final String destination = p.join(target.path, fileName);
        if (entity.path == destination) {
          continue;
        }
        try {
          await entity.rename(destination);
        } catch (_) {
          try {
            await entity.copy(destination);
            await entity.delete();
          } catch (_) {
            continue;
          }
        }
        await _recentIndex?.touch(destination);
      }
    } catch (_) {
      // Ignore migration failures.
    }
  }

  Future<ProjectDocument> saveDocument(ProjectDocument document) async {
    final Directory directory = await _ensureAutoSaveDirectory();
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

  Future<List<ProjectSummary>> listRecentProjects() async {
    final List<ProjectSummary> summaries = <ProjectSummary>[];
    await for (final ProjectSummary summary in streamRecentProjects()) {
      summaries.add(summary);
    }
    return summaries;
  }

  Stream<ProjectSummary> streamRecentProjects() async* {
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
    final List<StoredProjectInfo> items = <StoredProjectInfo>[];
    await for (final StoredProjectInfo info in streamStoredProjects()) {
      items.add(info);
    }
    items.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return items;
  }

  Stream<StoredProjectInfo> streamStoredProjects() async* {
    final Directory directory = await _ensureAutoSaveDirectory();
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

  Future<String> autoSaveDirectoryPath() async {
    final Directory directory = await _ensureAutoSaveDirectory();
    return directory.path;
  }

  Future<int> autoSaveDirectorySizeBytes() async {
    final Directory directory = await _ensureAutoSaveDirectory();
    int total = 0;
    try {
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
        total += await entity.length();
      }
    } catch (_) {
      return total;
    }
    return total;
  }

  Future<int> deleteAutoSavedProjects() async {
    final Directory directory = await _ensureAutoSaveDirectory();
    int deleted = 0;
    try {
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
        await deleteProject(entity.path);
        deleted += 1;
      }
    } catch (_) {
      return deleted;
    }
    return deleted;
  }

  Future<void> deleteProject(String path) async {
    await _ensureProjectDirectory();
    final File file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    await _recentIndex?.remove(path);
  }

  Future<List<_IndexedEntry>> _loadIndexEntries() async {
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

  Future<ProjectDocument> createDocumentFromSettings(
    CanvasSettings settings, {
    String name = '未命名项目',
  }) async {
    await _ensureProjectDirectory();
    return ProjectDocument.newProject(settings: settings, name: name);
  }

  Future<ProjectDocument> importPsd(String path) async {
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

  Future<ProjectDocument> importSai2(String path) async {
    await _ensureProjectDirectory();
    const Sai2Importer importer = Sai2Importer();
    return importer.importFile(path);
  }

  Future<ProjectDocument> importSai2FromBytes(
    Uint8List bytes, {
    String? fileName,
  }) async {
    final String? displayName = fileName == null || fileName.trim().isEmpty
        ? null
        : p.basenameWithoutExtension(fileName);
    const Sai2Importer importer = Sai2Importer();
    return importer.importBytes(bytes, displayName: displayName);
  }

  Future<void> exportDocumentAsPsd({
    required ProjectDocument document,
    required String path,
  }) async {
    const PsdExporter exporter = PsdExporter();
    await exporter.export(document, path);
  }

  Future<void> exportDocumentAsSai2({
    required ProjectDocument document,
    required String path,
  }) async {
    const Sai2Exporter exporter = Sai2Exporter();
    await exporter.export(document, path);
  }

  Future<ProjectDocument> createDocumentFromImage(
    String path, {
    String? name,
    int? svgRasterSizePx,
    bool hideBackgroundLayer = false,
  }) async {
    await _ensureProjectDirectory();
    final File file = File(path);
    if (!await file.exists()) {
      throw Exception('文件不存在：$path');
    }
    final Uint8List bytes = await file.readAsBytes();
    final _DecodedImage decoded = await _decodeImageBytes(
      bytes,
      svgRasterSizePx: svgRasterSizePx,
    );
    final String resolvedName = _resolveImageName(
      name ?? p.basenameWithoutExtension(path),
      fallback: '导入图像',
    );
    return _buildDocumentFromDecodedImage(
      decoded,
      resolvedName,
      hideBackgroundLayer: hideBackgroundLayer,
    );
  }

  Future<ProjectDocument> createDocumentFromImageBytes(
    Uint8List bytes, {
    String? name,
    int? svgRasterSizePx,
    bool hideBackgroundLayer = false,
  }) async {
    await _ensureProjectDirectory();
    final _DecodedImage decoded = await _decodeImageBytes(
      bytes,
      svgRasterSizePx: svgRasterSizePx,
    );
    final String resolvedName = _resolveImageName(name, fallback: '剪贴板图像');
    return _buildDocumentFromDecodedImage(
      decoded,
      resolvedName,
      hideBackgroundLayer: hideBackgroundLayer,
    );
  }

  String _resolveImageName(String? raw, {required String fallback}) {
    final String? trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return fallback;
    }
    return trimmed;
  }

  Future<_DecodedImage> _decodeImageBytes(
    Uint8List bytes, {
    int? svgRasterSizePx,
  }) async {
    final DecodedUiImageFrame decodedFrame = await decodeBitmapOrSvgFrame(
      bytes,
      svgRasterSizePx: svgRasterSizePx,
    );
    final ui.Image image = decodedFrame.image;
    final ByteData? pixelData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (pixelData == null) {
      image.dispose();
      throw Exception('无法读取图像像素数据');
    }
    final Uint8List rgba = Uint8List.fromList(
      pixelData.buffer.asUint8List(
        pixelData.offsetInBytes,
        pixelData.lengthInBytes,
      ),
    );
    unpremultiplyRgbaInPlace(rgba);
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
    String name, {
    bool hideBackgroundLayer = false,
  }) {
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
      base.layers.first.copyWith(visible: !hideBackgroundLayer),
      base.layers.length > 1
          ? base.layers[1].copyWith(
              name: name,
              visible: true,
              bitmap: decoded.rgba,
              bitmapWidth: decoded.width,
              bitmapHeight: decoded.height,
              clearFill: true,
            )
          : CanvasLayerData(
              id: generateLayerId(),
              name: name,
              visible: true,
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
