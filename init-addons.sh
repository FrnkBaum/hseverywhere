#! /usr/bin/env nix-shell
#! nix-shell --pure -i bash -p nix bash
set -eu
source ./nix-shell-init.sh

app=$(basename $PWD)
buildToolsVersion=$(nix-store --query --references $(nix-instantiate '<nixpkgs>' -A androidsdk) | grep 'android-build-tools' | sed 's/.*build-tools-r\(.*\).drv/\1/')

cp register_addons*.js $app/

nix-shell -p nodejs --run "cd $app && cat ../addons.txt | xargs -L1 npm install --save"
nix-shell -p nodejs --run "cd $app && cat ../addons.txt | sed 's/@.*//' | xargs -L1 node_modules/rnpm/bin/cli link"

# change addon android buildTools version to that available from nixpkgs
nix-shell --run "cd hseverywhere && cat ../addons.txt | sed 's/@.*//' | xargs -I {} sed -i 's/buildToolsVersion \"[^\"]*\"/buildToolsVersion \"24.0.2\"/' node_modules/{}/android/build.gradle"
