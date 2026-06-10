---
name: api-design
description: Generate API contract (OpenAPI + Markdown) from design docs and tech plans. Reads office-hours and eng-review outputs, infers interfaces, asks only unclear questions. Outputs api-contract.md and api-contract.yaml to project root.
---

# API Design Skill

Generate API contract from design docs and tech plans.

## When to Apply

Apply this skill when the user:
- Runs `/api-design`
- Asks to define API interfaces for a project
- Needs an API contract before frontend development

Do NOT apply when:
- User asks about a specific API bug or fix
- User is only asking conceptual questions

## Trigger

```
/api-design
```

## Prerequisites

This skill expects:
- A design doc from `/office-hours` (in `~/.gstack/projects/$SLUG/`)
- A tech plan from `/plan-eng-review` (optional but recommended)
- A git repository with project code

If no design doc found, warn:
> ⚠️ No design doc found. Run `/office-hours` first, or proceed with manual input.

If no eng-review found, warn:
> ⚠️ No eng-review found. Proceeding without tech plan context.

---

## Phase 1: Context Collection

### 1.1 Detect Project Root

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$PROJECT_ROOT" ]; then
  echo "ERROR: Not in a git repo"
fi
```

### 1.2 Find Design Doc

```bash
setopt +o nomatch 2>/dev/null || true
SLUG=$(~/.claude/skills/gstack/bin/gstack-slug 2>/dev/null | grep -oP '(?<=SLUG=).*' || basename "$PROJECT_ROOT")
BRANCH=$(git branch --show-current 2>/dev/null | tr '/' '-' || echo 'no-branch')
DESIGN=$(ls -t ~/.gstack/projects/$SLUG/*-design-*.md 2>/dev/null | head -1)
if [ -n "$DESIGN" ]; then
  echo "DESIGN_DOC: $DESIGN"
else
  echo "NO_DESIGN_DOC"
fi
```

Read the design doc if found.

### 1.3 Find Eng Review Output

```bash
ENG_TEST_PLAN=$(ls -t ~/.gstack/projects/$SLUG/*-eng-review-test-plan-*.md 2>/dev/null | head -1)
CEO_PLAN=$(ls -t ~/.gstack/projects/$SLUG/ceo-plans/*.md 2>/dev/null | head -1)
if [ -n "$ENG_TEST_PLAN" ]; then echo "ENG_REVIEW: $ENG_TEST_PLAN"; fi
if [ -n "$CEO_PLAN" ]; then echo "CEO_PLAN: $CEO_PLAN"; fi
```

Read eng review test plan and CEO plan if found — they contain scope and feature details.

### 1.4 Scan Existing API Patterns

Scan the project for existing API conventions:

```bash
# Detect backend framework and API patterns
find "$PROJECT_ROOT" -type f \( -name "*.controller.*" -o -name "*Controller*" -o -name "*router*" -o -name "*routes*" -o -name "*handler*" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/vendor/*" | head -20

# Detect existing API docs
ls "$PROJECT_ROOT"/{swagger,openapi,api-doc}*.{json,yaml,yml} 2>/dev/null

# Detect database models / schema
find "$PROJECT_ROOT" -type f \( -name "*model*" -o -name "*entity*" -o -name "*schema*" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/vendor/*" | head -20
```

From existing code, extract:
- URL naming convention (camelCase? kebab-case? snake_case?)
- Response wrapper format ({ code, data, message }? { status, body }?)
- Authentication method (Bearer token? Cookie? API key?)
- Pagination style (page/size? offset/limit? cursor?)
- Error response structure

### 1.5 Check Existing api-contract Files

```bash
if [ -f "$PROJECT_ROOT/api-contract.md" ]; then
  echo "EXISTING_CONTRACT: $PROJECT_ROOT/api-contract.md"
fi
if [ -f "$PROJECT_ROOT/api-contract.yaml" ]; then
  echo "EXISTING_OPENAPI: $PROJECT_ROOT/api-contract.yaml"
fi
```

If existing contracts found, ask:
> Found existing api-contract files. What do you want to do?
> - A) Update — add new interfaces, keep existing ones
> - B) Regenerate — overwrite everything
> - C) Cancel — I'll handle it manually

### Phase 1 Output

Store for subsequent phases:
- `PROJECT_ROOT`: absolute path
- `DESIGN_DOC`: design doc content or empty
- `ENG_REVIEW`: eng review content or empty
- `EXISTING_PATTERNS`: extracted conventions from existing code
- `EXISTING_CONTRACT`: existing contract content or empty

---

## Phase 2: Infer Interfaces

### 2.1 Identify Business Entities

From design doc and eng review, identify the core business entities:
- What resources does the system manage? (orders, users, products...)
- What relationships exist between entities?
- What actions can users perform on each entity?

### 2.2 Generate Interface List

For each entity, infer the standard interfaces:

| Action | Method | Path | Can Infer? |
|--------|--------|------|------------|
| List | GET | /api/{entities} | ✅ from entity name |
| Detail | GET | /api/{entities}/:id | ✅ from entity name |
| Create | POST | /api/{entities} | ✅ from entity name |
| Update | PUT/PATCH | /api/{entities}/:id | ✅ from entity name |
| Delete | DELETE | /api/{entities}/:id | ⚠️ soft vs hard delete |
| Custom actions | varies | varies | ❌ must ask |

### 2.3 Classify What to Ask vs What to Infer

**Auto-infer (don't ask):**
- Field types from database schema or model definitions
- Standard CRUD endpoints from entity names
- Response wrapper from existing patterns
- Pagination parameters from existing patterns
- Basic request/response structure

**Must ask (show with suggested options):**
- Business enum values (status types, user roles, etc.)
- Delete behavior (soft delete with status change? hard delete?)
- Permission / role requirements per endpoint
- Non-standard operations (batch update, import/export, approval flow)
- File upload endpoints
- Search/filter parameters beyond basic keyword

### 2.4 Prepare Questions

Group questions by entity/topic. For each question:
- State what was inferred (show your reasoning)
- Ask only the uncertain part
- Provide 2-4 suggested options

Example question format:
> **Order management** — I inferred these endpoints:
> - GET /api/orders (list)
> - GET /api/orders/:id (detail)
> - POST /api/orders (create)
> - PUT /api/orders/:id (update)
> - DELETE /api/orders/:id (delete)
>
> Questions:
> 1. Order status values — which ones?
>    - A) pending, paid, shipped, completed, cancelled (recommended)
>    - B) draft, submitted, approved, processing, done
>    - C) Custom (tell me)
>
> 2. Delete behavior?
>    - A) Soft delete — set status to cancelled (recommended)
>    - B) Hard delete — remove from database

---

## Phase 3: Interactive Confirmation

### 3.1 Present Global Conventions First

Show inferred global conventions and confirm:

```
Global conventions (auto-detected from existing code):

Response format: { code: number, data: any, message: string }
Auth: Bearer token in Authorization header
Pagination: page + size, returns { list, total }
Error codes: 400/401/403/404/500

Correct? Or adjust any item.
```

### 3.2 Entity-by-Entity Confirmation

For each business entity, present:

1. **Inferred endpoints** — show the full list, user confirms or removes
2. **Unresolved questions** — only the things AI couldn't infer, with options
3. **Fields review** — show the request/response fields inferred from models, user confirms

Use AskUserQuestion for each entity. One entity per question (not one field per question).

If user says "looks good" for an entity, mark it confirmed and move on.

### 3.3 Skip Simple Entities

If an entity only needs basic CRUD and all fields are inferable, auto-confirm without asking:
> Entity "Category" — basic CRUD, fields all from schema. Auto-confirmed. ✅

### Phase 3 Output

- `CONFIRMED_ENTITIES`: list of entities with confirmed endpoints and fields
- `GLOBAL_CONVENTIONS`: confirmed response format, auth, pagination, errors

---

## Phase 4: Generate Output

### 4.1 Generate api-contract.md

Write to `$PROJECT_ROOT/api-contract.md`:

```markdown
# API Contract

Generated by /api-design on {date}
Branch: {branch}
Status: DRAFT → APPROVED after user confirmation

## Global Conventions

- Base URL: /api
- Auth: Bearer token in Authorization header
- Response: { code: number, data: any, message: string }
- Pagination: page (default 1) + size (default 20) → { list: T[], total: number }
- Errors: 400 参数错误 / 401 未登录 / 403 无权限 / 404 未找到 / 500 服务错误

---

## {Entity Name}

### GET /api/{entities}
{Description}

Query params:
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| page | number | no | Page number, default 1 |
| size | number | no | Page size, default 20 |
| keyword | string | no | Search keyword |
| ... | ... | ... | ... |

Response 200:
```json
{
  "code": 0,
  "data": {
    "list": [{ "id": "string", ... }],
    "total": 0
  }
}
```

### POST /api/{entities}
{Description}

Request:
```json
{
  "field1": "type (required/optional) — description",
  "field2": "type (required/optional) — description"
}
```

Response 200:
```json
{
  "code": 0,
  "data": { "id": "string", ... }
}
```

Errors:
- 400 → { code: 400, message: "具体错误信息" }

---

(Repeat for each endpoint)
```

### 4.2 Generate api-contract.yaml

Write OpenAPI 3.0 spec to `$PROJECT_ROOT/api-contract.yaml`:

```yaml
openapi: "3.0.3"
info:
  title: "{Project Name} API"
  version: "1.0.0"
  description: "Generated by /api-design"

servers:
  - url: /api

security:
  - BearerAuth: []

components:
  securitySchemes:
    BearerAuth:
      type: http
      scheme: bearer

  schemas:
    # Auto-generated from entity fields
    {EntityName}:
      type: object
      properties:
        id:
          type: string
        # ...

    # Standard response wrappers
    Response[T]:
      type: object
      properties:
        code:
          type: integer
        data:
          $ref: "#/components/schemas/{T}"
        message:
          type: string

    PaginatedResponse[T]:
      type: object
      properties:
        code:
          type: integer
        data:
          type: object
          properties:
            list:
              type: array
              items:
                $ref: "#/components/schemas/{T}"
            total:
              type: integer

paths:
  /{entities}:
    get:
      summary: "List {entities}"
      parameters:
        - name: page
          in: query
          schema:
            type: integer
            default: 1
        - name: size
          in: query
          schema:
            type: integer
            default: 20
      responses:
        "200":
          description: "Success"
          # ...

    post:
      summary: "Create {entity}"
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/Create{EntityName}"
      responses:
        "200":
          description: "Success"
          # ...

  /{entities}/{id}:
    get:
      summary: "Get {entity} detail"
      # ...

    put:
      summary: "Update {entity}"
      # ...

    delete:
      summary: "Delete {entity}"
      # ...
```

### 4.3 Self-Check Against Consistency Rules (MANDATORY — DO NOT SKIP)

**STOP. Before presenting to the user, you MUST execute these checks. Skipping this step is a critical bug.**

Read both output files. Then output a checklist with PASS/FAIL for each rule:

```
Self-Check Results:
[ ] 1. Pagination: ALL list GET endpoints return { list, total } with page+size params
[ ] 2. DELETE body: No DELETE endpoint has requestBody
[ ] 3. YAML schemas: Every response has a full schema (no bare description)
[ ] 4. Security: security: is declared in YAML
[ ] 5. md-yaml consistency: Field names, enums, paths match
```

**How to check rule 1 (pagination):** Use grep to find every GET endpoint in the md file that returns `"data": [` (bare array). This means pagination is missing. It MUST be `"data": { "list": [` and `"total":`.

```bash
# Check for bare arrays in md (violations = missing pagination)
grep -n '"data": \[' "$PROJECT_ROOT/api-contract.md"
# Any match = VIOLATION. Fix before proceeding.

# Check for bare arrays in yaml (violations = missing pagination)
grep -n 'type: array' "$PROJECT_ROOT/api-contract.yaml" | grep -v 'items:' | head -5
# If data is type: array directly under a response (not under list:), that's a VIOLATION.
```

**How to check rule 2 (DELETE body):**
```bash
grep -B2 "requestBody" "$PROJECT_ROOT/api-contract.yaml" | grep -i delete
# Any match = VIOLATION.
```

**How to check rule 3 (schema completeness):**
```bash
grep -c '"description":' "$PROJECT_ROOT/api-contract.yaml"
grep -c 'schema:' "$PROJECT_ROOT/api-contract.yaml"
# Every response must have both. Spot-check visually.
```

**How to check rule 4 (security):**
```bash
head -15 "$PROJECT_ROOT/api-contract.yaml" | grep "security:"
# Must be present.
```

If ANY check shows FAIL, fix the files immediately and re-run ALL checks. Do NOT proceed to 4.4 until all checks PASS. Present the PASS checklist to the user alongside the files.

### 4.4 Validate YAML

```bash
if command -v npx >/dev/null 2>&1; then
  npx --yes @redocly/cli lint "$PROJECT_ROOT/api-contract.yaml" 2>&1 | head -20 || true
fi
```

If validation fails, fix the YAML before presenting to user.

### 4.5 Present for Final Approval

Show the generated files to the user:

> Generated:
> - `api-contract.md` — human-readable API contract
> - `api-contract.yaml` — OpenAPI 3.0 spec (machine-readable)
>
> Options:
> - A) Approve — both files look good
> - B) Revise — something needs changing (tell me what)
> - C) Regenerate — start over

If A: mark Status as APPROVED in both files, commit.

If B: make the requested changes, re-present.

If C: return to Phase 2.

### 4.5 Commit

```bash
cd "$PROJECT_ROOT"
git add api-contract.md api-contract.yaml
git commit -m "docs: add API contract generated by /api-design"
```

---

## Downstream Consumers

This skill produces files consumed by:

| Consumer | File | How |
|----------|------|-----|
| `/flow-extract` | api-contract.md | Read interface semantics to generate interaction flows |
| `/write-plan` or subagent-develop | api-contract.yaml | Generate TypeScript types and API client code |
| Playwright test generation | api-contract.yaml | Generate mock data for test scenarios |

Each downstream skill should:
1. Check for `api-contract.md` / `api-contract.yaml` in project root
2. If found, read and use as constraint
3. If not found, suggest running `/api-design` first

---

## Important Rules

- **Only ask what you can't infer.** Never ask about things detectable from code.
- **Always show your reasoning.** When presenting inferred interfaces, briefly state what you based the inference on.
- **One entity per question.** Don't batch multiple entities into one AskUserQuestion.
- **Simple entities auto-confirm.** Basic CRUD with all fields inferable → skip asking.
- **Never modify existing code.** This skill only produces documentation files.
- **YAML must validate.** Always run OpenAPI lint before presenting.

### Consistency Rules

These rules are MANDATORY. Violating any of them is a bug in the skill output.

1. **All list endpoints use pagination.** Every `GET` that returns multiple items must return `{ list: T[], total: number }` with `page` + `size` query params. No exceptions — even if the entity is small (templates, categories), use the same paginated format for consistency. Downstream code generation depends on this uniformity.

2. **Never use request body with DELETE.** Some HTTP clients and proxies strip body from DELETE requests. Instead of `DELETE` with a JSON body, use `POST /api/{entities}/batch-delete` or `POST /api/{entities}/clear` with the body. Keep simple single-resource `DELETE /api/{entities}/:id` without body.

3. **YAML must have complete response schemas.** Every response in the YAML must include the full schema with all fields — no shortcuts like `"200": description: "成功"` without a schema. Downstream tools (Orval, openapi-typescript) need complete schemas to generate TypeScript types. If the md file has example JSON, the YAML must have the matching schema.

4. **YAML must declare security.** Even if the project has no auth (MVP / localhost-only), explicitly declare it:
   ```yaml
   security: []  # No auth required (MVP)
   ```
   Or with auth:
   ```yaml
   security:
     - BearerAuth: []
   ```
   This makes it clear and easy to enable auth later without restructuring.

5. **Naming must be consistent across md and yaml.** Field names, enum values, endpoint paths in api-contract.md must exactly match api-contract.yaml. No discrepancies.
