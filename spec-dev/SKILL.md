---
name: spec-dev
description: 按规格文档驱动的开发入口 — 自动从 DESIGN.md / api-contract.yaml / flows.md 提取上下文注入子 agent，开发完成后自动验证一致性，不通过则自动打回重试（最多 3 次）
---

# Spec-Driven Dev Skill

任何已有规格文档项目的开发入口。自动从 DESIGN.md / api-contract.yaml / flows.md 中提取相关上下文，注入子 agent prompt，开发完成后验证一致性。

## When to Apply

- 项目已有 DESIGN.md、api-contract.yaml、flows.md，需要按这些规格开发功能
- 用户说"开发 XX 功能"、"实现 XX"、"写代码"
- 用户从 write-plan 拿到任务列表后

Do NOT apply when:
- 只讨论设计，不写代码
- 只改配置文件
- 项目缺少契约文档（应先跑 /api-design 和 /flow-extract）

## Trigger

```
/spec-dev
```

或用户说"按文档开发 XXX 功能"。

---

## Phase 1: 收集上下文

### 1.1 检测项目根目录

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$PROJECT_ROOT" ]; then
  echo "ERROR: Not in a git repo"
  exit 1
fi
```

### 1.2 读取规格文档（强制）

契约三件套缺一不可，缺失则 STOP：

```bash
# 1. 设计文档
[ -f "$PROJECT_ROOT/DESIGN.md" ] && echo "✅ DESIGN.md" || { echo "❌ DESIGN.md not found"; exit 1; }

# 2. API 契约（必需）
[ -f "$PROJECT_ROOT/api-contract.yaml" ] && echo "✅ api-contract.yaml" || { echo "❌ api-contract.yaml not found — run /api-design first"; exit 1; }

# 3. 交互流程（必需）
[ -f "$PROJECT_ROOT/flows.md" ] && echo "✅ flows.md" || { echo "❌ flows.md not found — run /flow-extract first"; exit 1; }
```

可选文档（存在则读取，不存在跳过）：

```bash
# 4. 样式设计 prompt（open-design / design-consultation 等工具产出）
[ -f "$PROJECT_ROOT/open-design-prompt.md" ] && echo "✅ open-design-prompt.md" || echo "⚠️ no style prompt (optional)"

# 5. 项目 CLAUDE.md
[ -f "$PROJECT_ROOT/CLAUDE.md" ] && echo "✅ CLAUDE.md" || echo "⚠️ no CLAUDE.md (optional)"
```

全部通过后，完整读取每个文件的内容。

### 1.3 理解任务

向用户确认开发任务：
- 如果是 write-plan 产出的任务列表：读取并确认
- 如果是用户口述：复述并确认理解

---

## Phase 2: 上下文切分

### 2.1 识别任务涉及的模块/页面

从任务描述中识别涉及的功能模块、页面、组件名称。

### 2.2 从 api-contract.yaml 切出相关端点

**通用方法**：用任务描述里的关键词（页面名、功能名、实体名）在 api-contract.yaml 中匹配相关端点。匹配维度：
- 路径片段（如任务提到 "task" → 匹配 `/tasks`、`/tasks/{id}` 等）
- OpenAPI `tags` / `summary` 描述
- request/response schema 里的实体名

提取每个匹配端点的**完整 schema**（path、method、query 参数、request body、response、错误码）。

**切分原则**：
- 多切不要少切 — 漏切会导致子 agent 编造接口
- 宁可带上相关端点让 agent 自己判断
- 不确定时，把同实体的 CRUD 端点一起切出

### 2.3 从 flows.md 切出相关断言

找到任务相关的 Flow 章节，提取所有 `[预期]` 断言。

这些断言是 **HARD REQUIREMENTS**，必须全部实现。

### 2.4 从 DESIGN.md 提取相关约束

提取：
- 技术栈约束（框架、语言）
- 全局响应格式约定
- 权限/角色规则
- 状态机规则
- CSS Token / 设计系统要求
- 核心交互原则

### 2.5 提取样式约束（如有）

从样式文档（open-design-prompt.md / DESIGN.md 样式章节 / token 定义文件）提取：
- 页面布局描述
- CSS Token 表
- 组件视觉规范

### 2.6 组装上下文包

将以上所有内容组装为结构化上下文包：

```
## API 契约（强制遵循）
[相关 endpoint 的完整 schema]

