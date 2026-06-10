---
name: frontend-test
description: Automated frontend component testing with self-healing loop. Scans components, infers interaction specs, generates Vitest tests, auto-fixes failures in background. Supports React / Vue / Next.js. Use /frontend-test to trigger.
---

# Frontend Test Skill

Automated component-level frontend testing with self-healing loop.

## When to Apply

Apply this skill when the user:
- Runs `/frontend-test` or `/frontend-test <path>`
- Asks to test frontend components
- Asks to generate frontend tests
- Mentions frontend testing coverage

Do NOT apply when:
- User asks about backend/API tests
- User asks about E2E tests (Playwright, Cypress)
- User is only asking conceptual questions

## Trigger

```
/frontend-test                    # Scan entire src/
/frontend-test src/components/    # Scan specific directory
/frontend-test src/components/Table.tsx  # Test specific component
```

No argument defaults to scanning `src/` in the project root.

---

## Phase 1: Environment Check

Before any testing, verify the project is ready.

### 1.1 Detect Project Root

Find the nearest `package.json` by checking the target path and walking up.

```bash
cat package.json | head -5
```

If no `package.json` found, report:

> ⚠️ No package.json found. Are you in a frontend project directory?

And STOP.

### 1.2 Detect Framework

Read `package.json` dependencies to determine framework:

```bash
cat package.json | grep -E '"react"|"vue"|"next"|"nuxt"'
```

| Detected Dependency | Framework Mode |
|---------------------|---------------|
| `next` | nextjs (use React testing tools) |
| `react` | react |
| `vue` or `nuxt` | vue |
| None found | Report error and STOP |

### 1.3 Check Testing Dependencies

Based on detected framework, verify testing dependencies:

**React / Next.js:**
```bash
cat package.json | grep -E '"vitest"|"@testing-library/react"|"@testing-library/jest-dom"|"jsdom"'
```

**Vue:**
```bash
cat package.json | grep -E '"vitest"|"@vue/test-utils"|"jsdom"|"happy-dom"'
```

If missing, print install instructions and STOP:

**React / Next.js:**
```
⚠️ Missing testing dependencies. Install them first:

npm install -D vitest @testing-library/react @testing-library/jest-dom @testing-library/user-event jsdom @vitejs/plugin-react

Then create vitest.config.ts with jsdom environment.
```

**Vue:**
```
⚠️ Missing testing dependencies. Install them first:

npm install -D vitest @vue/test-utils jsdom @vitejs/plugin-vue

Then create vitest.config.ts with jsdom environment.
```

### 1.4 Verify Vitest Works

```bash
npx vitest run --reporter=verbose 2>&1 | head -20
```

If this fails with a config error, report the error and STOP.
If no tests exist yet, that's OK — proceed to Phase 2.

### Phase 1 Output

Store these for subsequent phases:

- `FRAMEWORK`: "react" | "vue" | "nextjs"
- `PROJECT_ROOT`: absolute path to project root
- `SRC_DIR`: absolute path to target directory (user-specified or `src/`)

---

## Phase 2: Component Scan & Spec Inference

### 2.1 Discover Components

Scan for component files based on `FRAMEWORK`:

**React / Next.js:**
```bash
find $SRC_DIR -name "*.tsx" -o -name "*.jsx" | grep -v ".test." | grep -v ".spec." | grep -v ".stories." | sort
```

**Vue:**
```bash
find $SRC_DIR -name "*.vue" | grep -v ".test." | grep -v ".spec." | sort
```

Store the list as `COMPONENTS`.

If no components found, report:

> ⚠️ No components found in `$SRC_DIR`. Check the path.

And STOP.

### 2.2 Sort by Dependency Depth

For each component, count how many other local components it imports. This determines testing order — leaf components first, pages last.

```bash
# For each component file, count local imports from the project
for f in $COMPONENTS; do
  local_imports=$(grep -cE "from ['\"].*(components|src)" "$f" 2>/dev/null || echo 0)
  echo "$local_imports $f"
done | sort -n
```

Sort ascending by local import count:
- **0 imports** → leaf component (Button, Input, Badge...) — test first
- **1-3 imports** → composite component (Form, Table, Card...) — test second
- **4+ imports** → page component (Page, Layout...) — test last

Store the sorted list as `SORTED_COMPONENTS`.

### 2.3 Infer Interaction Specs

For each component in `SORTED_COMPONENTS`, read the source code and extract interaction specs.

**State detection:**
- `useState` / `useReducer` / `ref()` / `reactive()` → infer state variables, guess meaning from names (e.g. `isLoading` → loading state)
- Ternary operators and `&&` short-circuits with JSX → conditional rendering branches
- `v-if` / `v-show` directives → conditional rendering
- Variables named `isLoading`, `isError`, `error`, `status` → async state pattern (loading / error / success)

**Event detection:**
- `onClick`, `onSubmit`, `onChange`, `@click`, `@submit`, `@change`, `emit(` → user interactions
- For each handler: trace what it does (API call? state change? navigation?)

