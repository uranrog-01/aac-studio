{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load({
  config: {renderer: 'canvaskit', canvasKitVariant: 'full', canvasKitBaseUrl: 'canvaskit/'},
  onEntrypointLoaded: async function(engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
      document.getElementById('loading')?.remove();
    } catch (error) {
      document.getElementById('loading-text').textContent = 'Could not open AAC Studio. Check your connection and reload.';
      console.error(error);
    }
  }
});
