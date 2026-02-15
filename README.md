# APK to OpenAPI

A Claude Code plugin that extracts REST API specifications from Android applications. Point it at any APK, APKM, or XAPK file and it will decompile the app, find every HTTP endpoint, and generate a validated OpenAPI 3.1.0 spec.

Handles both **native Android** apps (Java/Kotlin with Retrofit) and **React Native** apps (including Hermes bytecode).

## Installation

### Option 1: Add via Claude Code (recommended)

Inside a Claude Code session, run the following slash commands:

```
/plugin marketplace add bryanmig/apk-to-openapi-skill
/plugin install apk-to-openapi
```

You can scope the install to your project (shared with your team via `.claude/settings.json`) or keep it user-level (personal):

```
# Project scope — committed to repo, shared with collaborators
/plugin install apk-to-openapi --scope project

# User scope — global, only on your machine (default)
/plugin install apk-to-openapi --scope user
```

### Option 2: Manual settings.json

Add the marketplace and enable the plugin directly in your `.claude/settings.json` (user-level) or your project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "apk-to-openapi": {
      "source": {
        "source": "github",
        "repo": "bryanmig/apk-to-openapi-skill"
      }
    }
  },
  "enabledPlugins": {
    "apk-to-openapi@apk-to-openapi": true
  }
}
```

### Option 3: Local development

Clone the repo and point Claude Code at it directly:

```bash
git clone https://github.com/bryanmig/apk-to-openapi-skill.git
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
- **Volley** requests (`StringRequest`, `JsonObjectRequest`)
- **OkHttp** raw usage (`Request.Builder`, `.newCall()`)
- **Ktor** client calls (`client.get`, `client.post`)
- **GraphQL** / Apollo Client queries and mutations
- Model classes with `@SerializedName` / `@Json` / `@Serializable` / `@JsonProperty` annotations
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
bash plugins/apk-to-openapi/skills/apk-to-openapi/scripts/check-deps.sh

# Install missing dependencies
bash plugins/apk-to-openapi/skills/apk-to-openapi/scripts/install-dep.sh java
bash plugins/apk-to-openapi/skills/apk-to-openapi/scripts/install-dep.sh jadx
bash plugins/apk-to-openapi/skills/apk-to-openapi/scripts/install-dep.sh hermes-dec
```

## Manual Usage

### One-shot pipeline (recommended)

Run the full pipeline in a single command:

```bash
bash plugins/apk-to-openapi/skills/apk-to-openapi/scripts/prepare.sh app.apkm
```

This handles everything: dependency checking, APK extraction, jadx decompilation, Hermes detection/decompilation, and native code scanning. It outputs a structured report listing all discovered API files, model classes, base URLs, and auth patterns.

### Step-by-step

If you prefer to run each step individually:

```bash
SCRIPTS=plugins/apk-to-openapi/skills/apk-to-openapi/scripts

# 1. Check / install dependencies
bash $SCRIPTS/check-deps.sh
bash $SCRIPTS/install-dep.sh java     # if missing
bash $SCRIPTS/install-dep.sh jadx     # if missing
bash $SCRIPTS/install-dep.sh hermes-dec  # if missing

# 2. Extract base APK from bundle
BASE_APK=$(bash $SCRIPTS/extract-apk.sh app.apkm)

# 3. Decompile native code
jadx -d app-decompiled --show-bad-code "$BASE_APK"

# 4. Check for React Native / Hermes
bash $SCRIPTS/detect-hermes.sh app-decompiled
# Output: HERMES:<path>, PLAINJS:<path>, or NONE

# 5. Decompile Hermes bytecode (if detected)
mkdir -p app-decompiled-js
hbc-decompiler <bundle-path> app-decompiled-js/index.js

# 6. Search JS code for API endpoints
bash $SCRIPTS/find-js-api-calls.sh app-decompiled-js/index.js

# 7. Validate the generated spec
npx @redocly/cli lint openapi.yaml
```

### JS API search options

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
├── .claude-plugin/
│   └── marketplace.json                # Marketplace catalog
└── plugins/
    └── apk-to-openapi/
        ├── .claude-plugin/
        │   └── plugin.json             # Plugin metadata
        ├── commands/
        │   └── extract-api.md          # /extract-api command definition
        └── skills/
            └── apk-to-openapi/
                ├── SKILL.md            # Full workflow documentation
                └── scripts/
                    ├── prepare.sh          # One-shot pipeline (recommended)
                    ├── check-deps.sh       # Verify dependencies
                    ├── install-dep.sh      # Install missing deps
                    ├── extract-apk.sh      # Extract base APK from bundles
                    ├── detect-hermes.sh    # Detect Hermes bytecode
                    └── find-js-api-calls.sh # Extract JS API patterns
```

## License

MIT
