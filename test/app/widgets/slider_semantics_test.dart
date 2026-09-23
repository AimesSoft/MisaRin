import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:misa_rin/app/widgets/app_slider.dart';
import 'package:misa_rin/app/widgets/app_color_picker.dart';

// Check the serialized tree, not only Flutter's logical semantics tree: an
// OverlayPortal can leave the latter valid while sending an orphan to AXTree.
class _SemanticsBinding extends AutomatedTestWidgetsFlutterBinding {
  final Map<int, List<int>> nodes = {};
  final List<int> orphans = [];

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() => _Builder(this);
}

class _Builder implements ui.SemanticsUpdateBuilder {
  _Builder(this.binding);
  final _SemanticsBinding binding;
  final Map<int, List<int>> updates = {};

  // The many unrelated updateNode fields are intentionally ignored. This also
  // keeps the recorder compatible with Flutter's evolving semantics flags.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final args = invocation.namedArguments;
      updates[args[#id] as int] = List<int>.of(
        args[#childrenInTraversalOrder] as Iterable<int>,
      );
      return null;
    }
    if (invocation.memberName == #updateCustomAction) return null;
    return super.noSuchMethod(invocation);
  }

  @override
  ui.SemanticsUpdate build() {
    binding.nodes.addAll(updates);
    final reachable = <int>{};
    void visit(int id) {
      if (!reachable.add(id)) return;
      for (final child in binding.nodes[id] ?? <int>[]) {
        visit(child);
      }
    }

    visit(0);
    binding.orphans.addAll(updates.keys.where((id) => !reachable.contains(id)));
    binding.nodes.removeWhere((id, _) => !reachable.contains(id));
    return ui.SemanticsUpdateBuilder().build();
  }
}

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    body: fluent.FluentTheme(data: fluent.FluentThemeData(), child: child),
  ),
);

void main() {
  final binding = _SemanticsBinding();
  setUp(() {
    binding.nodes.clear();
    binding.orphans.clear();
  });

  testWidgets(
    'slider routes and dialogs never serialize orphan AX nodes',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          localizationsDelegates: const [fluent.FluentLocalizations.delegate],
          home: const Scaffold(body: Text('Home')),
        ),
      );
      for (var iteration = 0; iteration < 3; iteration++) {
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: fluent.FluentTheme(
                data: fluent.FluentThemeData(),
                child: Column(
                  children: List.generate(
                    4,
                    (index) =>
                        AppSlider(value: 40, label: '40', onChanged: (_) {}),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Text fields are where the damaged native tree eventually crashed.
        showDialog<void>(
          context: navigator.currentContext!,
          builder: (_) => const AlertDialog(content: TextField()),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Regression $iteration');
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
      }
      expect(binding.orphans, isEmpty);
      semantics.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'keyboard and accessibility preserve values and callbacks',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final focus = FocusNode();
      addTearDown(focus.dispose);
      final events = <String>[];
      double value = 20;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              return AppSlider(
                value: value,
                min: 10,
                max: 30,
                divisions: 4,
                focusNode: focus,
                onChangeStart: (v) => events.add('start:$v'),
                onChanged: (v) {
                  events.add('change:$v');
                  setState(() => value = v);
                },
                onChangeEnd: (v) => events.add('end:$v'),
              );
            },
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(value, 25);
      expect(events, ['start:20.0', 'change:25.0', 'end:25.0']);
      final node = tester.getSemantics(find.byType(AppSlider));
      expect(node.getSemanticsData().value, '75%');
      node.owner!.performAction(node.id, ui.SemanticsAction.decrease);
      await tester.pump();
      expect(value, 20);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(value, 30);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(value, 30);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(value, 10);
      expect(binding.orphans, isEmpty);
      semantics.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'pointer drag commits once and respects discrete values',
    (tester) async {
      double value = 50;
      int starts = 0;
      int ends = 0;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              return Center(
                child: SizedBox(
                  width: 300,
                  child: AppSlider(
                    value: value,
                    divisions: 10,
                    onChanged: (v) => setState(() => value = v),
                    onChangeStart: (_) => starts++,
                    onChangeEnd: (_) => ends++,
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.drag(find.byType(AppSlider), const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(value, greaterThan(50));
      expect(value % 10, 0);
      expect(starts, 1);
      expect(ends, 1);
      final rect = tester.getRect(find.byType(AppSlider));
      await tester.tapAt(Offset(rect.left + 10, rect.center.dy));
      await tester.pumpAndSettle();
      expect(value, 0);
      expect(starts, 2);
      expect(ends, 2);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'disabled and zero-width ranges have no adjustment actions',
    (tester) async {
      final semantics = tester.ensureSemantics();

      for (final collapsed in [false, true]) {
        await tester.pumpWidget(
          _app(
            AppSlider(
              value: 10,
              min: 10,
              max: collapsed ? 10 : 30,
              onChanged: collapsed
                  ? (_) => fail('disabled slider changed')
                  : null,
            ),
          ),
        );
        final data = tester
            .getSemantics(find.byType(AppSlider))
            .getSemanticsData();
        expect(data.hasAction(ui.SemanticsAction.increase), isFalse);
        expect(data.hasAction(ui.SemanticsAction.decrease), isFalse);
        expect(binding.orphans, isEmpty);
      }
      semantics.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'vertical slider and RTL keyboard keep their direction',
    (tester) async {
      double value = 50;
      await tester.pumpWidget(
        _app(
          Directionality(
            textDirection: TextDirection.rtl,
            child: Center(
              child: SizedBox(
                height: 300,
                child: StatefulBuilder(
                  builder: (context, setState) => AppSlider(
                    value: value,
                    vertical: true,
                    autofocus: true,
                    onChanged: (v) => setState(() => value = v),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(value, 40);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(value, 50);
      await tester.drag(find.byType(AppSlider), const Offset(0, -70));
      await tester.pumpAndSettle();
      expect(value, greaterThan(50));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  testWidgets(
    'color picker dialogs keep the AX tree connected',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final navigator = GlobalKey<NavigatorState>();
      Color selected = const Color(0xFF6636C5);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          localizationsDelegates: const [fluent.FluentLocalizations.delegate],
          home: const Scaffold(body: Text('Canvas')),
        ),
      );
      for (final shape in fluent.ColorSpectrumShape.values) {
        showDialog<void>(
          context: navigator.currentContext!,
          builder: (_) => AlertDialog(
            content: fluent.FluentTheme(
              data: fluent.FluentThemeData(),
              child: AppColorPicker(
                color: selected,
                colorSpectrumShape: shape,
                onChanged: (color) => selected = color,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = selected;
        final rect = tester.getRect(find.byType(AppSlider));
        final fraction = HSVColor.fromColor(selected).value;
        await tester.dragFrom(
          Offset(rect.left + 10 + fraction * (rect.width - 20), rect.center.dy),
          const Offset(-50, 0),
        );
        await tester.pumpAndSettle();
        expect(selected, isNot(before));
        await tester.enterText(find.byType(EditableText).first, '#39C5BB');
        await tester.pumpAndSettle();
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
      }
      expect(binding.orphans, isEmpty);
      semantics.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
