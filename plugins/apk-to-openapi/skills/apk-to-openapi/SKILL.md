---
name: apk-to-openapi
description: Use when you have an Android APK, APKM, or XAPK file and need to extract its REST API endpoints into an OpenAPI specification. Also use when reverse-engineering an Android app's network layer, whether native (Retrofit) or React Native (Hermes bytecode).
---

# APK to OpenAPI

Decompile an Android application's native code and React Native JavaScript bundle, extract all HTTP API endpoints from both layers, and generate a comprehensive OpenAPI 3.1.0 specification.

## Prerequisites

Java JDK 17+, jadx, Python 3, and hermes-dec are required. Run the dependency checker:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/apk-to-openapi/scripts/check-deps.sh
```

If dependencies are missing, install them:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/apk-to-openapi/scripts/install-dep.sh <dep>
```

Available deps: `java`, `jadx`, `hermes-dec`. Re-run `check-deps.sh` after installation to confirm.

## Workflow

### Phase 1: Prepare Input

The script handles `.apk`, `.apkm`, and `.xapk` formats. APKM and XAPK are ZIP bundles containing split APKs — the script extracts the base APK automatically.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/apk-to-openapi/scripts/extract-apk.sh <file>
```

Output: prints the path to the base APK file. For plain `.apk` input, it prints the input path unchanged.

### Phase 2: Decompile Native Code

Run jadx on the base APK:

```bash
jadx -d <basename>-decompiled --show-bad-code <base-apk>
```

After decompilation:

1. **Read AndroidManifest.xml** from `<output>/resources/AndroidManifest.xml`
   - Find main Activity, Application class, permissions
   - Note any React Native indicators (`ReactActivity`, `ReactApplication`, Hermes flags)

2. **Survey package structure** under `<output>/sources/`
   - Identify the main app package
   - Look for `api`, `network`, `data`, `repository`, `service`, `retrofit`, `http` packages

3. **Search for native API endpoints**:
   ```bash
   # Retrofit annotations
   grep -rn '@GET\|@POST\|@PUT\|@DELETE\|@PATCH\|@HEAD' <output>/sources/

   # Base URL configuration
   grep -rn 'BASE_URL\|API_URL\|baseUrl\|api_base' <output>/sources/

   # Auth interceptors
   grep -rn 'Authorization\|Bearer\|Basic\|addHeader\|Interceptor' <output>/sources/

   # OkHttp / HTTP clients
   grep -rn 'OkHttpClient\|HttpUrl\|Retrofit\.Builder' <output>/sources/
   ```

4. **Read all discovered API interface files** (Retrofit `@GET`/`@POST` annotated interfaces) to extract:
   - HTTP methods and paths
   - Query/path parameters
   - Request/response model classes

5. **Read model classes** referenced by API interfaces. Look for:
   - `@SerializedName` (Gson) — exact JSON field names
   - `@Json` (Moshi) — exact JSON field names
   - `@Serializable` (Kotlinx) — field names from serialization descriptors

### Phase 3: Detect & Decompile Hermes Bytecode

Check if the app uses React Native with Hermes:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/apk-to-openapi/scripts/detect-hermes.sh <output>
```

The script:
- Searches for `index.android.bundle` in `<output>/resources/assets/`
- Checks magic bytes (`c6 1f bc 03`) to identify Hermes bytecode
- Reports: `HERMES:<path>`, `PLAINJS:<path>`, or `NONE`

**If HERMES**: Decompile with hermes-dec:
```bash
mkdir -p <basename>-decompiled-js
hbc-decompiler <bundle-path> <basename>-decompiled-js/index.js
```

The decompiled output is pseudo-JavaScript with register-based variables (`r0`, `r1`, etc.) and `// Original name:` comments preserving function names.

**If PLAINJS**: Copy/use the bundle directly.

**If NONE**: Skip to Phase 5 — the app is native-only.

### Phase 4: Extract JS API Endpoints

Run the JS API extraction script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/apk-to-openapi/scripts/find-js-api-calls.sh <decompiled-js-dir>/index.js
```

The script searches for these patterns in hermes-dec output:

| Pattern | What it finds |
|---------|---------------|
| `// Original name: Api,` | API class definition |
| `r2['methodName'] = r` | Method registry (all endpoint method names) |
| `.apisauce` | HTTP client usage |
| `.post\|.get\|.put\|.delete\|.patch` followed by `.bind` | HTTP method calls |
| `baseURL\|config.url` | Base URL configuration |
| `setHeader.*Authorization` | Auth header setup |
| `'endpoint/path'` string literals near `.bind` calls | Endpoint paths |

**After running the script**, manually read the sections of the decompiled JS it identifies to extract the full details for each endpoint:
- HTTP method (GET/POST/PUT/DELETE/PATCH)
- URL path
- Request body structure (if any)
- Query parameters (if any)

**Key technique**: The API method registry (typically a block of `r2['name'] = r7` assignments) lists ALL endpoint method names in one place. Use these names to search for the corresponding function implementations, which contain the actual HTTP calls with paths and methods.

### Phase 5: Generate OpenAPI Specification

Combine all discoveries from native and JS extraction into an OpenAPI 3.1.0 YAML file.

**Structure**:

```yaml
openapi: 3.1.0
info:
  title: <App Name> API
  description: |
    REST API extracted from <app package> v<version> by decompiling
    native Android code (jadx) and React Native Hermes bytecode (hermes-dec).
  version: <app version from AndroidManifest>

servers:
  - url: <base URL from BuildConfig or JS config>
    description: Production

security:
  - <auth scheme discovered>: []

tags:
  - name: <Functional Area>
    description: <what this group of endpoints does>

paths:
  /<endpoint>:
    <method>:
      tags: [<area>]
      summary: <what it does>
      operationId: <methodName from JS or Retrofit>
      parameters: [...]   # path params, query params
      requestBody: {...}   # if POST/PUT/PATCH
      responses:
        "200":
          description: <response description>
          content:
            application/json:
              schema: {...}

components:
  securitySchemes:
    <auth>: {...}
  schemas:
    <ModelName>:
      type: object
      properties:
        <field>:  # from @SerializedName or JS object literals
          type: <type>
```

**Guidelines for schema generation**:
- Use native model classes (with `@SerializedName` annotations) for detailed schemas
- For JS-only endpoints without native models, use `type: object` with inferred properties
- Group endpoints by functional area into tags
- Use `operationId` matching the method name from the API class
- For nullable fields, use `type: ["string", "null"]` (OpenAPI 3.1 syntax, NOT `nullable: true`)

**Validate** the spec if npx is available:
```bash
npx @redocly/cli lint openapi.yaml
```

Fix any errors. Warnings about missing `4XX` responses are acceptable since we're extracting from decompiled code without full error response details.

## Output

Deliver:
1. **OpenAPI spec** at `openapi.yaml` in the working directory
2. **Summary** with: endpoint count, functional areas, auth method, base URL, and validation status
