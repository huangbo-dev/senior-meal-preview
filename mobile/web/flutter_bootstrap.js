{{flutter_js}}
{{flutter_build_config}}

// All renderer and font assets stay on this local application origin.
// No service worker is registered; do not hide API failures with cached data.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
    fontFallbackBaseUrl: "assets/fonts/",
  },
});
