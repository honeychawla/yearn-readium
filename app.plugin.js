const {
  withDangerousMod,
  withPlugins,
  IOSConfig,
} = require('@expo/config-plugins');
const path = require('path');
const fs = require('fs');

/**
 * Expo config plugin for react-native-readium
 * This plugin configures iOS to properly link the native Swift modules
 */
const withReactNativeReadium = (config) => {
  return withPlugins(config, [
    // Add Swift bridging header configuration
    (config) =>
      withDangerousMod(config, [
        'ios',
        async (config) => {
          const projectRoot = config.modRequest.projectRoot;
          const iosProjectPath = path.join(
            projectRoot,
            'ios',
            config.modRequest.projectName
          );

          // Ensure bridging header exists
          const bridgingHeaderPath = path.join(
            iosProjectPath,
            `${config.modRequest.projectName}-Bridging-Header.h`
          );

          // Create or update bridging header
          const bridgingHeaderContent = `//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import <React/RCTBridgeModule.h>
#import <React/RCTViewManager.h>
#import <React/RCTEventEmitter.h>
`;

          // Create the file if it doesn't exist
          if (!fs.existsSync(bridgingHeaderPath)) {
            fs.writeFileSync(bridgingHeaderPath, bridgingHeaderContent);
            console.log('✅ Created bridging header for react-native-readium');
          }

          return config;
        },
      ]),

    // Configure Xcode project settings
    (config) =>
      withDangerousMod(config, [
        'ios',
        async (config) => {
          const projectName = config.modRequest.projectName || '';
          const xcodeProject = IOSConfig.XcodeUtils.getPbxproj(
            config.modRequest.platformProjectRoot
          );

          // Set Swift version
          const configurations =
            xcodeProject.pbxXCBuildConfigurationSection();
          Object.keys(configurations).forEach((key) => {
            const configuration = configurations[key];
            if (typeof configuration === 'object' && configuration.buildSettings) {
              // Set Swift version
              configuration.buildSettings.SWIFT_VERSION = '5.0';

              // Set bridging header path
              configuration.buildSettings.SWIFT_OBJC_BRIDGING_HEADER =
                `${projectName}/${projectName}-Bridging-Header.h`;

              // Enable modules
              configuration.buildSettings.CLANG_ENABLE_MODULES = 'YES';

              // Always embed Swift standard libraries
              configuration.buildSettings.ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES =
                'YES';
            }
          });

          fs.writeFileSync(
            config.modRequest.platformProjectRoot + '/project.pbxproj',
            xcodeProject.writeSync()
          );

          return config;
        },
      ]),
  ]);
};

module.exports = withReactNativeReadium;
