---
name: spec-verify
description: 规格一致性验证 — 检查前端代码是否与 api-contract.yaml 和 flows.md 一致，输出结构化 PASS/FAIL 结果
---

# Spec Verify Skill

检查前端代码是否遵循 API 契约和交互流程设计。由 spec-dev 自动调用，也可手动触发。

## When to Apply

- 由 spec-dev 在开发完成后自动调用
- 用户手动运行 `/spec-verify`
- 用户问"检查代码是否跟设计文档一致"

Do NOT apply when:
- 项目缺少 api-contract.yaml 或 flows.md（无法验证）

## Trigger

```
/spec-verify
```

---

## Phase 1: 检测上下文

### 1.1 检测项目根目录

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$PROJECT_ROOT" ]; then
  echo "ERROR: Not in a git repo"
  exit 1
fi
```

### 1.2 确认契约文档存在

```bash
ls "$PROJECT_ROOT/api-contract.yaml" "$PROJECT_ROOT/flows.md" "$PROJECT_ROOT/DESIGN.md" 2>&1
```

缺失任何一个 → 报告无法验证，建议先运行对应 skill。

### 1.3 识别已修改的前端文件

```bash
cd "$PROJECT_ROOT"
# 优先检查 git diff 中的文件
git diff --name-only HEAD | grep -E '\.(tsx?|jsx?|css)$' | grep -v node_modules

