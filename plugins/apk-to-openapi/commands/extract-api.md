---
allowed-tools: Bash, Read, Glob, Grep, Write, Edit, Task, WebFetch
description: Extract all API endpoints from an Android APK and generate an OpenAPI specification
user-invocable: true
argument: path to APK, APKM, or XAPK file
---

# /extract-api

Extract all API endpoints from an Android application and generate a comprehensive OpenAPI 3.1.0 specification.

## Instructions

You are starting the APK-to-OpenAPI extraction workflow. Follow the skill document at `${CLAUDE_PLUGIN_ROOT}/skills/apk-to-openapi/SKILL.md` exactly.

### Step 1: Get the target file

If the user provided a file path as an argument, use that. Otherwise, ask the user for the path to the APK, APKM, or XAPK file.

### Step 2: Follow the SKILL.md workflow

Read and follow `${CLAUDE_PLUGIN_ROOT}/skills/apk-to-openapi/SKILL.md` which covers:

1. **Dependencies** — Check and install java, jadx, python3, hermes-dec
2. **Prepare Input** — Extract base APK from APKM/XAPK bundles if needed
3. **Decompile Native Code** — jadx decompilation and structure analysis
4. **Detect & Decompile Hermes** — Find React Native JS bundles and decompile Hermes bytecode
5. **Extract API Endpoints** — Search both native Java/Kotlin and decompiled JS for all endpoints
6. **Generate OpenAPI Spec** — Produce a validated OpenAPI 3.1.0 YAML file

### Step 3: Deliver results

Output the OpenAPI spec to `openapi.yaml` in the working directory (or a user-specified path). Report a summary of:
- Total endpoints discovered
- Functional areas/tags
- Authentication method
- Base URL(s)
