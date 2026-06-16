---
name: spec-dev
description: 规格驱动开发入口 — 从设计文档自动提取上下文注入子 agent，开发完成后自动验证，不通过则打回重试（最多 3 次）
---

# Spec Dev Skill

项目开发入口。自动从设计文档中提取上下文，注入子 agent prompt，开发完成后验证一致性，不通过则打回修复（最多 3 次）。

## When to Apply

- 任何遵循规格文档结构的项目开发任务
- 用户说"开发 XX 功能"、"实现 XX"、"写代码"
- 用户从 write-plan 拿到任务列表后

Do NOT apply when:
- 只讨论设计，不写代码
- 只修配置文件
- 项目缺少必要的规格文档

## Trigger

```
/spec-dev
```

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

### 1.2 读取规格文档

强制文件，缺失任何一个都 STOP：

```bash
[ -f "$PROJECT_ROOT/docs/DESIGN.md" ] && echo "✅ docs/DESIGN.md" || { echo "❌ docs/DESIGN.md not found"; exit 1; }
[ -f "$PROJECT_ROOT/docs/api-contract.yaml" ] && echo "✅ docs/api-contract.yaml" || { echo "❌ docs/api-contract.yaml not found"; exit 1; }
[ -f "$PROJECT_ROOT/docs/flows.md" ] && echo "✅ docs/flows.md" || { echo "❌ docs/flows.md not found"; exit 1; }
```

推荐文件，缺失时 warn：

```bash
[ -f "$PROJECT_ROOT/CONTEXT.md" ] && echo "✅ CONTEXT.md" || echo "⚠️ CONTEXT.md not found — 建议先建立领域语言（/grill-with-docs）"
[ -f "$PROJECT_ROOT/docs/open-design-prompt.md" ] && echo "✅ docs/open-design-prompt.md" || echo "⚠️ docs/open-design-prompt.md not found"
[ -f "$PROJECT_ROOT/CLAUDE.md" ] && echo "✅ CLAUDE.md" || echo "⚠️ CLAUDE.md not found"
```

全部强制文件通过后，完整读取每个文件。CONTEXT.md 若存在也必须完整读取。

### 1.3 理解任务

向用户确认开发任务：
- 如果是 write-plan 产出的任务列表：读取并确认
- 如果是用户口述：复述并确认理解

---

## Phase 2: 上下文切分

### 2.1 识别任务涉及的页面/模块

从任务描述中识别涉及的页面名称或模块。

### 2.2 从 api-contract.yaml 切出相关端点

找到与任务相关的所有 API 端点，提取完整的 schema 定义（request/response 字段、query 参数、错误码）。

不确定时多切不要少切。

### 2.3 从 flows.md 切出相关断言

找到与任务相关的 Flow 章节，提取所有 `[预期]` 断言。

这些断言是 HARD REQUIREMENTS，必须全部实现。

### 2.4 从 DESIGN.md 提取相关约束

提取技术栈、响应格式、权限规则、状态机、CSS Token、交互原则、组件模式等。

### 2.5 从 CONTEXT.md 提取领域术语（若有）

若存在，将其核心术语注入上下文包。子 agent 必须使用其中定义的命名，不得自行创造同义词。

### 2.6 从 open-design-prompt.md 提取样式约束（若有）

### 2.7 组装上下文包

```
## 领域语言（若 CONTEXT.md 存在）
[核心术语定义]

## API 契约（强制遵循）
[相关 endpoint schema，含完整字段定义]

## 交互流程断言（HARD REQUIREMENTS）
[flows.md 中所有 [预期] 断言，编号列出]

## 设计约束
[技术栈、响应格式、权限、状态机]

## 样式约束
[CSS Token 规则]

## 绝对禁止
[已知反模式]

## 现有代码
[相关组件接口、API 模块签名]
```

---

## Phase 3: 开发执行

### 3.1 组装最终 Prompt

```
<任务描述>

<上下文包>

## 指令
1. 先 Read 所有需要引用的现有文件，确认接口签名
2. 基于契约、断言、约束编写代码
3. 复用现有 API 模块，不创建新的调用模块
4. 不修改不相关的文件
5. 完成后自检：每条 [预期] 断言是否实现？每个 API 调用是否与契约一致？

## 后端开发约束（后端子 agent 强制）
- TDD: 每个新函数/新接口先写一个失败测试，再写最小实现
- 禁止水平切片：一次一个测试 → 一个实现，不能先写完所有测试再实现
- 提交前确认：每个新增函数有对应测试，且亲眼见过测试失败

## 前端开发约束（前端子 agent 强制）
- 返回前运行已有测试：
  npx vitest run --reporter=verbose 2>&1 | tail -10
- 有红修到绿再返回，不破坏已有功能
```

### 3.2 调用子 agent 开发

### 3.3 读取子 agent 产出

检查修改文件范围是否合理。

---

## Phase 4: 验证与打回

### 4.1 调用 spec-verify

### 4.2 判断结果

- **全部 PASS** → Phase 5
- **有 FAIL** → 进入打回循环

### 4.3 打回循环（最多 3 次）

```
打回计数 = 0
while 验证不通过 and 打回计数 < 3:
    1. 收集所有 FAIL 项，格式化为修复指令
    2. 追加修复指令到原任务 prompt
    3. 重新调用子 agent
    4. 重新运行 spec-verify
    5. 打回计数 += 1

if 打回计数 >= 3:
    🚨 标记人工介入
```

修复指令格式：
```
上次代码有以下问题，请逐一修复：

1. <FAIL项 1 — 文件路径、行号、具体问题>
2. <FAIL项 2 — 文件路径、行号、具体问题>
...

## 修复规则（强制）
- 一次只修一个问题。修完用对应命令自检确认，再修下一个。
  样式问题 → grep 确认硬编码颜色已移除
  API 路径问题 → grep 确认路径已修正
  断言遗漏 → 对照 flows.md 确认已实现
  类型错误 → npx tsc --noEmit
- 修之前先说 "我认为根因是 X，改了 Y 应该能修复"
- 禁止同时改多个问题（出了问题无法定位原因）
- 禁止不验证直接提交
```

---

## Phase 5: 完成

- 报告修改文件、验证结果
- 若经过打回：告知第 N 次重试后通过
- 建议运行完整测试确认

---

## 重要规则

1. **规格文档缺一不可。** DESIGN.md + api-contract.yaml + flows.md 全部必须存在。
2. **CONTEXT.md 存在时必须遵循其术语。** 子 agent 不得自创同义词。
3. **上下文包必须含完整 API schema。** 不能只写路径，子 agent 需要字段名和类型。
4. **[预期] 断言必须编号列出。** 便于 verify 逐条检查。
5. **打回时一次只修一个问题。** 修完自检通过再修下一个。
6. **现有代码必须先 Read 再引用。** 不假设 API 签名。
7. **最多打回 3 次。** 超过标记人工介入。
8. **后端任务强制 TDD。** 先测试再代码，禁止水平切片。
9. **前端任务返回前运行已有测试。** 不破坏已有功能。

## 下游

| 消费者 | 说明 |
|--------|------|
| spec-verify | 开发完成后自动调用 |
| write-plan | 上游：产出任务列表 |
| subagent | 被包装：实际执行开发的 agent |

## 与 superpowers 的关系

此 skill 不替代 superpowers 的任何 skill。它位于 write-plan 和 subagent 之间，作为上下文注入适配层。
