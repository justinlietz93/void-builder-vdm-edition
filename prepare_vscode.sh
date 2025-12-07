#!/usr/bin/env bash
# shellcheck disable=SC1091,2154

set -e

# include common functions
. ./utils.sh

# Void - disable icon copying, we already handled icons
# if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
#   cp -rp src/insider/* vscode/
# else
#   cp -rp src/stable/* vscode/
# fi

# Void - keep our license...
# cp -f LICENSE vscode/LICENSE.txt

cd vscode || { echo "'vscode' dir not found"; exit 1; }

../update_settings.sh

# apply patches
{ set +x; } 2>/dev/null

echo "APP_NAME=\"${APP_NAME}\""
echo "APP_NAME_LC=\"${APP_NAME_LC}\""
echo "BINARY_NAME=\"${BINARY_NAME}\""
echo "GH_REPO_PATH=\"${GH_REPO_PATH}\""
echo "ORG_NAME=\"${ORG_NAME}\""

echo "Applying patches at ../patches/*.patch..." # Void comment
for file in ../patches/*.patch; do
  if [[ -f "${file}" ]]; then
    apply_patch "${file}"
  fi
done

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  echo "Applying insider patches..." # Void comment
  for file in ../patches/insider/*.patch; do
    if [[ -f "${file}" ]]; then
      apply_patch "${file}"
    fi
  done
fi

if [[ -d "../patches/${OS_NAME}/" ]]; then
  echo "Applying OS patches (${OS_NAME})..." # Void comment
  for file in "../patches/${OS_NAME}/"*.patch; do
    if [[ -f "${file}" ]]; then
      apply_patch "${file}"
    fi
  done
fi

echo "Applying user patches..." # Void comment
for file in ../patches/user/*.patch; do
  if [[ -f "${file}" ]]; then
    apply_patch "${file}"
  fi
done

set -x

export ELECTRON_SKIP_BINARY_DOWNLOAD=1
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

if [[ "${OS_NAME}" == "linux" ]]; then
  export VSCODE_SKIP_NODE_VERSION_CHECK=1

   if [[ "${npm_config_arch}" == "arm" ]]; then
    export npm_config_arm_version=7
  fi
elif [[ "${OS_NAME}" == "windows" ]]; then
  if [[ "${npm_config_arch}" == "arm" ]]; then
    export npm_config_arm_version=7
  fi
else
  if [[ "${CI_BUILD}" != "no" ]]; then
    clang++ --version
  fi
fi

mv .npmrc .npmrc.bak
cp ../npmrc .npmrc

for i in {1..5}; do # try 5 times
  if [[ "${CI_BUILD}" != "no" && "${OS_NAME}" == "osx" ]]; then
    CXX=clang++ npm ci && break
  else
    npm ci && break
  fi

  if [[ $i == 3 ]]; then
    echo "Npm install failed too many times" >&2
    exit 1
  fi
  echo "Npm install failed $i, trying again..."

  sleep $(( 15 * (i + 1)))
done

mv .npmrc.bak .npmrc

setpath() {
  # Update a top-level JSON string property without requiring jq.
  # Usage: setpath <baseNameWithoutExt> <key> <stringValue>
  { set +x; } 2>/dev/null
  local file="${1}.json"
  local key="${2}"
  local value="${3}"
  node - "$file" "$key" "$value" << 'EOF'
const fs = require('fs');
const [file, key, value] = process.argv.slice(2);
const json = JSON.parse(fs.readFileSync(file, 'utf8'));
json[key] = value;
fs.writeFileSync(file, JSON.stringify(json, null, 2));
EOF
  set -x
}

setpath_json() {
  # Update a top-level JSON property with a JSON value (object/array/etc.) without jq.
  # Usage: setpath_json <baseNameWithoutExt> <key> <jsonString>
  { set +x; } 2>/dev/null
  local file="${1}.json"
  local key="${2}"
  local value="${3}"
  node - "$file" "$key" "$value" << 'EOF'
const fs = require('fs');
const [file, key, raw] = process.argv.slice(2);
const json = JSON.parse(fs.readFileSync(file, 'utf8'));
let parsed;
try {
  parsed = JSON.parse(raw);
} catch {
  // Fallback: treat as string if not valid JSON.
  parsed = raw;
}
json[key] = parsed;
fs.writeFileSync(file, JSON.stringify(json, null, 2));
EOF
  set -x
}

# product.json
cp product.json{,.bak}

setpath "product" "checksumFailMoreInfoUrl" "https://go.microsoft.com/fwlink/?LinkId=828886"
setpath "product" "documentationUrl" "https://voideditor.com"
# setpath_json "product" "extensionsGallery" '{"serviceUrl": "https://open-vsx.org/vscode/gallery", "itemUrl": "https://open-vsx.org/vscode/item"}'
setpath "product" "introductoryVideosUrl" "https://go.microsoft.com/fwlink/?linkid=832146"
setpath "product" "keyboardShortcutsUrlLinux" "https://go.microsoft.com/fwlink/?linkid=832144"
setpath "product" "keyboardShortcutsUrlMac" "https://go.microsoft.com/fwlink/?linkid=832143"
setpath "product" "keyboardShortcutsUrlWin" "https://go.microsoft.com/fwlink/?linkid=832145"
setpath "product" "licenseUrl" "https://github.com/voideditor/void/blob/main/LICENSE.txt"
# setpath_json "product" "linkProtectionTrustedDomains" '["https://open-vsx.org"]'
# setpath "product" "releaseNotesUrl" "https://go.microsoft.com/fwlink/?LinkID=533483#vscode"
setpath "product" "reportIssueUrl" "https://github.com/voideditor/void/issues/new"
setpath "product" "requestFeatureUrl" "https://github.com/voideditor/void/issues/new"
setpath "product" "tipsAndTricksUrl" "https://go.microsoft.com/fwlink/?linkid=852118"
setpath "product" "twitterUrl" "https://x.com/thevoideditor"

if [[ "${DISABLE_UPDATE}" != "yes" ]]; then
  setpath "product" "updateUrl" "https://raw.githubusercontent.com/voideditor/versions/refs/heads/main"
  setpath "product" "downloadUrl" "https://github.com/voideditor/binaries/releases"
fi

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  setpath "product" "nameShort" "Void - Insiders"
  setpath "product" "nameLong" "Void - Insiders"
  setpath "product" "applicationName" "void-insiders"
  setpath "product" "dataFolderName" ".void-insiders"
  setpath "product" "linuxIconName" "void-insiders"
  setpath "product" "quality" "insider"
  setpath "product" "urlProtocol" "void-insiders"
  setpath "product" "serverApplicationName" "void-server-insiders"
  setpath "product" "serverDataFolderName" ".void-server-insiders"
  setpath "product" "darwinBundleIdentifier" "ai.voideditor.VoidInsiders"
  setpath "product" "win32AppUserModelId" "Void.VoidInsiders"
  setpath "product" "win32DirName" "Void Insiders"
  setpath "product" "win32MutexName" "voidinsiders"
  setpath "product" "win32NameVersion" "Void Insiders"
  setpath "product" "win32RegValueName" "VoidInsiders"
  setpath "product" "win32ShellNameShort" "Void Insiders"
  setpath "product" "win32AppId" "{{5893CE20-77AA-4856-A655-ECE65CBCF1C7}"
  setpath "product" "win32x64AppId" "{{7A261980-5847-44B6-B554-31DF0F5CDFC9}"
  setpath "product" "win32arm64AppId" "{{EE4FF7AA-A874-419D-BAE0-168C9DBCE211}"
  setpath "product" "win32UserAppId" "{{FA3AE0C7-888E-45DA-AB58-B8E33DE0CB2E}"
  setpath "product" "win32x64UserAppId" "{{5B1813E3-1D97-4E00-AF59-C59A39CF066A}"
  setpath "product" "win32arm64UserAppId" "{{C2FA90D8-B265-41B1-B909-3BAEB21CAA9D}"
else
  setpath "product" "nameShort" "Void"
  setpath "product" "nameLong" "Void"
  setpath "product" "applicationName" "void"
  setpath "product" "linuxIconName" "void"
  setpath "product" "quality" "stable"
  setpath "product" "urlProtocol" "void"
  setpath "product" "serverApplicationName" "void-server"
  setpath "product" "serverDataFolderName" ".void-server"
  setpath "product" "darwinBundleIdentifier" "com.void"
  setpath "product" "win32AppUserModelId" "Void.Void"
  setpath "product" "win32DirName" "Void"
  setpath "product" "win32MutexName" "void"
  setpath "product" "win32NameVersion" "Void"
  setpath "product" "win32RegValueName" "Void"
  setpath "product" "win32ShellNameShort" "Void"
  # Void - already set in product
  # setpath "product" "win32AppId" "{{88DA3577-054F-4CA1-8122-7D820494CFFB}"
  # setpath "product" "win32x64AppId" "{{9D394D01-1728-45A7-B997-A6C82C5452C3}"
  # setpath "product" "win32arm64AppId" "{{0668DD58-2BDE-4101-8CDA-40252DF8875D}"
  # setpath "product" "win32UserAppId" "{{0FD05EB4-651E-4E78-A062-515204B47A3A}"
  # setpath "product" "win32x64UserAppId" "{{8BED5DC1-6C55-46E6-9FE6-18F7E6F7C7F1}"
  # setpath "product" "win32arm64UserAppId" "{{F6C87466-BC82-4A8F-B0FF-18CA366BA4D8}"
fi

# Merge upstream product.json with our overlay ../product.json without jq.
{ set +x; } 2>/dev/null
node << 'EOF'
const fs = require('fs');
const base = JSON.parse(fs.readFileSync('product.json', 'utf8'));
const overlay = JSON.parse(fs.readFileSync('../product.json', 'utf8'));

function deepMerge(target, source) {
  for (const [k, v] of Object.entries(source)) {
    if (v && typeof v === 'object' && !Array.isArray(v)) {
      if (!Object.prototype.hasOwnProperty.call(target, k) || typeof target[k] !== 'object') {
        target[k] = {};
      }
      deepMerge(target[k], v);
    } else {
      target[k] = v;
    }
  }
  return target;
}

const merged = deepMerge(base, overlay);
fs.writeFileSync('product.json', JSON.stringify(merged, null, 2));
EOF
set -x

cat product.json

# package.json
cp package.json{,.bak}

setpath "package" "version" "${RELEASE_VERSION%-insider}"

replace 's|Microsoft Corporation|Void|' package.json

cp resources/server/manifest.json{,.bak}

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  setpath "resources/server/manifest" "name" "Void - Insiders"
  setpath "resources/server/manifest" "short_name" "Void - Insiders"
else
  setpath "resources/server/manifest" "name" "Void"
  setpath "resources/server/manifest" "short_name" "Void"
fi

cp resources/server/manifest.json{,.bak}

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  setpath "resources/server/manifest" "name" "Void - Insiders"
  setpath "resources/server/manifest" "short_name" "Void - Insiders"
else
  # Void already has this
  setpath "resources/server/manifest" "name" "Void"
  setpath "resources/server/manifest" "short_name" "Void"
fi

# announcements
# replace "s|\\[\\/\\* BUILTIN_ANNOUNCEMENTS \\*\\/\\]|$( tr -d '\n' < ../announcements-builtin.json )|" src/vs/workbench/contrib/welcomeGettingStarted/browser/gettingStarted.ts

../undo_telemetry.sh

replace 's|Microsoft Corporation|Void|' build/lib/electron.js
replace 's|Microsoft Corporation|Void|' build/lib/electron.ts
replace 's|([0-9]) Microsoft|\1 Void|' build/lib/electron.js
replace 's|([0-9]) Microsoft|\1 Void|' build/lib/electron.ts

if [[ "${OS_NAME}" == "linux" ]]; then
  # microsoft adds their apt repo to sources
  # unless the app name is code-oss
  # as we are renaming the application to void
  # we need to edit a line in the post install template
  if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
    sed -i "s/code-oss/void-insiders/" resources/linux/debian/postinst.template
  else
    sed -i "s/code-oss/void/" resources/linux/debian/postinst.template
  fi

  # fix the packages metadata
  # code.appdata.xml
  sed -i 's|Visual Studio Code|Void|g' resources/linux/code.appdata.xml
  sed -i 's|https://code.visualstudio.com/docs/setup/linux|https://voideditor.com|' resources/linux/code.appdata.xml
  sed -i 's|https://code.visualstudio.com/home/home-screenshot-linux-lg.png|https://vscodium.com/img/vscodium.png|' resources/linux/code.appdata.xml
  sed -i 's|https://code.visualstudio.com|https://voideditor.com|' resources/linux/code.appdata.xml

  # control.template
  sed -i 's|Microsoft Corporation <vscode-linux@microsoft.com>|Void Team <team@voideditor.com>|'  resources/linux/debian/control.template
  sed -i 's|Visual Studio Code|Void|g' resources/linux/debian/control.template
  sed -i 's|https://code.visualstudio.com/docs/setup/linux|https://voideditor.com|' resources/linux/debian/control.template
  sed -i 's|https://code.visualstudio.com|https://voideditor.com|' resources/linux/debian/control.template

  # code.spec.template
  sed -i 's|Microsoft Corporation|Void Team|' resources/linux/rpm/code.spec.template
  sed -i 's|Visual Studio Code Team <vscode-linux@microsoft.com>|Void Team <team@voideditor.com>|' resources/linux/rpm/code.spec.template
  sed -i 's|Visual Studio Code|Void|' resources/linux/rpm/code.spec.template
  sed -i 's|https://code.visualstudio.com/docs/setup/linux|https://voideditor.com|' resources/linux/rpm/code.spec.template
  sed -i 's|https://code.visualstudio.com|https://voideditor.com|' resources/linux/rpm/code.spec.template

  # snapcraft.yaml
  sed -i 's|Visual Studio Code|Void|'  resources/linux/rpm/code.spec.template
elif [[ "${OS_NAME}" == "windows" ]]; then
  # code.iss
  sed -i 's|https://code.visualstudio.com|https://voideditor.com|' build/win32/code.iss
  sed -i 's|Microsoft Corporation|Void|' build/win32/code.iss
fi

cd ..
