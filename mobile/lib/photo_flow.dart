import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Side length of the square photo and mask sent to the model (its working size).
const photoSide = 1024;

/// Where a photo comes from; injectable so tests do not need the platform plugin.
typedef PhotoPicker = Future<Uint8List?> Function(ImageSource source);

Future<Uint8List?> pickWithImagePicker(ImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 92,
    requestFullMetadata: false,
  );
  return file?.readAsBytes();
}

/// Centre-crops [bytes] to a square and re-encodes it as a [side]×[side] PNG.
///
/// Drawing the decoded pixels into a fresh image drops EXIF, GPS and every other
/// metadata block, so location never leaves the phone.
Future<Uint8List> squarePng(Uint8List bytes, {int side = photoSide}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final source = (await codec.getNextFrame()).image;
  final s = math.min(source.width, source.height).toDouble();
  final crop = Rect.fromLTWH(
    (source.width - s) / 2,
    (source.height - s) / 2,
    s,
    s,
  );
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    source,
    crop,
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final image = await recorder.endRecording().toImage(side, side);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  source.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// One brush stroke in 0–1 photo coordinates; [width] is a fraction of the side.
class Stroke {
  Stroke(this.width);
  final double width;
  final List<Offset> points = [];
}

void _paintStrokes(Canvas canvas, double side, List<Stroke> strokes, Color c) {
  for (final stroke in strokes) {
    final paint = Paint()
      ..color = c
      ..strokeWidth = stroke.width * side
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final pts = stroke.points.map((p) => p * side).toList();
    if (pts.length == 1) {
      canvas.drawCircle(
        pts.first,
        stroke.width * side / 2,
        paint..style = PaintingStyle.fill,
      );
    } else {
      canvas.drawPath(Path()..addPolygon(pts, false), paint);
    }
  }
}

/// White-on-black mask PNG of [strokes]: white is where the model may change pixels.
Future<Uint8List> maskPng(List<Stroke> strokes, {int side = photoSide}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = side.toDouble();
  canvas.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = Colors.black);
  _paintStrokes(canvas, s, strokes, Colors.white);
  final image = await recorder.endRecording().toImage(side, side);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes, this.revision);
  final List<Stroke> strokes;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) => _paintStrokes(
    canvas,
    size.width,
    strokes,
    AppColors.accent.withValues(alpha: 0.55),
  );

  @override
  bool shouldRepaint(_StrokePainter old) => old.revision != revision;
}

enum _Stage { choose, paint, working, result }

/// Take or choose a meal photo, paint the rice, and get the model's edit back.
class PhotoEditPage extends StatefulWidget {
  const PhotoEditPage({
    super.key,
    required this.api,
    required this.available,
    this.picker = pickWithImagePicker,
  });

  final MealApi api;

  /// Whether the server advertised `photo_upload` (a real model is connected).
  final bool available;
  final PhotoPicker picker;

  @override
  State<PhotoEditPage> createState() => _PhotoEditPageState();
}

