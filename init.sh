#! /usr/bin/env nix-shell
#! nix-shell --pure -i bash -p nix bash
set -eu
source ./nix-shell-init.sh

app=$(basename $PWD)

reactNativeVersion=$(cat files/package.json | grep '"react-native"' | cut -d '"' -f4)
reactNativeMacosVersion=$(cat files/package.json | grep '"react-native-macos"' | cut -d '"' -f4)
buildToolsVersion=$(nix-store --query --references $(nix-instantiate '<nixpkgs>' -A androidsdk) | grep 'android-build-tools' | sed 's/.*build-tools-r\(.*\).drv/\1/')

# install react-native-cli and react-native-macos-cli
mkdir $app
cp files/package.json $app/
test -f files/npm-shrinkwrap && cp files/npm-shrinkwrap.json $app/
nix-shell -p nodejs --run "cd $app && npm install react-native-cli && npm install react-native-macos-cli"

# add correct react-native-macos version for the cli-tool to install.
sed -i "s/npm install --save react-native-macos/npm install --save react-native-macos@$reactNativeMacosVersion/g" $app/node_modules/react-native-macos-cli/index.js

# init ios/android/macos project
nix-shell -p nodejs python2 --run "\
     (echo yes | node ./$app/node_modules/react-native-macos-cli/index.js init $app --version=$reactNativeMacosVersion && rm $app/.gitignore)\
  && (echo yes | node ./$app/node_modules/react-native-cli/index.js init $app --version=$reactNativeVersion)\
  && (cd $app; node ./node_modules/react-native-cli/index.js android)"

# Android package signing
echo "MYAPP_RELEASE_STORE_FILE=my-release-key.keystore" >> $app/android/gradle.properties
echo "MYAPP_RELEASE_KEY_ALIAS=my-key-alias" >> $app/android/gradle.properties
echo "MYAPP_RELEASE_STORE_PASSWORD=foobar" >> $app/android/gradle.properties
echo "MYAPP_RELEASE_KEY_PASSWORD=foobar" >> $app/android/gradle.properties
sed -i "s/defaultConfig {/signingConfigs {release {storeFile file(MYAPP_RELEASE_STORE_FILE); storePassword MYAPP_RELEASE_STORE_PASSWORD;keyAlias MYAPP_RELEASE_KEY_ALIAS;keyPassword MYAPP_RELEASE_KEY_PASSWORD}}; buildTypes { release { signingConfig signingConfigs.release }}; defaultConfig {/g" $app/android/app/build.gradle
sed -i "s/minifyEnabled/signingConfig signingConfigs.release; minifyEnabled/g" $app/android/app/build.gradle

sed -i "s/^android [{]/android { adbOptions.timeOutInMs = 8*60*1000; com.android.ddmlib.DdmPreferences.setTimeOut(8*60*1000)/" $app/android/app/build.gradle

# change project buildTools to that available from nixpkgs
sed -i "s/buildToolsVersion \"[^\"]*\"/buildToolsVersion \"$buildToolsVersion\"/" $app/android/app/build.gradle

# install all needed npm-stuff
cp -fR files/* $app/
rm $app/index.windows.js
nix-shell -p nodejs --run "cd $app && npm install"

# init Windows project
nix-shell -p nodejs --run "cd $app && ./node_modules/rnpm/bin/cli windows"
cp -f files/index.windows.js $app/

# 10.0.2.2 is a VirtualBox alias for localhost
sed -i "s/localhost:8081/10.0.2.2:8081/" $app/node_modules/react-native-windows/ReactWindows/ReactNative.Shared/DevSupport/DevServerHelper.cs
# change VS project output path outside of the network share.
sed -r 's/(<OutputPath>)([^<]*)/\1c:\\vagrant-build\\\2/g' $app/windows/$app/$app.csproj > $app/windows/$app/$app.csproj.temp && mv $app/windows/$app/$app.csproj.temp $app/windows/$app/$app.csproj
# enable private network to access react-packager
sed -i 's/<\/Capabilities>/<Capability Name="privateNetworkClientServer"\/><\/Capabilities>/' $app/windows/$app/Package.appxmanifest

# ignore ghcjs-generated files from transform since it's too slow
sed -i "s/function transform(src, filename, options) {/function transform(src, filename, options) { if (filename.indexOf('all.js') > -1) return { code: src };/" $app/node_modules/react-native/packager/transformer.js
sed -i "s/function transform(src, filename, options) {/function transform(src, filename, options) { if (filename.indexOf('all.js') > -1) return { code: src };/" $app/node_modules/react-native-macos/packager/transformer.js

# I don't know why on earth I need this...
sed -i "s/this.flags = flags;/flags = flags || ''; this.flags = flags;/" $app/node_modules/commander/index.js

./init-addons.sh
