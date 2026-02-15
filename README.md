# APK to OpenAPI

A Claude Code plugin that extracts REST API specifications from Android applications. Point it at any APK, APKM, or XAPK file and it will decompile the app, find every HTTP endpoint, and generate a validated OpenAPI 3.1.0 spec.

Handles both **native Android** apps (Java/Kotlin with Retrofit) and **React Native** apps (including Hermes bytecode).

## Installation

```bash
# Install from GitHub
claude plugin add github:bryanmig/apk-to-openapi

# Or test locally without installing
claude --plugin-dir ./apk-to-openapi
```

## Quick Start

Once installed, run:

```
/extract-api path/to/app.apkm
```

Claude walks through the full pipeline automatically:

1. Extract the base APK from the bundle
2. Decompile native code with jadx
3. Detect and decompile Hermes bytecode (if React Native)
4. Search both native and JS layers for API endpoints
5. Generate a validated `openapi.yaml`

## What It Extracts

### Native Layer (Java/Kotlin)

- **Retrofit** annotations (`@GET`, `@POST`, `@PUT`, `@DELETE`, `@PATCH`) for endpoint definitions
- Model classes with `@SerializedName` / `@Json` / `@Serializable` annotations for request/response schemas
- Base URLs from `BuildConfig` or `Retrofit.Builder` calls
- Auth interceptors (`Authorization`, `Bearer`, `Basic` headers)

### React Native Layer (JavaScript)

- Hermes bytecode detection via magic bytes (`c6 1f bc 03`)
- Decompiled pseudo-JavaScript from **hermes-dec**
- API class definitions via `// Original name:` comments
- Method registries and HTTP calls (`.get`, `.post`, `.put`, `.delete`, `.patch`)
- Base URL and auth header configuration

## Prerequisites

| Dependency | Purpose | Install |
|------------|---------|---------|
| Java JDK 17+ | Runtime for jadx | `brew install openjdk@17` |
| jadx | Android decompiler | `brew install jadx` |
| Python 3 | Runtime for hermes-dec | `brew install python3` |
| hermes-dec | Hermes bytecode decompiler | `pip3 install hermes-dec` |
| npx (optional) | OpenAPI validation | Comes with Node.js |

Or use the included scripts:

```bash
# Check what's installed
bash skills/apk-to-openapi/scripts/check-deps.sh

# Install missing dependencies
bash skills/apk-to-openapi/scripts/install-dep.sh java
bash skills/apk-to-openapi/scripts/install-dep.sh jadx
bash skills/apk-to-openapi/scripts/install-dep.sh hermes-dec
```

## Manual Usage

If you prefer to run the steps yourself instead of using `/extract-api`:

```bash
# 1. Extract base APK from bundle
BASE_APK=$(bash skills/apk-to-openapi/scripts/extract-apk.sh app.apkm)

# 2. Decompile native code
jadx -d app-decompiled --show-bad-code "$BASE_APK"

# 3. Check for React Native / Hermes
bash skills/apk-to-openapi/scripts/detect-hermes.sh app-decompiled
# Output: HERMES:<path>, PLAINJS:<path>, or NONE

# 4. Decompile Hermes bytecode (if detected)
mkdir -p app-decompiled-js
hbc-decompiler <bundle-path> app-decompiled-js/index.js

# 5. Search native code for API endpoints
grep -rn '@GET\|@POST\|@PUT\|@DELETE\|@PATCH' app-decompiled/sources/
grep -rn 'BASE_URL\|API_URL\|Retrofit\.Builder' app-decompiled/sources/

# 6. Search JS code for API endpoints
bash skills/apk-to-openapi/scripts/find-js-api-calls.sh app-decompiled-js/index.js

# 7. Validate the generated spec
npx @redocly/cli lint openapi.yaml
```

### JS API Search Options

The `find-js-api-calls.sh` script supports targeted searches:

```bash
bash find-js-api-calls.sh index.js --methods    # API method registry
bash find-js-api-calls.sh index.js --http        # HTTP method calls
bash find-js-api-calls.sh index.js --config      # Base URL config
bash find-js-api-calls.sh index.js --auth        # Auth patterns
bash find-js-api-calls.sh index.js --endpoints   # Endpoint path strings
bash find-js-api-calls.sh index.js --all         # Everything (default)
```

## Output

The plugin produces:

- **`openapi.yaml`** — A complete OpenAPI 3.1.0 spec with endpoints, schemas, auth, and tags
- **Summary** — Endpoint count, functional areas, authentication method, base URL(s), and validation status

You can use the generated spec with any OpenAPI-compatible tool:

```bash
# Validate
npx @redocly/cli lint openapi.yaml

# Generate HTML docs
npx @redocly/cli build-docs openapi.yaml -o docs.html

# Import into Postman, Insomnia, Bruno, etc.
```

## Project Structure

```
apk-to-openapi/
├── README.md
├── commands/
│   └── extract-api.md                  # /extract-api command definition
├── skills/
│   └── apk-to-openapi/
│       ├── SKILL.md                    # Full workflow documentation
│       └── scripts/
│           ├── check-deps.sh           # Verify dependencies
│           ├── install-dep.sh          # Install missing deps
│           ├── extract-apk.sh          # Extract base APK from bundles
│           ├── detect-hermes.sh        # Detect Hermes bytecode
│           └── find-js-api-calls.sh    # Extract JS API patterns
└── .claude-plugin/
    └── plugin.json                     # Plugin metadata
```

## License

MIT
