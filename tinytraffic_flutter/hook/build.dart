import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // flutter_scene:init:start
    // Import .glb and .fscene sources under assets/, loadable by source path
    // with loadScene (and hot-reloadable). A no-op when there are no scenes.
    buildScenes(
      buildInput: input,
      buildOutput: output,
      compressTextures: true,
    );
    // Compile .fmat materials under assets/, loadable by source path with
    // loadFmatMaterial (and hot-reloadable). A no-op when there are none.
    await buildMaterials(buildInput: input, buildOutput: output);
    // flutter_scene:init:end

    // Compile the engine's own shaders into this app's generated tree too.
    // flutter_scene's hook already does this into its package, but marks the
    // iOS Metal folder `platforms: [ios]`, and the Apple Watch build
    // (flutter-watchos) filters assets as `macos`, so the watch, which renders
    // with the iOS Metal shaders, would never get them. This copy is listed in
    // our pubspec, where we can include it for the watch.
    await buildEngineAssets(buildInput: input, buildOutput: output);
  });
}
