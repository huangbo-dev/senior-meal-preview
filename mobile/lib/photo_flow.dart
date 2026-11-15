import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
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

/// Estimated share of a photo edit that is done after [seconds], for a change
/// that usually takes [typicalSeconds].
///
/// The server reports no progress, so this is an estimate from elapsed time
/// alone: it reaches about three quarters at the usual time and then slows,
/// never showing complete before the result arrives.
double photoEditProgress(int seconds, int typicalSeconds) =>
    math.min(0.97, 1 - math.exp(-1.5 * seconds / typicalSeconds));

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

/// Take or choose a meal photo and get the edited photo back.
///
/// When the server finds the rice itself ([autoMask]) nothing is painted: the
/// photo is sent as soon as it is chosen. Painting remains as a fallback when
/// the rice is not found, and as the only way on servers without that ability.
class PhotoEditPage extends StatefulWidget {
  const PhotoEditPage({
    super.key,
    required this.api,
    required this.available,
    this.autoMask = false,
    this.picker = pickWithImagePicker,
    this.onBackToMeals,
  });

  final MealApi api;

  /// Called by "Back to meals" when the page is a tab; a pushed page pops.
  final VoidCallback? onBackToMeals;

  /// Whether the server advertised `photo_upload` (a real model is connected).
  final bool available;

  /// Whether the server advertised `auto_mask` (it finds the rice itself).
  final bool autoMask;
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

