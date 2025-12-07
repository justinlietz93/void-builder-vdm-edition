# Void Builder – Rust CLI Build Notes

This document explains how the Rust-based CLI is built inside Void Builder, when it runs, and how to opt out of building it for local or constrained environments.

The CLI build is orchestrated by:

- [`build.sh`](void-builder/build.sh:1), which is invoked by the top-level helper [`dev/build.sh`](void-builder/dev/build.sh:1).
- The Rust-specific script [`build_cli.sh`](void-builder/build_cli.sh:1), which compiles the CLI binary for each supported platform and architecture and installs it into the built VSCode/VSCode-win32/VSCode-darwin trees.

---

## 1. Where and when the CLI is built

The main builder entry point is [`dev/build.sh`](void-builder/dev/build.sh:1). It:

1. Sets up environment (e.g. `OS_NAME`, `VSCODE_ARCH`, `CI_BUILD`).
2. Fetches or reuses VS Code sources via `get_repo.sh` / `version.sh`.
3. Delegates to [`build.sh`](void-builder/build.sh:1) to perform the actual build.
4. Optionally runs asset packaging via `prepare_assets.sh`.

Inside [`build.sh`](void-builder/build.sh:1), the Rust CLI is built via [`build_cli.sh`](void-builder/build_cli.sh:1) in the following branches:

- **macOS (`OS_NAME=osx`)**

  ```bash
  npm run gulp "vscode-darwin-${VSCODE_ARCH}-min-ci"
  find "../VSCode-darwin-${VSCODE_ARCH}" -print0 | xargs -0 touch -c
  . ../build_cli.sh
  ```

  The CLI build always runs for macOS desktop builds (subject to `SKIP_CLI_BUILD`, described below).

- **Windows (`OS_NAME=windows`)**

  ```bash
  if [[ "${CI_BUILD}" == "no" ]]; then
    . ../build/windows/rtf/make.sh
    npm run gulp "vscode-win32-${VSCODE_ARCH}-min-ci"
    . ../build_cli.sh
  fi
  ```

  On Windows, the CLI build runs only when `CI_BUILD="no"` (i.e., in the local/dev build path rather than the CI packaging jobs).

- **Linux (`OS_NAME=linux`)**

  ```bash
  if [[ "${CI_BUILD}" == "no" ]]; then
    npm run gulp "vscode-linux-${VSCODE_ARCH}-min-ci"
    find "../VSCode-linux-${VSCODE_ARCH}" -print0 | xargs -0 touch -c
    . ../build_cli.sh
  fi
  ```

  Similarly, on Linux the CLI is built only when `CI_BUILD="no"`.

The Rust-specific logic lives in [`build_cli.sh`](void-builder/build_cli.sh:1). In summary:

- It expects to run from the `cli/` subdirectory and relies on:

  - `APP_NAME`, `VSCODE_QUALITY`, and `VSCODE_ARCH` exported by [`dev/build.sh`](void-builder/dev/build.sh:1).
  - `serverApplicationName`, `tunnelApplicationName`, and `nameShort` from [`product.json`](void-builder/product.json:1).

- It configures:

  - `VSCODE_CLI_APP_NAME` and `VSCODE_CLI_BINARY_NAME` using Node + [`product.json`](void-builder/product.json:1).
  - Update/download endpoints for the CLI (pointing at the `voideditor` GitHub repos).
  - Platform-specific targets:

    - macOS: `aarch64-apple-darwin` or `x86_64-apple-darwin`
    - Windows: `aarch64-pc-windows-msvc` or `x86_64-pc-windows-msvc`
    - Linux: `aarch64-unknown-linux-gnu`, `armv7-unknown-linux-gnueabihf`, or `x86_64-unknown-linux-gnu`

- It installs an OpenSSL prebuilt package:

  ```bash
  npm pack @vscode/openssl-prebuilt@0.0.11
  mkdir openssl
  tar -xvzf vscode-openssl-prebuilt-0.0.11.tgz --strip-components=1 --directory=openssl
  ```

- It configures `OPENSSL_LIB_DIR`, `OPENSSL_INCLUDE_DIR`, and (for cross builds) cross-compilation toolchains.
- It runs `rustup target add "${VSCODE_CLI_TARGET}"` and then:

  ```bash
  cargo build --release --target "${VSCODE_CLI_TARGET}" --bin=code
  ```

- It copies the resulting binary into the appropriate build output:

  - macOS: `../VSCode-darwin-${VSCODE_ARCH}/…/bin/${TUNNEL_APPLICATION_NAME}`
  - Windows: `../VSCode-win32-${VSCODE_ARCH}/bin/${TUNNEL_APPLICATION_NAME}.exe`
  - Linux: `../VSCode-linux-${VSCODE_ARCH}/bin/${TUNNEL_APPLICATION_NAME}`

In short: **if you run the standard builder pipeline for a desktop platform with `CI_BUILD="no"`, the Rust CLI will be built by default**.

---

## 2. Prerequisites for building the CLI

The Rust CLI build has more prerequisites than the main Electron desktop bundle:

- A working **Rust toolchain** (including `cargo` and `rustup`).
- Platform-appropriate **C/C++ build tools**:
  - On Windows: MSVC build tools and the CRT (as implied by `-C target-feature=+crt-static` and `/guard:cf` flags).
  - On Linux/macOS: GCC/Clang and standard development headers, plus toolchains for cross-compilation if you are targeting non-native architectures.
- Node/npm to install `@vscode/openssl-prebuilt` (already a dependency of the main VSCodium/Void build pipeline).

