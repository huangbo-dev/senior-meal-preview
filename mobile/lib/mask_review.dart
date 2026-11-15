import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'api.dart';

/// Returns the confirmed full rice region. Back or Cancel abandons the edit.
Future<Uint8List?> reviewRiceMask(
  BuildContext context,
  MealApi api,
  Uint8List photo, {
  Uint8List? initial,
}) => Navigator.of(context).push<Uint8List>(
  MaterialPageRoute(
    builder: (_) => RiceMaskReview(api: api, photo: photo, initial: initial),
  ),
);

class RiceMaskReview extends StatefulWidget {
  const RiceMaskReview({
    super.key,
    required this.api,
    required this.photo,
    this.initial,
  });
  final MealApi api;
  final Uint8List photo;
  final Uint8List? initial;
  @override
  State<RiceMaskReview> createState() => _RiceMaskReviewState();
}

class _Mark {
  _Mark(this.add, this.width, Offset first) : points = [first];
  final bool add;
  final double width;
  final List<Offset> points;
}

void _drawMask(Canvas canvas, Size size, ui.Image? base, List<_Mark> marks) {
  canvas.save();
  canvas.scale(size.width, size.height);
  const bounds = Rect.fromLTWH(0, 0, 1, 1);
  canvas.drawRect(bounds, Paint()..color = Colors.black);
  if (base != null) {
    canvas.drawImageRect(
      base,
      Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
      bounds,
      Paint()..filterQuality = FilterQuality.none,
    );
  }
  for (final mark in marks) {
    final paint = Paint()
      ..color = mark.add ? Colors.white : Colors.black
      ..strokeWidth = mark.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(mark.points.first, mark.width / 2, paint);
    if (mark.points.length > 1) {
      canvas.drawPath(
        Path()..addPolygon(mark.points, false),
        paint..style = PaintingStyle.stroke,
      );
    }
  }
  canvas.restore();
}

class _Overlay extends CustomPainter {
  _Overlay(this.base, this.marks, this.revision);
  final ui.Image? base;
  final List<_Mark> marks;
  final int revision;
  @override
  void paint(Canvas canvas, Size size) {
    // White mask pixels become translucent turquoise; black pixels are transparent.
    canvas.saveLayer(
      Offset.zero & size,
      Paint()
        ..colorFilter = const ColorFilter.matrix([
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          210,
          0,
          0,
          0,
          0,
          180,
          0.52,
          0,
          0,
          0,
          0,
        ]),
    );
    _drawMask(canvas, size, base, marks);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Overlay old) =>
      revision != old.revision || base != old.base;
}

class _RiceMaskReviewState extends State<RiceMaskReview> {
  final _marks = <_Mark>[];
  ui.Image? _base;
  bool _add = false, _loading = true, _saving = false, _show = true;
  double _width = .035;
  int _revision = 0;
  int? _pointer;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _base?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final bytes = widget.initial ?? await widget.api.riceMask(widget.photo);
      final codec = await ui.instantiateImageCodec(bytes);
      final ui.Image image;
      try {
        image = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      if (!mounted) {
        image.dispose();
        return;
      }
      if (image.width != 1024 || image.height != 1024) {
        image.dispose();
        throw const FormatException();
      }
      setState(() {
        _base = image;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _add = true;
        _message = error is ApiException && error.code == 'rice_not_found'
            ? 'No rice was detected. Mark the visible rice to continue.'
            : 'The outline could not be loaded. Mark the rice yourself or cancel.';
      });
    }
  }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() {
      _saving = true;
    });
    try {
      final recorder = ui.PictureRecorder();
      _drawMask(Canvas(recorder), const Size.square(1024), _base, _marks);
      final picture = recorder.endRecording();
      final image = await picture.toImage(1024, 1024);
      picture.dispose();
      try {
        final rgba = (await image.toByteData())!;
        int selected = 0;
        for (int i = 0; i < rgba.lengthInBytes; i += 4) {
          if (rgba.getUint8(i) > 127) selected++;
        }
        if (selected < .005 * 1024 * 1024 || selected > .85 * 1024 * 1024) {
          if (mounted) {
            setState(() {
              _saving = false;
              _message =
                  'Mark just the visible rice (between 0.5% and 85% of the photo).';
            });
          }
          return;
        }
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        if (mounted) {
          Navigator.pop(
            context,
            png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          );
        }
      } finally {
        image.dispose();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _message = 'Could not prepare the mask. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review rice area')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Keep the highlight on visible rice. Erase chicken, plate and other foods.',
              ),
              if (_loading)
                const LinearProgressIndicator(semanticsLabel: 'Finding rice'),
              if (_message != null)
                Text(_message!, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, box) {
                  final side = box.maxWidth;
                  Offset point(Offset p) => Offset(
                    (p.dx / side).clamp(0, 1),
                    (p.dy / side).clamp(0, 1),
                  );
                  return AspectRatio(
                    aspectRatio: 1,
                    child: RawGestureDetector(
                      gestures: {
                        EagerGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              EagerGestureRecognizer
                            >(EagerGestureRecognizer.new, (_) {}),
                      },
                      child: Listener(
                        key: const Key('rice-review-canvas'),
                        onPointerDown: (e) {
                          if (_loading ||
                              _saving ||
                              !_show ||
                              _pointer != null) {
                            return;
                          }
                          setState(() {
                            _pointer = e.pointer;
                            _marks.add(
                              _Mark(_add, _width, point(e.localPosition)),
                            );
                            _revision++;
                          });
                        },
                        onPointerMove: (e) {
                          if (_pointer == e.pointer) {
                            setState(() {
                              _marks.last.points.add(point(e.localPosition));
                              _revision++;
                            });
                          }
                        },
                        onPointerCancel: (e) {
                          if (_pointer == e.pointer) {
                            setState(() => _pointer = null);
                          }
                        },
                        onPointerUp: (e) {
                          if (_pointer == e.pointer) {
                            setState(() => _pointer = null);
                          }
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              widget.photo,
                              fit: BoxFit.fill,
                              semanticLabel: 'Original meal',
                            ),
                            if (!_loading && _show)
                              CustomPaint(
                                painter: _Overlay(_base, _marks, _revision),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (!_loading) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Erase'),
                      selected: !_add,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() {
                              _add = false;
                              _show = true;
                            }),
                    ),
                    ChoiceChip(
                      label: const Text('Add rice'),
                      selected: _add,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() {
                              _add = true;
                              _show = true;
                            }),
                    ),
                    TextButton(
                      onPressed: _marks.isEmpty || _saving || _pointer != null
                          ? null
                          : () => setState(() {
                              _marks.removeLast();
                              _revision++;
                            }),
                      child: const Text('Undo'),
                    ),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _show = !_show),
                      child: Text(_show ? 'Hide highlight' : 'Show highlight'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Brush size'),
                    Expanded(
                      child: Slider(
                        value: _width,
                        min: .008,
                        max: .12,
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _width = v),
                      ),
                    ),
                  ],
                ),
                FilledButton(
                  onPressed: _saving ? null : _confirm,
                  child: const Text('Use this area and generate'),
                ),
              ],
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