  /// The finger that is painting; a second finger is ignored.
  int? _paintPointer;
  bool _preparing = false;
  String? _error;
  PhotoEditResult? _result;
  final Stopwatch _waited = Stopwatch();
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startWaiting() {
    _waited
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopWaiting() {
    _ticker?.cancel();
    _ticker = null;
    _waited.stop();
  }

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
      if (widget.autoMask) unawaited(_submit(painted: false));
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

  /// Sends the photo. With [painted] the strokes mark the area to change;
  /// otherwise the server finds the rice itself.
  Future<void> _submit({bool painted = true}) async {
    final photo = _photo;
    if (photo == null || (painted && _strokes.isEmpty)) return;
    setState(() {
      _stage = _Stage.working;
      _error = null;
    });
    _startWaiting();
    try {
      final result = await widget.api.editPhoto(
        changeIds: _change.ids,
        imagePng: photo,
        maskPng: painted ? await maskPng(_strokes) : null,
      );
      _stopWaiting();
      if (!mounted) return;
      setState(() {
        _result = result;
        _stage = _Stage.result;
      });
    } catch (error) {
      _stopWaiting();
      if (!mounted) return;
      final message = error is ApiException
          ? error.message
          : 'Something went wrong. Please try again.';
      final riceNotFound =
          error is ApiException && error.code == 'rice_not_found';
      setState(() {
        if (painted) {
          _stage = _Stage.paint;
          _error = message;
        } else if (riceNotFound && _change.paintable) {
          // Let the user show where the rice is instead of giving up.
          _stage = _Stage.paint;
          _error =
              'We could not find the rice by ourselves. Paint over it below, '
              'or use a different photo.';
        } else {
          _stage = _Stage.choose;
          _photo = null;
          _error = message;
        }
      });
    }
  }

  /// From a result the user is unhappy with: mark the area by hand instead.
  void _paintInstead() => setState(() {
    _stage = _Stage.paint;
    _result = null;
    _error = null;
    _strokes.clear();
    _revision++;
  });

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
      bottomNavigationBar: _pinnedAction() == null
          ? null
          : PinnedActionBar(child: _pinnedAction()!),
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

  Widget _submitButton() => AppPrimaryButton(
    key: const Key('photo-submit'),
    label: _strokes.isEmpty ? 'Paint the rice first' : 'Make the change',
    onPressed: _strokes.isEmpty ? null : _submit,
  );

  Widget _againButton() => AppPrimaryButton(
    key: const Key('photo-again'),
    label: 'Try another photo',
    onPressed: _startOver,
  );

  /// The stage's main action, pinned at the bottom on roomy screens.
  Widget? _pinnedAction() {
    if (!pinPrimaryAction(context)) return null;
    return switch (_stage) {
      _Stage.paint => _submitButton(),
      _Stage.result => _againButton(),
      _Stage.choose || _Stage.working => null,
    };
  }

  List<Widget> _chooseView() => [
    const StepHeading('Change your own meal photo'),
    const SizedBox(height: 8),
    Text(
      widget.autoMask
          ? 'Take a photo of a rice meal and see a healthier version of it. '
                'The rice is found for you.'
          : 'Take a photo of a rice meal, mark the rice, and see one change '
                'made to it.',
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
            if (widget.autoMask || change.paintable)
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
            // The page scrolls, and a scroll view would take every vertical
            // drag that starts on the photo. The eager recognizer claims
            // touches on the photo at once, so painting never scrolls the page.
            child: RawGestureDetector(
              gestures: {
                EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      EagerGestureRecognizer
                    >(EagerGestureRecognizer.new, (_) {}),
              },
              child: Listener(
                key: const Key('paint-area'),
                onPointerDown: (e) {
                  if (_paintPointer != null) return;
                  _paintPointer = e.pointer;
                  _addPoint(e.localPosition, side, start: true);
                },
                onPointerMove: (e) {
                  if (e.pointer == _paintPointer) {
                    _addPoint(e.localPosition, side);
                  }
                },
                onPointerUp: (e) {
                  if (e.pointer == _paintPointer) _paintPointer = null;
                },
                onPointerCancel: (e) {
                  if (e.pointer == _paintPointer) _paintPointer = null;
                },
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
    if (!pinPrimaryAction(context)) ...[
      _submitButton(),
      const SizedBox(height: 8),
    ],
    TextButton(
      onPressed: _startOver,
      child: const Text('Use a different photo'),
    ),
  ];

  List<Widget> _workingView() {
    final seconds = _waited.elapsed.inSeconds;
    final typical = _change.typicalSeconds;
    final late = seconds >= typical + 5;
    final status = seconds < 2
        ? 'Sending your photo…'
        : late
        ? 'Still working. It may be trying again…'
        : 'Editing your photo…';
    return [
      const SizedBox(height: 60),
      Text(
        status,
        key: const Key('photo-working-status'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 20),
      ),
      const SizedBox(height: 20),
      Semantics(
        label: 'Editing your photo, $seconds seconds so far',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            key: const Key('photo-working-progress'),
            value: photoEditProgress(seconds, typical),
            minHeight: 12,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        '$seconds s so far',
        key: const Key('photo-working-elapsed'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        'This change usually takes about $typical seconds. '
        'A hard one can take up to a minute. The bar is an estimate.',
        textAlign: TextAlign.center,
      ),
    ];
  }

  List<Widget> _resultView() {
    final result = _result!;
    final edited = base64Decode(
      result.artifact.imageDataUrl.substring('data:image/png;base64,'.length),
    );
    return [
      StepHeading(_change.label),
      const SizedBox(height: 6),
      Text(
        'Drag across the photo to compare before and after.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      BeforeAfterSlider(
        before: Image.memory(_photo!, fit: BoxFit.cover, gaplessPlayback: true),
        after: Image.memory(edited, fit: BoxFit.cover, gaplessPlayback: true),
        afterLabel: result.artifact.generatedLabel,
      ),
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
      if (!pinPrimaryAction(context)) ...[
        _againButton(),
        const SizedBox(height: 8),
      ],
      if (widget.autoMask && _change.paintable)
        TextButton(
          key: const Key('photo-paint-instead'),
          onPressed: _paintInstead,
          child: const Text('Not right? Mark the rice yourself'),
        ),
      TextButton(
        key: const Key('photo-back-to-meals'),
        onPressed:
            widget.onBackToMeals ?? () => Navigator.of(context).maybePop(),
        child: const Text('Back to meals'),
      ),
    ];
  }
}
