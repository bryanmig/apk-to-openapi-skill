---
allowed-tools: Bash, Read, Glob, Grep, Write, Edit, Task
description: Extract all API endpoints from an Android APK and generate an OpenAPI specification
user-invocable: true
argument: path to APK, APKM, or XAPK file
---

# /extract-api

Extract REST API endpoints from an Android APK/APKM/XAPK and generate an OpenAPI 3.1.0 spec.

## Step 1: Prepare

Run the preparation pipeline. This checks dependencies, extracts the base APK from bundles, decompiles with jadx, detects and decompiles Hermes bytecode, and scans native code for API patterns — all in one command.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/apk-to-openapi/scripts/prepare.sh <file>
```

Use a **5-minute timeout** since jadx decompilation can be slow on large APKs.

The script outputs a structured report. Parse these fields:

| Field | Meaning |
|-------|---------|
| `DECOMPILED_DIR=<path>` | jadx output directory |
| `MANIFEST=<path>` | AndroidManifest.xml |
| `JS_FILE=<path>` | Decompiled JS file, or `NONE` |
| `API_FILES` section | Files with Retrofit `@GET/@POST/...` annotations |
| `VOLLEY_FILES` section | Files using Volley HTTP client |
| `OKHTTP_FILES` section | Files using raw OkHttp |
| `KTOR_FILES` section | Files using Ktor client |
| `MODEL_FILES` section | Files with `@SerializedName`/`@Json`/`@Serializable` |
| `BASE_URLS` section | Base URL configuration matches |
| `AUTH_PATTERNS` section | Authentication pattern matches |
| `GRAPHQL_FILES` section | Files using Apollo/GraphQL |

## Step 2: Read API sources

Read the files identified in the report. Use **parallel Read calls** to read multiple files simultaneously.

1. **AndroidManifest.xml** — Extract app package name, version, permissions, React Native indicators.

2. **API interface files** (from API_FILES) — For each Retrofit interface, extract:
   - HTTP method and path from annotations (`@GET("path")`, etc.)
   - `@Path`, `@Query`, `@QueryMap`, `@Body`, `@Header` parameters
   - Request/response model class references (return types, `@Body` types)

3. **Other HTTP client files** (VOLLEY_FILES, OKHTTP_FILES, KTOR_FILES) — Look for:
   - URL construction patterns and endpoint paths
   - Request body building
   - Response parsing into model classes

4. **Model/DTO classes** (from MODEL_FILES) — Extract:
   - Exact JSON field names from `@SerializedName("name")`, `@Json(name = "name")`, or `@JsonProperty("name")`
   - Field types (String, Int, Boolean, List, nested objects)
   - Nullable annotations

5. **Note base URLs and auth patterns** directly from the report output.

## Step 3: Extract JS endpoints (if applicable)

Skip this step if `JS_FILE=NONE`.

Run the JS API scanner:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/apk-to-openapi/scripts/find-js-api-calls.sh <JS_FILE>
```

Then read the sections of the JS file it identifies. Focus on:

- **API method registry** — Block of `r2['methodName'] = r7` assignments listing ALL endpoints.
- **Function implementations** — Search for each method name via `// Original name:` comments. Each function contains the HTTP method (`.get`/`.post`/etc.) and endpoint path.
- **Base URL config** — `baseURL` or `config.url` assignments.
- **Auth setup** — `setHeader.*Authorization` patterns.

## Step 4: Generate OpenAPI spec

Combine all discoveries into `openapi.yaml`:

```yaml
openapi: 3.1.0
info:
  title: <App Name> API
  description: REST API extracted from <package> v<version>
  version: <version from AndroidManifest>
servers:
  - url: <base URL>
security:
  - <discovered auth scheme>: []
paths:
  /<endpoint>:
    <method>:
      tags: [<functional area>]
      summary: <description>
      operationId: <method name>
      parameters: [...]
      requestBody: { ... }
      responses:
        "200":
          description: Success
          content:
            application/json:
              schema: { $ref: '#/components/schemas/...' }
components:
  securitySchemes: { ... }
  schemas:
    <Model>:
      type: object
      properties:
        <field>:
          type: <type>
```

**Rules**:
- Use native model classes (with `@SerializedName` annotations) for detailed schemas
- For JS-only endpoints without native models, use `type: object` with inferred properties
- Group endpoints by functional area into tags
- Use `operationId` matching the source method name
- Nullable fields: `type: ["string", "null"]` (OpenAPI 3.1 syntax, NOT `nullable: true`)

## Step 5: Validate

```bash
npx @redocly/cli lint openapi.yaml
```

Fix any errors. Warnings about missing `4XX` responses are acceptable.

## Step 6: Report

Summarize: total endpoints, functional areas/tags, auth method, base URL(s), validation status.
