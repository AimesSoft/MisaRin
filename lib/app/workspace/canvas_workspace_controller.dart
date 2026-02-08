import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../project/project_document.dart';
import '../../src/rust/api/workspace.dart' as rust;

class CanvasWorkspaceEntry {
  CanvasWorkspaceEntry({required this.document, this.isDirty = false});

  ProjectDocument document;
  bool isDirty;

  String get id => document.id;
  String get name => document.name;

  CanvasWorkspaceEntry copyWith({ProjectDocument? document, bool? isDirty}) {
    return CanvasWorkspaceEntry(
      document: document ?? this.document,
      isDirty: isDirty ?? this.isDirty,
    );
  }
}

class CanvasWorkspaceController extends ChangeNotifier {
  CanvasWorkspaceController._() {
    _restoreFromRust();
  }

  static final CanvasWorkspaceController instance =
      CanvasWorkspaceController._();

  final List<CanvasWorkspaceEntry> _entries = <CanvasWorkspaceEntry>[];
  String? _activeId;
  bool _notifyScheduled = false;

  UnmodifiableListView<CanvasWorkspaceEntry> get entries =>
      UnmodifiableListView<CanvasWorkspaceEntry>(_entries);

  String? get activeId => _activeId;

  CanvasWorkspaceEntry? entryById(String id) {
    for (final CanvasWorkspaceEntry entry in _entries) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }

  void open(ProjectDocument document, {bool activate = true}) {
    final CanvasWorkspaceEntry? existing = entryById(document.id);
    final bool isDirty = existing?.isDirty ?? false;
    if (kIsWeb) {
      final int index = _entries.indexWhere((entry) => entry.id == document.id);
      final CanvasWorkspaceEntry entry = CanvasWorkspaceEntry(
        document: document,
        isDirty: isDirty,
      );
      if (index >= 0) {
        _entries[index] = entry;
      } else {
        _entries.add(entry);
      }
      if (activate) {
        _activeId = document.id;
      }
      _scheduleNotify();
      return;
    }
    final rust.WorkspaceState state = rust.workspaceOpen(
      entry: rust.WorkspaceEntry(
        id: document.id,
        name: document.name,
        isDirty: isDirty,
      ),
      activate: activate,
    );
    _applyRustState(state, documentOverride: document);
  }

  void updateDocument(ProjectDocument document) {
    open(document, activate: _activeId == document.id);
  }

  void markDirty(String id, bool isDirty) {
    final CanvasWorkspaceEntry? current = entryById(id);
    if (current == null || current.isDirty == isDirty) {
      return;
    }
    if (kIsWeb) {
      final int index = _entries.indexWhere((entry) => entry.id == id);
      if (index < 0) {
        return;
      }
      _entries[index] = current.copyWith(isDirty: isDirty);
      _scheduleNotify();
      return;
    }
    final rust.WorkspaceState state = rust.workspaceMarkDirty(
      id: id,
      isDirty: isDirty,
    );
    _applyRustState(state);
  }

  void setActive(String id) {
    if (_activeId == id) {
      return;
    }
    if (entryById(id) == null) {
      return;
    }
    if (kIsWeb) {
      _activeId = id;
      _scheduleNotify();
      return;
    }
    final rust.WorkspaceState state = rust.workspaceSetActive(id: id);
    _applyRustState(state);
  }

  CanvasWorkspaceEntry? neighborFor(String id) {
    if (kIsWeb) {
      final int index = _entries.indexWhere((entry) => entry.id == id);
      if (index < 0) {
        return null;
      }
      int neighborIndex = index > 0 ? index - 1 : index + 1;
      if (neighborIndex < 0 || neighborIndex >= _entries.length) {
        return null;
      }
      return _entries[neighborIndex];
    }
    rust.WorkspaceEntry? neighbor;
    try {
      neighbor = rust.workspaceNeighbor(id: id);
    } catch (_) {
      neighbor = null;
    }
    if (neighbor == null) {
      return null;
    }
    final CanvasWorkspaceEntry? existing = entryById(neighbor.id);
    if (existing == null) {
      return null;
    }
    if (existing.isDirty == neighbor.isDirty && existing.name == neighbor.name) {
      return existing;
    }
    final ProjectDocument document = existing.name == neighbor.name
        ? existing.document
        : existing.document.copyWith(name: neighbor.name);
    return CanvasWorkspaceEntry(
      document: document,
      isDirty: neighbor.isDirty,
    );
  }