**Data flow detection:**
- `props` / `defineProps` → required vs optional props
- `.map()` / `v-for` → list rendering with empty state possibility
- `fetch` / `axios` / `useQuery` / `useMutation` → async operations with loading/error/success

**Form detection:**
- `<form` / `<input` / `<select` / `<textarea` → form behavior
- `validate` / `required` / `pattern` / `rules` → validation rules

### 2.4 Present Specs for User Review

After analyzing all components, present the inferred specs:

```
📋 Inferred Interaction Specs

## ComponentName (src/path/to/Component.tsx)
Priority: leaf | composite | page

### States
- loading: <inferred behavior>
- error: <inferred behavior>
- empty: <inferred behavior>

### User Interactions
- <interaction description>

### ❓ Needs Confirmation
- <ambiguity or missing info>

---
```

Use AskUserQuestion to present the specs and wait for user response:

> I've analyzed N components and inferred their interaction specs.
> 
> <specs summary>
> 
> Options:
> - A) All good, proceed with testing
> - B) I want to adjust some specs (tell me which ones)
> - C) Add additional specs (tell me for which components)

Wait for user response before proceeding to Phase 3.

### Phase 2 Output

- `SORTED_COMPONENTS`: ordered list of component file paths
- `SPECS`: mapping of component path → inferred interaction spec
- User confirmation received

---

## Phase 3: Parallel Test Loop

### 3.1 Create Isolation Branch

All changes happen on a separate branch. The main branch is never touched.

```bash
BRANCH_NAME="test-auto-fix/$(date +%Y%m%d-%H%M%S)"
git checkout -b "$BRANCH_NAME"
echo "🌿 Created isolation branch: $BRANCH_NAME"
```

### 3.2 Boundaries

| Boundary | Value |
|----------|-------|
| Max fix rounds per component | 3 |
| Total time limit | 30 minutes |
| Max concurrent subagents | 3 |
| Start time | current timestamp |

### 3.3 Dispatch Subagents

Process `SORTED_COMPONENTS` in batches of 3 (max concurrent subagents). For each component, dispatch a subagent (via TaskCreate) with the following prompt template:

---

**Subagent Prompt Template:**

You are a frontend test engineer. Write tests for one component and fix any issues found.

**Component:** `<component_path>`
**Framework:** `{{FRAMEWORK}}`
**Interaction Spec:**
```
{{component's inferred spec from SPECS}}
```

**Your workflow:**

**Step 1: Read the component and its dependencies.**
Read `<component_path>` and all imported child components/utilities to understand the full picture.

**Step 2: Generate test file.**

Create test file at: `<component_dir>/__tests__/<component_name>.spec.<ext>`
(ext is `.tsx` for React/Next.js, `.ts` for Vue)

The test file must cover these dimensions (use the interaction spec as guide):

```typescript
describe('ComponentName', () => {
  describe('Rendering', () => {
    // Render without crash
    // Render with required props
    // Apply className/style
  })

  describe('States', () => {
    // For each state from spec: loading, error, empty, success
    // Assert correct DOM output for each state
    // Use DOM assertions (getByText, getByRole, getByTestId)
  })

  describe('Interactions', () => {
    // For each user interaction from spec
    // Simulate the event (fireEvent.click, userEvent.type, etc.)
    // Assert the outcome (callback called, DOM updated, navigation happened)
  })

  describe('Edge Cases', () => {
    // null/undefined data
    // empty arrays
    // concurrent operations
  })
})
```

**Framework-specific imports:**

React / Next.js:
```typescript
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, it, expect, vi, beforeEach } from 'vitest'
```

Vue:
```typescript
import { mount, shallowMount } from '@vue/test-utils'
import { describe, it, expect, vi, beforeEach } from 'vitest'
```

**Mocking rules:**
- Mock external API calls (fetch, axios) with `vi.fn()` or MSW
- Mock child components ONLY if they have complex side effects (API calls, routing)
- Use real component for simple presentational children
- Mock router/navigation: `vi.mock('next/navigation', ...)` or `vi.mock('vue-router', ...)`
- For Zustand stores: set test state via `useStore.setState({...})`
- For Pinia stores: set test state via `useStore.$patch({...})`

**Step 3: Run the test.**
```bash
npx vitest run <test_file_path> --reporter=verbose
```

**Step 4: If PASS → report SUCCESS.** Include test summary (how many passed).

**Step 5: If FAIL → fix and retry (up to 3 rounds total).**

Read the error output carefully. Classify the failure:

| Failure Type | Indicators | Action |
|-------------|-----------|--------|
| Test bug | Wrong selector, missing mock, incorrect assertion | Fix the TEST file |
| Source bug | Null access, missing guard, wrong logic | Fix the SOURCE file |

After each fix, re-run: `npx vitest run <test_file_path> --reporter=verbose`

**Step 6: After 3 rounds still failing:**