On machines without these prerequisites (especially Windows hosts without a full Rust/MSVC setup), the CLI build is the most likely point of failure.

---

## 3. `SKIP_CLI_BUILD` – opt out of CLI builds

To make local and constrained builds more robust, the builder now supports a `SKIP_CLI_BUILD` environment variable.

### 3.1. Default behavior

At the top of [`build.sh`](void-builder/build.sh:1), the following logic is applied:

```bash
# Default to building the Rust CLI unless explicitly disabled.
if [[ -z "${SKIP_CLI_BUILD}" ]]; then
  export SKIP_CLI_BUILD="no"
fi
```

- If `SKIP_CLI_BUILD` is **unset**, it is defaulted to `"no"`.
- This preserves existing behavior: **CI and existing local scripts continue to build the CLI by default.**

### 3.2. Conditional CLI invocation

Each platform branch in [`build.sh`](void-builder/build.sh:25) now checks `SKIP_CLI_BUILD` before invoking [`build_cli.sh`](void-builder/build_cli.sh:1):

- **macOS**

  ```bash
  find "../VSCode-darwin-${VSCODE_ARCH}" -print0 | xargs -0 touch -c

  if [[ "${SKIP_CLI_BUILD}" != "yes" ]]; then
    . ../build_cli.sh
  else
    echo "Skipping Rust CLI build (SKIP_CLI_BUILD=yes)"
  fi
  ```

- **Windows**

  ```bash
  if [[ "${CI_BUILD}" == "no" ]]; then
    . ../build/windows/rtf/make.sh
    npm run gulp "vscode-win32-${VSCODE_ARCH}-min-ci"

    if [[ "${VSCODE_ARCH}" != "x64" ]]; then
      SHOULD_BUILD_REH="no"
      SHOULD_BUILD_REH_WEB="no"
    fi

    if [[ "${SKIP_CLI_BUILD}" != "yes" ]]; then
      . ../build_cli.sh
    else
      echo "Skipping Rust CLI build (SKIP_CLI_BUILD=yes)"
    fi
  fi
  ```

- **Linux**

  ```bash
  if [[ "${CI_BUILD}" == "no" ]]; then
    npm run gulp "vscode-linux-${VSCODE_ARCH}-min-ci"

    find "../VSCode-linux-${VSCODE_ARCH}" -print0 | xargs -0 touch -c

    if [[ "${SKIP_CLI_BUILD}" != "yes" ]]; then
      . ../build_cli.sh
    else
      echo "Skipping Rust CLI build (SKIP_CLI_BUILD=yes)"
    fi
  fi
  ```

When `SKIP_CLI_BUILD="yes"`, the CLI build is entirely skipped and a single log line is printed for visibility.

---

## 4. Recommended usage patterns

### 4.1. Local development where CLI is not required

For many local IDE development scenarios (iterating on the GUI/Crux integration, testing editor features, etc.), the Rust CLI is not strictly required. In these cases, you can opt out of building it to avoid toolchain issues or reduce build time.

**Linux/macOS example:**

```bash
cd void-builder
SKIP_CLI_BUILD=yes ./dev/build.sh
```

**Windows example (PowerShell invoking the VSCodium-style builder):**

```powershell
cd C:\git\Void-Genesis\Void-Genesis\void-builder
$env:SKIP_CLI_BUILD = "yes"
powershell -ExecutionPolicy ByPass -File .\dev\build.ps1
```

**Windows example (Git Bash):**

```bash
cd /c/git/Void-Genesis/Void-Genesis/void-builder
SKIP_CLI_BUILD=yes ./dev/build.sh
```

In all of the above, the desktop artifacts (e.g. `VSCode-win32-x64`, `VSCode-darwin-arm64`, `VSCode-linux-x64`) are still built; only the Rust CLI binary is omitted.

### 4.2. CI and release builds

For CI and release pipelines where the CLI is considered part of the supported artifact set:

- Do **not** set `SKIP_CLI_BUILD`, or set it explicitly to `"no"`.
- Ensure that the Rust toolchain and OpenSSL dependencies are installed according to the platform requirements inferred from [`build_cli.sh`](void-builder/build_cli.sh:1).

This keeps behavior aligned with upstream VSCodium while making the local developer workflow more forgiving.

---

## 5. Operational notes and caveats

- Skipping the CLI build means:

  - You will not have a built Rust CLI binary inside the `VSCode-*/bin/` directory.
  - Any workflows or scripts that rely on the CLI (e.g., remote tunnel helpers or CLI-based automation) will not be available from that build.

- The core Void Genesis IDE application **does not** depend on the Rust CLI to start or to talk to Crux; the CLI is a separate entry point.

- If you encounter Rust- or OpenSSL-related build failures during the CLI step, you can:

  1. Re-run the build with `SKIP_CLI_BUILD=yes` to unblock IDE development.
  2. Later, provision the necessary toolchain and re-run without `SKIP_CLI_BUILD` to produce a full build including the CLI.

---

## 6. Cross-reference

For more context on the overall build pipeline and how Void Builder is used to produce distributable artifacts, see:

- [`README.md`](void-builder/README.md:1) – high-level purpose of Void Builder and its relationship to VSCodium and the GitHub Actions workflows.
- [`docs/howto-build.md`](void-builder/docs/howto-build.md:1) – upstream VSCodium build instructions and flags for `dev/build.sh`.
- [`DEV_WORKFLOW.md`](void_genesis_ide/DEV_WORKFLOW.md:1) – canonical dev workflow for editing the `void_genesis_ide` editor fork and building via Void Builder.

These documents, together with this file, define the expected and supported behavior for the Rust CLI lifecycle in local and CI builds.