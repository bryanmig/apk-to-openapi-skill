---
name: apk-to-openapi
description: Use when you have an Android APK, APKM, or XAPK file and need to extract its REST API endpoints into an OpenAPI specification. Also use when reverse-engineering an Android app's network layer, whether native (Retrofit, Volley, OkHttp, Ktor) or React Native (Hermes bytecode).
---

# APK to OpenAPI

Decompile an Android application and extract all HTTP API endpoints into an OpenAPI 3.1.0 spec.

## Quick start

Use the `/extract-api` command:

```
/extract-api path/to/app.apk
```

## Manual pipeline

If `/extract-api` is not available, run the one-shot preparation script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/apk-to-openapi/scripts/prepare.sh <file>
```

This handles dependency checking, APK extraction, jadx decompilation, Hermes detection/decompilation, and native code scanning in a single command. It outputs a structured report listing:

- Decompiled directory and manifest paths
- API interface files (Retrofit, Volley, OkHttp, Ktor)
- Model/DTO class files
- Base URL configuration
- Authentication patterns
- GraphQL usage

Read the identified files to understand the API surface, then generate `openapi.yaml`.

For React Native apps with decompiled JS, also run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/apk-to-openapi/scripts/find-js-api-calls.sh <js-file>
```

## Individual scripts

| Script | Purpose |
|--------|---------|
| `scripts/check-deps.sh` | Verify all dependencies are installed |
| `scripts/install-dep.sh <name>` | Install a missing dependency (java, jadx, hermes-dec) |
| `scripts/extract-apk.sh <file>` | Extract base APK from APKM/XAPK bundles |
| `scripts/detect-hermes.sh <dir>` | Detect Hermes bytecode in decompiled output |
| `scripts/find-js-api-calls.sh <js>` | Search decompiled JS for API patterns |

All scripts are at `${CLAUDE_PLUGIN_ROOT}/skills/apk-to-openapi/scripts/`.