Write a `test-fixes.log` file next to the test:
```
Round 1: <error summary> → <fix attempted>
Round 2: <error summary> → <fix attempted>
Round 3: <error summary> → gave up
```

Report FAILURE with:
- All error messages from each round
- What was tried in each round
- Suggested fix for a human engineer

**IMPORTANT RULES:**
- Do NOT modify any file outside this component's directory
- Do NOT install new packages or modify package.json / config files
- All source code fixes must be minimal and targeted
- Log every change you make (what file, what line, what changed)

---

### 3.4 Collect Results

After all subagents complete (or time limit reached), collect results into an array:

For each component, record:
- `status`: "passed" | "failed" | "skipped" | "timeout"
- `rounds`: number of fix rounds attempted
- `test_file`: path to generated test
- `fixes_log`: path to fixes log (if any)
- `error_summary`: last error message (if failed)
- `suggestions`: fix suggestions for human (if failed)

### 3.5 Handle Time Limit

Before dispatching each new batch, check elapsed time:

```bash
ELAPSED=$(( $(date +%s) - START_TIME ))
if [ $ELAPSED -gt 1800 ]; then
  echo "⏱️ Time limit reached (30 minutes). Stopping."
  break
fi
```

Any components not yet processed are marked as "skipped" with reason "time limit".

### Phase 3 Output

- `RESULTS`: array of component test results
- All test files written to component `__tests__/` directories
- Source code fixes applied on isolation branch only
- Branch has uncommitted changes ready for Phase 5 commit

---

## Phase 4: Screenshot Review (Failed Components Only)

### 4.1 Check gstack browse Availability

```bash
B="$HOME/.claude/skills/gstack/browse/dist/browse"
if [ -x "$B" ]; then
  echo "BROWSE_READY=true"
else
  echo "BROWSE_READY=false"
fi
```

If `BROWSE_READY=false`, skip this phase and note in report: "Screenshot skipped: gstack browse not available."

### 4.2 Start Dev Server

```bash
cd $PROJECT_ROOT
npm run dev &
DEV_PID=$!
sleep 5  # Wait for server to start
```

If dev server fails to start, skip screenshots and note in report.

### 4.3 Screenshot Failed Components

For each failed component, attempt to capture a screenshot:

```bash
# Navigate to dev server
$B goto "http://localhost:5173"  # or detected port from dev server output

# Take a snapshot to see what's on screen
$B snapshot -i -c

# If the component is reachable via a route, navigate there
# Otherwise, note "component not routable" in report

# Take screenshot
mkdir -p $PROJECT_ROOT/__test-screenshots
$B screenshot "$PROJECT_ROOT/__test-screenshots/<component_name>-failure.png"
```

For leaf components that don't have their own route, note in report:
> Component `<name>` is not directly routable. Screenshot skipped.

### 4.4 Cleanup

```bash
kill $DEV_PID 2>/dev/null || true
```

---

## Phase 5: Report Output

### 5.1 Commit Results

Before generating report, commit all changes on the isolation branch:

```bash
git add -A
git commit -m "test: auto-generated frontend tests $(date +%Y%m%d-%H%M%S)"
```

### 5.2 Generate Report

Create `$PROJECT_ROOT/FRONTEND_TEST_REPORT.md`:

```markdown
# 🧪 Frontend Test Report

## 概览
- 总计: <total> 组件
- ✅ 通过: <passed>
- ❌ 失败: <failed>
- ⏭️ 跳过: <skipped>
- ⏱️ 耗时: <duration>
- 🌿 分支: <branch_name>

## ✅ 通过的组件
<comma-separated list of passed component names>

## ❌ 失败的组件

### <ComponentName> (<rounds>/3 轮用尽)
**测试文件:** <test_file_path>
**截图:** <screenshot_path or "不可用">

- 轮次 1: <error_summary> → <fix_attempted>
- 轮次 2: <error_summary> → <fix_attempted>
- 轮次 3: <final_error>

**修复建议（可交给 Claude Code）:**
> <suggested_fix_description>

---

## ⏭️ 跳过的组件
<list of skipped components with reason>

## 📊 Git Diff
<output of `git diff main --stat`>
```

### 5.3 Print Summary to Terminal

Output a concise summary for quick scanning:

```
🧪 Frontend Test Complete

✅ <passed> passed | ❌ <failed> failed | ⏭️ <skipped> skipped
⏱️ <duration> | 🌿 branch: <branch_name>

❌ Failed:
  - <ComponentName> (<rounds> rounds): <error_summary> → see report

📄 Full report: FRONTEND_TEST_REPORT.md
📊 Diff: git diff main --stat
```

### 5.4 Branch Handling Guide

End the report with user instructions:

```
🔧 后续操作:
- git merge <branch_name>           → 采纳所有修改
- git cherry-pick <commit_hash>     → 选择性采纳
- git checkout main && git branch -D <branch_name>  → 丢弃所有修改
```

**DONE — Skill execution complete.**