  void remove(String id, {String? activateAfter}) {
    if (entryById(id) == null) {
      return;
    }
    if (kIsWeb) {
      final int index = _entries.indexWhere((entry) => entry.id == id);
      if (index < 0) {
        return;
      }
      _entries.removeAt(index);
      if (_activeId == id) {
        if (activateAfter != null && entryById(activateAfter) != null) {
          _activeId = activateAfter;
        } else if (_entries.isNotEmpty) {
          final int fallbackIndex = index >= _entries.length
              ? _entries.length - 1
              : index;
          _activeId = _entries[fallbackIndex].id;
        } else {
          _activeId = null;
        }
      }
      _scheduleNotify();
      return;
    }
    final rust.WorkspaceState state = rust.workspaceRemove(
      id: id,
      activateAfter: activateAfter,
    );
    _applyRustState(state);
  }

  void reset() {
    if (kIsWeb) {
      _entries.clear();
      _activeId = null;
      _scheduleNotify();
      return;
    }
    final rust.WorkspaceState state = rust.workspaceReset();
    _applyRustState(state);
  }

  void reorder(int oldIndex, int newIndex) {
    if (_entries.length <= 1) {
      return;
    }
    if (oldIndex < 0 || oldIndex >= _entries.length) {
      return;
    }
    if (kIsWeb) {
      int targetIndex = newIndex;
      if (targetIndex < 0) {
        targetIndex = 0;
      }
      if (targetIndex >= _entries.length) {
        targetIndex = _entries.length - 1;
      }
      if (targetIndex == oldIndex) {
        return;
      }
      final CanvasWorkspaceEntry entry = _entries.removeAt(oldIndex);
      _entries.insert(targetIndex, entry);
      _scheduleNotify();
      return;
    }
    final rust.WorkspaceState state = rust.workspaceReorder(
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
    _applyRustState(state);
  }

  void _restoreFromRust() {
    if (kIsWeb) {
      _entries.clear();
      _activeId = null;
      return;
    }
    try {
      final rust.WorkspaceState state = rust.workspaceState();
      _applyRustState(state);
    } catch (_) {
      _entries.clear();
      _activeId = null;
    }
  }

  void _applyRustState(
    rust.WorkspaceState state, {
    ProjectDocument? documentOverride,
  }) {
    final Map<String, CanvasWorkspaceEntry> cache =
        <String, CanvasWorkspaceEntry>{
      for (final CanvasWorkspaceEntry entry in _entries) entry.id: entry,
    };

    if (documentOverride != null) {
      final bool isDirty = cache[documentOverride.id]?.isDirty ?? false;
      cache[documentOverride.id] = CanvasWorkspaceEntry(
        document: documentOverride,
        isDirty: isDirty,
      );
    }

    final List<CanvasWorkspaceEntry> nextEntries = <CanvasWorkspaceEntry>[];
    for (final rust.WorkspaceEntry entry in state.entries) {
      final CanvasWorkspaceEntry? current = cache[entry.id];
      if (current == null) {
        continue;
      }
      final ProjectDocument document = current.name == entry.name
          ? current.document
          : current.document.copyWith(name: entry.name);
      nextEntries.add(
        CanvasWorkspaceEntry(
          document: document,
          isDirty: entry.isDirty,
        ),
      );
    }

    bool sameEntries = nextEntries.length == _entries.length;
    if (sameEntries) {
      for (int i = 0; i < nextEntries.length; i++) {
        final CanvasWorkspaceEntry next = nextEntries[i];
        final CanvasWorkspaceEntry current = _entries[i];
        if (next.id != current.id ||
            next.name != current.name ||
            next.isDirty != current.isDirty ||
            next.document != current.document) {
          sameEntries = false;
          break;
        }
      }
    }

    if (sameEntries && _activeId == state.activeId) {
      return;
    }

    _entries
      ..clear()
      ..addAll(nextEntries);
    _activeId = state.activeId;
    _scheduleNotify();
  }

  void _scheduleNotify() {
    final WidgetsBinding binding = WidgetsBinding.instance;
    if (_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    binding.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}