## 交互流程断言（HARD REQUIREMENTS，每条必须实现）
[flows.md 中该页面的所有 [预期] 断言，编号列出]

## 设计约束
[技术栈、响应格式、权限规则、状态机规则]

## 样式约束（如有）
[CSS Token 必须用 var(--xxx)，禁止硬编码颜色]

## 绝对禁止
[根据项目已知 bug 模式 / 反模式列出]

## 现有代码
[相关组件接口、API 模块签名，子 agent 必须复用]
```

---

## Phase 3: 开发执行

### 3.1 组装最终 Prompt

```
<任务描述>

<上下文包>

## 指令
1. 先 Read 所有需要引用的现有文件（API 模块、组件、CSS），确认接口签名
2. 基于上下文包中的契约、断言、约束编写代码
3. 不要创建新的 API 调用模块，复用现有的
4. 不要修改不相关的文件
5. 完成后自检：每条 [预期] 断言是否实现？每个 API 调用是否与契约一致？
```

### 3.2 调用子 agent 开发

使用 subagent 执行开发任务。

### 3.3 读取子 agent 产出

检查子 agent 修改了哪些文件，确认修改范围合理。

---

## Phase 4: 验证与打回

### 4.1 调用 spec-verify

运行 `/spec-verify`（或读取 spec-verify skill 的 Phase 2 检查规则手动执行）。

### 4.2 判断结果

- **全部 PASS** → Phase 5
- **有 FAIL** → 进入打回循环

### 4.3 打回循环（最多 3 次）

```
打回计数 = 0
while 验证不通过 and 打回计数 < 3:
    1. 收集所有 FAIL 项，格式化为修复指令
    2. 将修复指令追加到原任务 prompt 后面
    3. 重新调用子 agent（相同上下文包 + 修复指令）
    4. 重新验证
    打回计数 += 1

if 打回计数 >= 3:
    🚨 标记：人工介入
    展示最终失败清单
    让用户决定：手动修复 / 跳过 / 降低标准
```

修复指令格式：
```
上次代码有以下问题，请修复：
1. [FAIL项1的具体描述，含文件路径和行号]
2. [FAIL项2的具体描述]
请只修复这些问题，不要重写整个文件。
```

---

## Phase 5: 完成

- 报告开发结果：修改了哪些文件、验证通过
- 如果通过了打回循环：告知"第 N 次重试后通过"
- 建议运行测试确认

---

## 重要规则

1. **契约三件套缺失时绝对不开发。** DESIGN.md + api-contract.yaml + flows.md 缺一不可。
2. **上下文包必须包含完整 API schema，不能只写路径。** 子 agent 需要知道字段名和类型。
3. **[预期] 断言必须编号列出。** 方便 verify 阶段逐条检查。
4. **打回时只让 agent 修复失败项，不要全量重写。** 避免引入新问题。
5. **未知的现有代码必须先 Read 再引用。** 不要假设 API 签名。
6. **最多打回 3 次。** 超过则标记人工介入，不做死循环。

## 下游

| 消费者 | 说明 |
|--------|------|
| spec-verify | 开发完成后自动调用 |
| write-plan | 上游：产出任务列表 |
| subagent | 被包装：实际执行开发的 agent |

## 与 superpowers 的关系

此 skill 不替代 superpowers 的任何 skill。它位于 write-plan 和 subagent 之间，作为上下文注入适配层。
