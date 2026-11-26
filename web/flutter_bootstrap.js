{{flutter_js}}
{{flutter_build_config}}

// Start the engine (without Flutter's own service worker — sw.js handles
// offline caching), then fade the splash out.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    const splash = document.getElementById('splash');
    if (splash) {
      splash.classList.add('fade');
      setTimeout(function () { splash.remove(); }, 600);
    }
  }
});
