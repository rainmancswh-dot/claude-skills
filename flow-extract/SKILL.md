---
name: flow-extract
description: Generate frontend interaction flow descriptions from API contract and design docs. Reads api-contract.md, infers pages and flows, asks only unclear questions. Outputs flows.md to project root.
---

# Flow Extract Skill

Generate frontend interaction flow descriptions from API contract.

## When to Apply

Apply this skill when the user:
- Runs `/flow-extract`
- Asks to define frontend interaction flows for a project
- Needs flow documentation before frontend development

Do NOT apply when:
- User asks about a specific UI bug or fix
- User is only asking conceptual questions

## Trigger

```
/flow-extract
```

## Prerequisites

This skill expects:
- An API contract from `/api-design` (`api-contract.md` in project root)
- A design doc from `/office-hours` (optional but recommended)
- An eng-review output from `/plan-eng-review` (optional)

If no api-contract.md found, STOP:
> ⚠️ No api-contract.md found. Run `/api-design` first.

If no design doc found, warn but continue:
> ⚠️ No design doc found. Proceeding based on API contract only.

---

## Phase 1: Context Collection

### 1.1 Detect Project Root

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$PROJECT_ROOT" ]; then
  echo "ERROR: Not in a git repo"
fi
```

### 1.2 Read CONTEXT.md (Recommended)

```bash
if [ -f "$PROJECT_ROOT/CONTEXT.md" ]; then
  echo "CONTEXT: $PROJECT_ROOT/CONTEXT.md"
else
  echo "NO_CONTEXT"
fi
```

If CONTEXT.md exists, read it and use its terminology for all page names, navigation labels, and user-visible text. Flow descriptions must use the canonical terms defined in CONTEXT.md.

If CONTEXT.md does not exist, warn:
> ⚠️ No CONTEXT.md found. Consider running /grill-with-docs to establish domain language.

### 1.3 Find API Contract (Required)

```bash
if [ -f "$PROJECT_ROOT/docs/api-contract.md" ]; then
  echo "API_CONTRACT: $PROJECT_ROOT/docs/api-contract.md"
else
  echo "NO_API_CONTRACT"