class _PhotoEditPageState extends State<PhotoEditPage> {
  _Stage _stage = _Stage.choose;
  PhotoChange _change = PhotoChange.all.first;
  Uint8List? _photo;
  final List<Stroke> _strokes = [];
  int _revision = 0;
  bool _bigBrush = true;
  bool _preparing = false;
  String? _error;
  PhotoEditResult? _result;

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final bytes = await widget.picker(source);
      if (bytes == null) {
        if (mounted) setState(() => _preparing = false);
        return;
      }
      final square = await squarePng(bytes);
      if (!mounted) return;
      setState(() {
        _photo = square;
        _strokes.clear();
        _revision++;
        _preparing = false;
        _stage = _Stage.paint;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _error = source == ImageSource.camera
            ? 'Could not use the camera. Allow camera access, or choose a photo instead.'
            : 'Could not open that photo. Please choose another one.';
      });
    }
  }

  Future<void> _submit() async {
    final photo = _photo;
    if (photo == null || _strokes.isEmpty) return;
    setState(() {
      _stage = _Stage.working;
      _error = null;
    });
    try {
      final mask = await maskPng(_strokes);
      final result = await widget.api.editPhoto(
        changeId: _change.id,
        imagePng: photo,
        maskPng: mask,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _stage = _Stage.result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.paint;
        _error = error is ApiException
            ? error.message
            : 'Something went wrong. Please try again.';
      });
    }
  }

  void _startOver() => setState(() {
    _stage = _Stage.choose;
    _photo = null;
    _result = null;
    _error = null;
    _strokes.clear();
    _revision++;
  });

  void _addPoint(Offset local, double side, {bool start = false}) {
    final p = Offset(
      (local.dx / side).clamp(0.0, 1.0),
      (local.dy / side).clamp(0.0, 1.0),
    );
    setState(() {
      if (start || _strokes.isEmpty) {
        _strokes.add(Stroke(_bigBrush ? 0.09 : 0.04));
      }
      _strokes.last.points.add(p);
      _revision++;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _stage != _Stage.working,
    child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Your own photo'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxOuterWidth,
            ),
            child: ListView(
              padding: AppLayout.pagePadding,
              children: switch (_stage) {
                _Stage.choose => _chooseView(),
                _Stage.paint => _paintView(),
                _Stage.working => _workingView(),
                _Stage.result => _resultView(),
              },
            ),
          ),
        ),
      ),
    ),
  );

  List<Widget> _chooseView() => [
    const StepHeading('Change your own meal photo'),
    const SizedBox(height: 8),
    Text(
      'Take a photo of a rice meal, mark the rice, and see one change made '
      'to it.',
      style: Theme.of(context).textTheme.bodyLarge,
    ),
    const SizedBox(height: 16),
    if (!widget.available) ...[
      const NoticeCard(
        'Photo editing is switched off on the server right now. Please try '
        'again later.',
        error: true,
      ),
      const SizedBox(height: 16),
    ],
    const SectionHeading('What should change?'),
    const SizedBox(height: 8),
    RadioGroup<PhotoChange>(
      groupValue: _change,
      onChanged: (c) => setState(() => _change = c ?? _change),
      child: Column(
        children: [
          for (final change in PhotoChange.all)
            RadioListTile<PhotoChange>(
              key: Key('photo-change-${change.id}'),
              value: change,
              title: Text(change.label),
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    ),
    const SizedBox(height: 12),
    if (_error != null) ...[
      NoticeCard(_error!, error: true),
      const SizedBox(height: 12),
    ],
    AppPrimaryButton(
      key: const Key('photo-camera'),
      label: 'Take a photo',
      busy: _preparing,
      onPressed: widget.available && !_preparing
          ? () => _pick(ImageSource.camera)
          : null,
    ),
    const SizedBox(height: 12),
    OutlinedButton(
      key: const Key('photo-gallery'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: widget.available && !_preparing
          ? () => _pick(ImageSource.gallery)
          : null,
      child: const Text('Choose from gallery'),
    ),
    const SizedBox(height: 20),
    const NoticeCard(
      'Your photo is cropped to a square and its location data is removed on '
      'this phone. It is sent to the project server only to make the edit, '
      'then deleted. Please only use photos of food.',
      title: 'Privacy',
    ),
  ];

  List<Widget> _paintView() => [
    StepHeading(_change.label),
    const SizedBox(height: 6),
    Text(_change.paintHint, style: Theme.of(context).textTheme.bodyLarge),
    const SizedBox(height: 12),
    LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.plateCard),
          child: SizedBox.square(
            dimension: side,
            child: GestureDetector(
              key: const Key('paint-area'),
              onPanStart: (d) => _addPoint(d.localPosition, side, start: true),
              onPanUpdate: (d) => _addPoint(d.localPosition, side),
              onTapDown: (d) => _addPoint(d.localPosition, side, start: true),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    _photo!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    semanticLabel: 'Your meal photo',
                  ),
                  CustomPaint(painter: _StrokePainter(_strokes, _revision)),
                ],
              ),
            ),
          ),
        );
      },
    ),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('Big brush'),
          selected: _bigBrush,
          onSelected: (_) => setState(() => _bigBrush = true),
        ),
        ChoiceChip(
          label: const Text('Small brush'),
          selected: !_bigBrush,
          onSelected: (_) => setState(() => _bigBrush = false),
        ),
        TextButton(
          key: const Key('paint-undo'),
          onPressed: _strokes.isEmpty
              ? null
              : () => setState(() {
                  _strokes.removeLast();
                  _revision++;
                }),
          child: const Text('Undo'),
        ),
        TextButton(
          onPressed: _strokes.isEmpty
              ? null
              : () => setState(() {
                  _strokes.clear();
                  _revision++;
                }),
          child: const Text('Clear'),
        ),
      ],
    ),
    const SizedBox(height: 12),
    if (_error != null) ...[
      NoticeCard(_error!, error: true),
      const SizedBox(height: 12),
    ],
    AppPrimaryButton(
      key: const Key('photo-submit'),
      label: _strokes.isEmpty ? 'Paint the rice first' : 'Make the change',
      onPressed: _strokes.isEmpty ? null : _submit,
    ),
    const SizedBox(height: 8),
    TextButton(
      onPressed: _startOver,
      child: const Text('Use a different photo'),
    ),
  ];

  List<Widget> _workingView() => [
    const SizedBox(height: 60),
    Semantics(
      label: 'Editing your photo',
      child: const CupertinoActivityIndicator(radius: 16),
    ),
    const SizedBox(height: 24),
    const Text(
      'Editing your photo…',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 20),
    ),
    const SizedBox(height: 8),
    const Text(
      'This usually takes 15 to 60 seconds.',
      textAlign: TextAlign.center,
    ),
  ];

  List<Widget> _resultView() {
    final result = _result!;
    final edited = base64Decode(
      result.artifact.imageDataUrl.substring('data:image/png;base64,'.length),
    );
    Widget labelled(String label, Uint8List bytes, String semantics) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.notice),
          child: AspectRatio(
            aspectRatio: 1,
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              semanticLabel: semantics,
            ),
          ),
        ),
      ],
    );
    return [
      StepHeading(result.editTarget.label),
      const SizedBox(height: 12),
      labelled('Before', _photo!, 'Your original photo'),
      const SizedBox(height: 16),
      labelled('After', edited, result.artifact.generatedLabel),
      const SizedBox(height: 10),
      Text(
        result.artifact.generatedLabel,
        key: const Key('photo-result-label'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      Text(
        'Attempts: ${result.artifact.attempts} · Automatic check: '
        '${result.artifact.checkerPassed ? "passed" : "not passed"} '
        '(not a human review)',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      for (final notice in result.notices) ...[
        NoticeCard(notice),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 8),
      AppPrimaryButton(
        key: const Key('photo-again'),
        label: 'Try another photo',
        onPressed: _startOver,
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Back to meals'),
      ),
    ];
  }
}
