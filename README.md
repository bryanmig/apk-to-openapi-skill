# Skylight Android API

An extracted OpenAPI 3.1.0 specification for the [Skylight Frame](https://www.ourskylight.com) REST API, reverse-engineered from the Skylight Android app (v1.97.0). This repository also includes a reusable **APK-to-OpenAPI** toolkit (Claude Code plugin + shell scripts) that automates decompilation and API extraction from any Android application.

## What's Here

| Path | Description |
|------|-------------|
| `openapi.yaml` | Complete OpenAPI 3.1.0 spec — 110+ endpoints across 22 tags |
| `skills/apk-to-openapi/` | Reusable Claude Code skill for extracting APIs from any APK |
| `commands/extract-api.md` | `/extract-api` command definition for Claude Code |
| `apkm-extract/` | Extracted base APK and bundle metadata |

## Skylight API Overview

The extracted spec documents the full Skylight Frame REST API:

- **Base URL:** `https://app.ourskylight.com/api`
- **Auth:** HTTP Basic (user ID + token)
- **Format:** JSON:API-style responses (`data` / `included` envelopes)

### Endpoint Categories

| Tag | Description | Examples |
|-----|-------------|----------|
| Auth | Login, registration, password reset | `POST /users`, `POST /sessions` |
| User | Profile & account management | `GET /user`, `PUT /user` |
| Frames | Household management | `GET /frames`, `POST /frames` |
| Devices | Physical frame hardware | `GET /frames/{id}/devices` |
| Messages | Photos & videos | `GET /frames/{id}/messages` |
| Reactions | Likes & comments | `POST /frames/{id}/messages/{id}/likes` |
| Albums | Photo organization | `GET /frames/{id}/albums` |
| Calendar | Events & scheduling | `GET /frames/{id}/calendar_events` |
| Categories | Family member profiles | `GET /frames/{id}/categories` |
| Meals | Meal planning | `GET /frames/{id}/meals` |
| Chores | Tasks & chores | `GET /frames/{id}/chores` |
| Lists | Shared family lists | `GET /frames/{id}/lists` |
| Rewards | Reward system | `GET /frames/{id}/rewards` |
| Subscriptions | Skylight Plus | `GET /plus_subscriptions` |
| AI Sidekick | AI-powered features | `POST /auto_creation_intents` |
| Upload | Media file uploads | `POST /upload_url` |

## Using the OpenAPI Spec

View or interact with the spec using any OpenAPI-compatible tool:

```bash
# Validate with Redocly
npx @redocly/cli lint openapi.yaml

# Generate HTML docs
npx @redocly/cli build-docs openapi.yaml -o docs.html

# Import into Postman, Insomnia, Bruno, etc.
# Just open/import openapi.yaml
```

## APK-to-OpenAPI Toolkit

The `skills/apk-to-openapi/` directory contains a general-purpose toolkit for extracting API specifications from any Android app. It handles:

- **APK/APKM/XAPK** bundle formats (auto-extracts base APK from split bundles)
- **Native Android code** decompilation (Java/Kotlin via jadx)
- **React Native Hermes bytecode** decompilation (via hermes-dec)
- **API endpoint extraction** from both native Retrofit annotations and JS HTTP calls
- **OpenAPI 3.1.0 generation** with schemas, auth, and tags

### Prerequisites

| Dependency | Purpose | Install |
|------------|---------|---------|
| Java JDK 17+ | Runtime for jadx | `brew install openjdk@17` |
| jadx | Android decompiler | `brew install jadx` |
| Python 3 | Runtime for hermes-dec | `brew install python3` |
| hermes-dec | Hermes bytecode decompiler | `pip3 install hermes-dec` |
| npx (optional) | OpenAPI validation | Comes with Node.js |

Or use the included install script:

```bash
# Check what's installed
bash skills/apk-to-openapi/scripts/check-deps.sh

# Install missing dependencies
bash skills/apk-to-openapi/scripts/install-dep.sh java
bash skills/apk-to-openapi/scripts/install-dep.sh jadx
bash skills/apk-to-openapi/scripts/install-dep.sh hermes-dec
```

### Usage with Claude Code

This repo is a [Claude Code plugin](https://docs.anthropic.com/en/docs/claude-code). Install it and use the `/extract-api` command:

```
/extract-api path/to/app.apkm
```

Claude will walk through the full extraction pipeline:
1. Extract the base APK from the bundle
2. Decompile native code with jadx
3. Detect and decompile Hermes bytecode (if React Native)
4. Search both native and JS layers for API endpoints
5. Generate a validated `openapi.yaml`

### Manual Usage

If you prefer to run the steps yourself:

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
# Search for specific pattern categories
bash find-js-api-calls.sh index.js --methods    # API method registry
bash find-js-api-calls.sh index.js --http        # HTTP method calls
bash find-js-api-calls.sh index.js --config      # Base URL config
bash find-js-api-calls.sh index.js --auth        # Auth patterns
bash find-js-api-calls.sh index.js --endpoints   # Endpoint path strings
bash find-js-api-calls.sh index.js --all         # Everything (default)
```

## How It Works

The extraction pipeline targets two layers of a typical Android app:

### Native Layer (Java/Kotlin)
- Decompiles DEX bytecode back to Java/Kotlin source using **jadx**
- Searches for **Retrofit** annotations (`@GET`, `@POST`, etc.) to find API interface definitions
- Reads model classes with `@SerializedName` / `@Json` annotations for request/response schemas
- Extracts base URLs from `BuildConfig` or `Retrofit.Builder` calls
- Identifies auth interceptors (`Authorization`, `Bearer`, `Basic` headers)

### React Native Layer (JavaScript)
- Detects Hermes bytecode by checking magic bytes (`c6 1f bc 03`)
- Decompiles Hermes bytecode to pseudo-JavaScript using **hermes-dec**
- Locates API class definitions via `// Original name:` comments
- Extracts method registries (`r2['methodName'] = r7` patterns)
- Finds HTTP calls (`.get`, `.post`, `.put`, `.delete`, `.patch`)
- Identifies base URL and auth header configuration

## Project Structure

```
skylight-android-api/
├── README.md
├── openapi.yaml                        # Generated API spec (110+ endpoints)
├── commands/
│   └── extract-api.md                  # Claude Code /extract-api command
├── skills/
│   └── apk-to-openapi/
│       ├── SKILL.md                    # Full workflow documentation
│       └── scripts/
│           ├── check-deps.sh           # Verify dependencies
│           ├── install-dep.sh          # Install missing deps
│           ├── extract-apk.sh          # Extract base APK from bundles
│           ├── detect-hermes.sh        # Detect Hermes bytecode
│           └── find-js-api-calls.sh    # Extract JS API patterns
├── apkm-extract/
│   ├── base.apk                        # Extracted base APK
│   └── info.json                       # Bundle metadata
└── .claude-plugin/
    └── plugin.json                     # Plugin metadata
```

## License

MIT