# 如果没有 git diff，检查所有前端源文件
if [ $? -ne 0 ]; then
  find "$PROJECT_ROOT" \( -name "*.tsx" -o -name "*.ts" -o -name "*.jsx" \) \
    -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/dist/*"
fi
```

---

## Phase 2: 执行检查

### Check 1: API 路径一致性

**目标：** 前端代码中的 API 调用路径必须与 api-contract.yaml 一致。

**检查方法：**

从 api-contract.yaml 提取所有定义的路径和方法：
```bash
python3 -c "
import yaml
with open('$PROJECT_ROOT/api-contract.yaml') as f:
    spec = yaml.safe_load(f)
for path, methods in spec.get('paths', {}).items():
    for method in ['get', 'post', 'put', 'patch', 'delete']:
        if method in methods:
            print(f'{method.upper()} {path}')
" 2>/dev/null
```

从前端代码提取实际调用路径（按你的 HTTP 客户端调整 grep 模式）：
```bash
grep -rnE "(fetch|axios|client|api)\.(get|post|put|patch|delete)\(" \
  "$PROJECT_ROOT" --include="*.ts" --include="*.tsx" \
  | grep -v node_modules
```

**比对规则：**
- 每个前端调用路径必须在 api-contract.yaml 中存在
- 方法必须匹配（GET 不能调 POST）
- 动态参数归一化：代码中的 `/items/${id}` 对应契约的 `/items/{id}`

**输出：**
```
API 路径一致性:
✅ GET /api/items — 匹配
✅ POST /api/items — 匹配
❌ GET /api/item-summary — 未在契约中定义
```

### Check 2: API 参数一致性

**目标：** 前端传递的 query/body 参数必须与契约定义一致。

对每个 API 调用：
1. 从契约提取该端点的参数定义（query params + request body schema）
2. 扫描前端代码中传给该调用的参数对象
3. 比对参数名和类型

**重点检查：**
- 必填参数是否传递
- 参数名拼写（契约 `sort` vs 代码 `sort_by`）
- 参数类型匹配
- 契约里没有的额外参数（可能的 typo）

**输出：**
```
API 参数一致性:
✅ GET /api/items — 参数: page, size, status — 全部匹配
❌ GET /api/items — 代码传 sort_by，契约定义是 sort
```

### Check 3: flows.md [预期] 断言覆盖率

**目标：** flows.md 中每个页面的 [预期] 断言必须在对应页面代码中有实现。

**检查方法：**
1. 从 flows.md 提取每个 Flow 的页面和所有 `[预期]` 断言
2. 通过 Route 匹配找到对应前端文件
3. 逐条检查每条 [预期] 在代码中是否有对应实现

**匹配规则（语义检查，非精确字符串匹配）：**

| flows.md [预期] | 代码中应出现 |
|-----------------|-------------|
| "调用 GET /api/items (sort=deadline)" | `getItems({ sort: 'deadline' })` |
| "骨架屏" / "加载骨架屏" | skeleton 结构 / loading 占位 |
| "红色错误提示" | `var(--danger)` / error 样式 |
| "按 X 分组" | 代码逻辑按该字段分组 |
| "弹窗" | `<Modal` 或 `<dialog>` |
| "空状态" | 条件渲染的空状态组件 |
| "重试按钮" | "重试" button + onClick 重新请求 |

**输出：**
```
flows.md 断言覆盖率:
📄 列表页 (flows.md #10-35, 页面: ListPage.tsx)
✅ #1 并行加载数据
✅ #2 骨架屏
❌ #5 空状态文案 — 未找到空状态组件
...
总计: 9/10 通过, 1 未通过
```

### Check 4: CSS Token 合规

**目标：** 页面代码不得硬编码颜色，必须使用 CSS Token（`var(--xxx)`）。

```bash
grep -rnE "#[0-9a-fA-F]{3,6}|rgb\(|hsl\(|oklch\(" \
  "$PROJECT_ROOT" --include="*.tsx" --include="*.jsx" \
  | grep -v node_modules | grep -v "//\|/\*"
```

**注意：** 设计 token 定义组件（如 StatusPill）中硬编码颜色值是允许的（这些是 token 来源）；页面文件中不应硬编码。

**输出：**
```
CSS Token 合规:
✅ ListPage.tsx — 无硬编码颜色
⚠️ DetailPage.tsx:12 — oklch(...) 硬编码（建议提取为 token）
```

### Check 5: 禁止模式扫描

```bash
# 1. 浏览器原生弹窗
grep -rnE "\b(prompt|alert|confirm)\(" "$PROJECT_ROOT" --include="*.tsx" --include="*.jsx" | grep -v node_modules

# 2. 纯文字 loading
grep -rn "加载中\.\.\.\|loading\.\.\." "$PROJECT_ROOT" --include="*.tsx" | grep -v node_modules

# 3. 可能的伪造数据（取模构造假分组等）
grep -rnE "% [0-9]" "$PROJECT_ROOT" --include="*.tsx" | grep -v node_modules
```

**输出：**
```
禁止模式扫描:
✅ 无 prompt()/alert() 调用
❌ DetailPage.tsx:40 — 发现 prompt()，应用 Modal 替代
```

---

## Phase 3: 汇总结果

### 3.1 计算通过率

```
总检查项: N
通过: P
未通过: F
通过率: P/N * 100%
```

### 3.2 输出结构化结果

```json
{
  "status": "PASS" | "FAIL",
  "checks": {
    "api_paths": { "pass": N, "fail": N, "items": [...] },
    "api_params": { "pass": N, "fail": N, "items": [...] },
    "flow_assertions": { "pass": N, "fail": N, "items": [...] },
    "css_tokens": { "pass": N, "fail": N, "items": [...] },
    "forbidden_patterns": { "pass": N, "fail": N, "items": [...] }
  },
  "summary": "9/10 通过，1 项需修复"
}
```

### 3.3 判定

- **PASS:** 所有检查项 100% 通过
- **FAIL:** 任何检查项有未通过

### 3.4 返回给 spec-dev

- 被调用时：PASS → spec-dev 完成；FAIL → spec-dev 打回循环
- 手动调用：展示完整 PASS/FAIL 清单 + 每个 FAIL 的修复建议

---

## 重要规则

1. **语义匹配，不是字符串匹配。** "骨架屏"在代码中可以是任何 loading 占位结构。
2. **不检查第三方库代码。** 只检查项目源码，排除 node_modules / dist / .next。
3. **CSS Token 检查放宽对 token 定义组件的约束。** StatusPill 等可硬编码 oklch。
4. **动态路径参数归一化。** `/items/${id}` 匹配契约 `/items/{id}`。
5. **只检查变更范围。** 优先 git diff 文件；无 diff 时检查全部源码。
6. **输出必须包含文件路径和行号。** 方便定位修复。
7. **不自动修复。** 此 skill 只检查。修复由 spec-dev 打回循环处理。