fi
```

If NO_API_CONTRACT, STOP and tell user to run `/api-design` first.

### 1.4 Find Design Doc (Optional)

```bash
setopt +o nomatch 2>/dev/null || true
SLUG=$(~/.claude/skills/gstack/bin/gstack-slug 2>/dev/null | grep -oP '(?<=SLUG=).*' || basename "$PROJECT_ROOT")
DESIGN=$(ls -t ~/.gstack/projects/$SLUG/*-design-*.md 2>/dev/null | head -1)
ENG_TEST_PLAN=$(ls -t ~/.gstack/projects/$SLUG/*-eng-review-test-plan-*.md 2>/dev/null | head -1)
```

Read design doc and eng review if found.

### 1.5 Find Existing Routes/Pages (Optional)

Scan the project for existing frontend routes:

```bash
# Detect frontend framework and routing
find "$PROJECT_ROOT" -type f \( -name "*.tsx" -o -name "*.vue" -o -name "*.jsx" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" | head -30

# Look for route definitions
grep -rn "route\|Route\|router\|useNavigate\|Link to" \
  "$PROJECT_ROOT/src" 2>/dev/null | grep -v node_modules | head -20

# Look for page components
find "$PROJECT_ROOT/src" -type d \( -name "pages" -o -name "views" -o -name "routes" \) \
  -not -path "*/node_modules/*" 2>/dev/null
```

If routes found, extract existing page list for reference.

### 1.6 Check Existing flows.md

```bash
if [ -f "$PROJECT_ROOT/docs/flows.md" ]; then
  echo "EXISTING_FLOWS: $PROJECT_ROOT/docs/flows.md"
fi
```

If existing flows.md found, ask:
> Found existing flows.md. What do you want to do?
> - A) Update — add new flows, keep existing ones
> - B) Regenerate — overwrite everything
> - C) Cancel — I'll handle it manually

### Phase 1 Output

Store for subsequent phases:
- `PROJECT_ROOT`: absolute path
- `CONTEXT`: CONTEXT.md content or empty (canonical terminology)
- `API_CONTRACT`: api-contract.md content (required)
- `DESIGN_DOC`: design doc content or empty
- `ENG_REVIEW`: eng review content or empty
- `EXISTING_ROUTES`: list of detected routes/pages or empty
- `EXISTING_FLOWS`: existing flows.md content or empty

---

## Phase 2: Infer Pages and Flows

### 2.1 Extract Business Entities from API Contract

From api-contract.md, extract all business entities and their endpoints.

For the Orbit example, this would yield:
- FlowTemplate (CRUD + nodes + actions)
- Project (CRUD + progress)
- Deliverable (upload/download/delete)
- Review (approve/reject)
- Dashboard (overview)
- AuditLog (view)
- FrontendError (report/view/clear)

### 2.2 Map Entities to Pages

For each entity or entity group, infer the corresponding frontend page(s):

| Entity Pattern | Pages Inferred |
|----------------|----------------|
| Entity with list + CRUD | List page + Detail/Edit page |
| Entity with nested resources | List + Detail with tabs |
| Dashboard / overview | Single dashboard page |
| Log / audit | Read-only list page |
| Error tracking | List page with actions |

**Page naming convention**: Use entity names in plural for lists, singular for detail.
- `/templates` — template list
- `/templates/:id` — template detail (edit nodes/actions)
- `/projects` — project list
- `/projects/:id` — project detail

### 2.3 Identify Navigation Structure

Infer sidebar/nav structure from pages:
- Group related pages under sections
- Determine entry points (sidebar links, direct URLs, redirects)

### 2.4 Generate Draft Flow for Each Page

For each page, draft a flow based on:
1. What APIs the page calls
2. What user actions are available
3. What state transitions occur
4. What navigation happens

**Auto-infer (don't ask):**
- Page entry point from route structure
- Data loading flow from GET endpoints
- Form submission flow from POST/PUT endpoints
- Delete confirmation pattern
- List with pagination and filtering
- Navigation between related pages

**Must ask (show with suggested options):**
- Page layout preferences (table vs card, sidebar vs tabs)
- Workflow order — which page is the "home" / landing page
- Complex multi-step interactions not obvious from API
- Pages that share a route (tabs vs separate pages)
- Priority — which pages to build first
- Non-obvious conditional logic (e.g., "upload only if dependencies approved")

### 2.5 Classify Pages by Complexity

| Complexity | Criteria | Action |
|------------|----------|--------|
| Simple | Read-only list or single API call | Auto-generate, batch confirm |
| Medium | CRUD with standard patterns | Generate with brief confirmation |
| Complex | Multi-step workflow, conditional logic, multiple API calls | Ask detailed questions |

---

## Phase 3: Interactive Confirmation

### 3.1 Present Page List First

Show the inferred page structure:

```
Inferred pages from API contract:

1. Dashboard (/) — 全局概览
2. Template List (/templates) — 模板列表
3. Template Detail (/templates/:id) — 模板编辑（节点/动作）
4. Project List (/projects) — 项目列表
5. Project Detail (/projects/:id) — 项目详情（节点/交付物/审核）
6. Audit Log (/audit-log) — 操作日志
7. Frontend Errors (/errors) — 前端错误

Navigation: 侧边栏导航，Dashboard 为首页

Correct? Or adjust (add/remove pages, rename, reorder).
```

### 3.2 Page-by-Page Flow Confirmation

For each page, present the drafted flow and ask for confirmation or correction.

**Simple pages** (Dashboard, Audit Log, Error List): batch together:
> Pages 1, 6, 7 are simple read-only views. Drafted flows:
> - Dashboard: 加载概览数据 → 显示卡片和项目列表 → 点击项目跳转详情
> - Audit Log: 加载日志列表 → 支持筛选和分页
> - Errors: 加载错误列表 → 支持筛选 → 可清除已解决错误
>
> Look good?

**Medium pages** (Template List, Project List): one question per page:
> **Template List** — flow:
> 1. 加载模板列表（分页、按类型筛选）
> 2. 点击 "新建模板" → 弹窗填写名称和类型 → 创建成功刷新列表
> 3. 点击模板行 → 跳转模板详情
>
> Look good?

**Complex pages** (Template Detail, Project Detail): ask targeted questions:
> **Project Detail** — I inferred this flow:
> 1. 加载项目详情（含节点树和动作状态）
> 2. 显示进度条和当前节点
> 3. 展开节点 → 查看动作列表
> 4. 对 pending 动作：上传交付物 → 状态变为 submitted
> 5. 对 submitted 动作：审核（通过/驳回）
>
> Questions:
> 1. 节点如何展示？
>    - A) 树状步骤条（推荐）
>    - B) Tab 切换
>    - C) 可折叠列表
>
> 2. 审核入口在哪？
>    - A) 项目详情页内联操作（推荐）
>    - B) 独立审核页面
>    - C) 全局待审核列表中操作

### 3.3 Skip Simple Pages

If a page only has standard list/pagination and all interactions are obvious from the API, auto-confirm:
> Page "Audit Log" — standard read-only list with filtering. Auto-confirmed. ✅

### Phase 3 Output

- `CONFIRMED_PAGES`: list of pages with confirmed flows
- `NAVIGATION_STRUCTURE`: confirmed nav/sidebar structure
- `FLOW_DETAILS`: per-page operation flows with steps and assertions

---

## Phase 4: Generate Output

### 4.1 Generate flows.md

Write to `$PROJECT_ROOT/docs/flows.md`:

```markdown
# Frontend Interaction Flows — {Project Name}

Generated by /flow-extract on {date}
Branch: {branch}
Status: DRAFT → APPROVED after user confirmation

## Navigation Structure

```
Sidebar:
- 仪表盘 (/)
- 模板管理 (/templates)
- 项目管理 (/projects)
  - 项目详情 (/projects/:id)
- 操作日志 (/audit-log)
- 前端错误 (/errors)
```

---

## Flow: {Page Name}

- **Route**: `/{path}`
- **Entry**: 侧边栏 "{nav_label}" / 从 {source_page} 点击跳转
- **APIs**: {list of involved APIs}
- **Data-testid prefix**: `{prefix}-` (用于 Playwright 选择器)

### 操作流程

1. 进入页面 [预期] 调用 GET /api/{endpoint}，显示加载状态
   [预期] 数据返回后渲染 {what to render}
   [预期] 无数据时显示空状态（{empty_state_description}）

2. {操作名称} [预期] {前置条件}
   - 操作: {what user does}
   [预期] {what happens — API call, UI update, navigation}

3. ...

### 异常分支

- {异常场景1} [预期] {处理方式 — 错误提示/回退/重试}
- {异常场景2} [预期] {处理方式}

### 关联跳转

- → {目标页面}: {触发条件}
- ← {来源页面}: {返回条件}

---

(Repeat for each page)
```

### 4.2 Self-Check (MANDATORY — DO NOT SKIP)

**STOP. Before presenting to the user, execute these checks.**

Read the generated flows.md. Then output a checklist:

```
Self-Check Results:
[ ] 1. API coverage: Every endpoint in api-contract.md is referenced in at least one flow
[ ] 2. Route consistency: Route paths don't conflict or duplicate
[ ] 3. Flow completeness: Every flow has at least entry, operations, and error branches
[ ] 4. Assertion quality: Every step has at least one [预期] assertion
[ ] 5. Navigation consistency: All cross-page links reference valid routes
```

**How to check rule 1 (API coverage):**
```bash
# Extract all endpoints from api-contract.md
grep -oP '(GET|POST|PUT|PATCH|DELETE)\s+/api/[^\s]+' "$PROJECT_ROOT/docs/api-contract.md" | sort -u > /tmp/api_endpoints.txt

# Extract all API references from flows.md
grep -oP '(GET|POST|PUT|PATCH|DELETE)\s+/api/[^\s,)]+' "$PROJECT_ROOT/docs/flows.md" | sort -u > /tmp/flow_endpoints.txt

# Find uncovered endpoints
comm -23 /tmp/api_endpoints.txt /tmp/flow_endpoints.txt
# Any output = UNCOVERED endpoints. Fix before proceeding.
```

**How to check rule 2 (route consistency):**
```bash
# Extract routes from flows.md
grep -oP 'Route.*?`(/[^`]+)`' "$PROJECT_ROOT/docs/flows.md" | sort | uniq -d
# Any duplicate = VIOLATION.
```

**How to check rule 3 (flow completeness):**
```bash
# Every Flow section should have 操作流程 and 异常分支
for flow in $(grep -n "^## Flow:" "$PROJECT_ROOT/docs/flows.md"); do
  start=$(echo "$flow" | cut -d: -f1)
  section=$(sed -n "${start},\$p" "$PROJECT_ROOT/docs/flows.md" | head -50)
  echo "$section" | grep -q "### 操作流程" || echo "MISSING 操作流程 in flow at line $start"
  echo "$section" | grep -q "### 异常分支" || echo "MISSING 异常分支 in flow at line $start"
done
```

**How to check rule 4 (assertion quality):**
```bash
# Count [预期] per flow — should have at least 2
grep -c "\[预期\]" "$PROJECT_ROOT/docs/flows.md"
# If very low relative to number of flows, assertions are missing.
```

**How to check rule 5 (navigation consistency):**
```bash
# All referenced routes in 关联跳转 should exist in Route definitions
grep -oP '`/[^`]+`' "$PROJECT_ROOT/docs/flows.md" | sort -u
# Cross-check with Route: lines
grep -oP 'Route.*?`(/[^`]+)`' "$PROJECT_ROOT/docs/flows.md" | grep -oP '/[^`]+'
```

If ANY check shows FAIL, fix the file immediately and re-run ALL checks. Do NOT proceed to 4.3 until all checks PASS.

### 4.3 Present for Final Approval

Show the generated file to the user:

> Generated:
> - `flows.md` — frontend interaction flow descriptions
>
> Options:
> - A) Approve — looks good
> - B) Revise — something needs changing (tell me what)
> - C) Regenerate — start over

If A: mark Status as APPROVED, commit.

If B: make the requested changes, re-present.

If C: return to Phase 2.

### 4.4 Commit

```bash
cd "$PROJECT_ROOT"
git add docs/flows.md
git commit -m "docs: add frontend interaction flows generated by /flow-extract"
```

---

## Downstream Consumers

This skill produces files consumed by:

| Consumer | File | How |
|----------|------|-----|
| `/write-plan` | docs/flows.md | Break into implementation tasks per page/flow |
| subagent-develop | docs/flows.md + docs/api-contract.md | Generate frontend code with flow constraints |
| Playwright test generation | docs/flows.md + docs/api-contract.yaml | Generate E2E test scenarios from flow steps |
| `/frontend-test` | docs/flows.md | Generate component tests aligned with flow assertions |

Each downstream skill should:
1. Check for `flows.md` in project root
2. If found, read and use as constraint for frontend behavior
3. If not found, suggest running `/flow-extract` first

---

## Important Rules

- **Only ask what you can't infer.** Standard CRUD pages auto-generate.
- **Batch simple pages.** Don't ask one-by-one for read-only lists.
- **One page per question for complex pages.** Group questions by page.
- **Always show your reasoning.** State what was inferred and from what.
- **Never modify existing code.** This skill only produces documentation.
- **[预期] assertions are critical.** Every user action must have an expected outcome — these become Playwright assertions.
- **Data-testid prefix matters.** Each flow gets a prefix for stable Playwright selectors.

### Consistency Rules

These rules are MANDATORY. Violating any of them is a bug in the skill output.

1. **Every API endpoint must be covered.** If an endpoint exists in api-contract.md, it must appear in at least one flow. Uncovered endpoints mean missing pages or incomplete flows.

2. **Every flow must have error branches.** No happy-path-only flows. At minimum: API failure and empty state handling. These map directly to Playwright error scenario tests.

3. **[预期] assertions must be specific.** Not "shows data" but "renders 3 project cards with progress bars". Specific assertions make test generation deterministic.

4. **Navigation must be bidirectional.** If flow A links to flow B, flow B must reference flow A in its entry or 关联跳转 section. Orphan links are bugs.

5. **Route paths must be unique.** No two flows share the same route. Parameterized routes (e.g., `/projects/:id`) count as one route.
