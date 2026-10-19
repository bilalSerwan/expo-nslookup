const { withPodfile } = require("expo/config-plugins");

// fmt 11.0.2 (pulled in by React Native 0.79) fails to compile as C++20 with Xcode 26's clang:
// "call to consteval function ... is not a constant expression". Compiling just the fmt pod as C++17
// avoids its consteval path. `npx expo prebuild` regenerates ios/Podfile, so a hand edit there is lost;
// this plugin re-applies the setting on every prebuild.
const MARKER = "# [withFmtCxx17] compile fmt as C++17 for Xcode 26";

const SNIPPET = `
    ${MARKER}
    installer.pods_project.targets.each do |target|
      next unless target.name == 'fmt'
      target.build_configurations.each do |build_config|
        build_config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'c++17'
      end
    end
`;

// Must run after react_native_post_install, which sets the C++ standard for every pod.
const AFTER_RN_POST_INSTALL =
  /(\n[ \t]*react_native_post_install\([\s\S]*?\n[ \t]*\)\n)/;

module.exports = function withFmtCxx17(config) {
  return withPodfile(config, (config) => {
    const podfile = config.modResults.contents;
    if (podfile.includes(MARKER)) return config;
    if (!AFTER_RN_POST_INSTALL.test(podfile)) {
      throw new Error(
        "withFmtCxx17: could not find react_native_post_install(...) in ios/Podfile",
      );
    }
    config.modResults.contents = podfile.replace(
      AFTER_RN_POST_INSTALL,
      `$1${SNIPPET}`,
    );
    return config;
  });
};
