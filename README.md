# 🛠 Claude Code Skills — Spec-Driven Frontend Pipeline

六个 Claude Code 自定义 skill + 一个 vendored skill，覆盖从需求收敛到前端开发、验证、测试的完整流程。

## Skills

| Skill | 命令 | 功能 |
|-------|------|------|
| **api-design** | `/api-design` | 从设计文档自动生成 API 契约（OpenAPI YAML + Markdown） |
| **flow-extract** | `/flow-extract` | 从 API 契约推断前端页面结构和交互流程 |
| **spec-dev** | `/spec-dev` | 按规格文档驱动开发，注入上下文到子 agent，自动验证打回 |
| **spec-verify** | `/spec-verify` | 检查代码与 API 契约、交互流程的一致性 |
| **frontend-test** | `/frontend-test` | 自动化前端组件测试，含自修复循环 |
| **design-prototype** | `/design-prototype` | 从规格文档生成 open-design 提示词，校验原型产物，归档到 docs/ |
| **grill-with-docs**（vendored） | `/grill-with-docs` | 拷问式需求收敛，建立 CONTEXT.md 领域语言（源出 mattpocock/skills，已内置） |

### 流水线关系

```
Phase 1  /office-hours → /grill-with-docs（CONTEXT.md）→ /plan-ceo-review → /plan-eng-review
                ↓
Phase 2  /api-design → api-contract.md/yaml
           /flow-extract → flows.md
           /design-prototype → open-design-prompt.md + 原型
                ↓
Phase 3  writing-plans（superpowers）→ docs/plans/
           /spec-dev → 代码（调用 /spec-verify 验证，不过则打回重试 ≤3 轮）
                ↓
Phase 4  /frontend-test → 组件测试
```

完整编排规则（各阶段文档放哪、上下游怎么传上下文）由 install.sh 自动注入 `~/.claude/CLAUDE.md` 的 **Development Flow** 段。

## 安装

### 方式一：curl 一行安装（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rainmancswh-dot/claude-skills/main/install.sh)
```

自动检测远程执行，clone 仓库后安装。默认装全部 6 个 skill，并自动：

- 安装 vendored 的 `grill-with-docs`（缺失时）
- 检查外部依赖（gstack、superpowers），缺失时打印手动安装指引
- 向 `~/.claude/CLAUDE.md` 注入 **Development Flow 编排段**（已有则跳过，改前自动备份）

### 装指定 skill

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rainmancswh-dot/claude-skills/main/install.sh) api-design spec-dev spec-verify
```

### 方式二：克隆后安装

```bash
git clone https://github.com/rainmancswh-dot/claude-skills.git
bash claude-skills/install.sh              # 默认全部 6 个
bash claude-skills/install.sh spec-dev     # 指定
bash claude-skills/install.sh --check-deps # 只检查依赖，不装 skill
```

## 外部依赖（完整流程需要）

本仓库的 skill 之外，完整 Development Flow 还依赖两个外部工具，install.sh 只提示、不代装：

| 依赖 | 用途 | 安装 |
|------|------|------|
| **gstack** | Phase 1 的 `/office-hours`、`/plan-ceo-review`、`/plan-eng-review` | `git clone <gstack-repo> ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup` |
| **superpowers 插件** | Phase 3 的 `writing-plans` | Claude Code 内执行 `/plugin install superpowers@superpowers-marketplace` |

只用到 Phase 2 之后（`/api-design` → `/spec-dev`）的话，不装这两个也能跑。

## 卸载

```bash
git clone https://github.com/rainmancswh-dot/claude-skills.git /tmp/claude-skills
bash /tmp/claude-skills/uninstall.sh            # 卸载全部已安装的
bash /tmp/claude-skills/uninstall.sh spec-dev   # 只卸载指定的
```

## 前置依赖

### api-design
- **必需**：Git 仓库
- **可选**：gstack 的 `/office-hours` 输出（设计文档）和 `/plan-eng-review` 输出（技术方案）
- 没有设计文档也能用，但需要手动描述需求

### flow-extract
- **必需**：`api-contract.md`（由 `/api-design` 生成）
- **可选**：设计文档、eng-review 输出

### spec-dev
- **必需**：`DESIGN.md` + `api-contract.yaml` + `flows.md`（三件套缺一不可，缺则 STOP）
- **可选**：`open-design-prompt.md`（样式 prompt）、项目 `CLAUDE.md`
- 依赖 spec-verify（开发后自动调用验证）

### spec-verify
- **必需**：`api-contract.yaml` + `flows.md`
- 通常由 spec-dev 自动调用，也可手动运行

### frontend-test
- **必需**：前端项目（React / Vue / Next.js），已安装 Vitest + Testing Library
- **可选**：gstack browse（用于失败组件截图）
- 自动检测框架和测试依赖，缺少时会提示安装命令

### design-prototype
- **必需**：`api-contract.yaml` + `flows.md`
- 生成 open-design 提示词，原型产物归档到 `docs/prototype/`

### grill-with-docs
- **必需**：一个想清楚的计划/想法
- 产出 `CONTEXT.md`（项目根目录），下游所有 skill 读取并遵循其术语
- Phase 1 的核心环节，缺了它整条流程的领域语言就断了

## 各 Skill 详解

### /api-design

从设计文档和现有代码推断 API 接口：
1. 扫描项目现有的路由、模型、API 风格
2. 从设计文档提取业务实体
3. 只问推断不了的问题（枚举值、删除策略、权限等）
4. 生成 `api-contract.md`（人类可读）+ `api-contract.yaml`（OpenAPI 3.0）
5. 自动做一致性检查（分页格式、DELETE 无 body、YAML schema 完整性等）

### /flow-extract

从 API 契约推断前端页面和交互：
1. 解析 API 实体，映射到页面
2. 按复杂度分类（简单/中等/复杂），简单页面自动确认
3. 生成 `flows.md`，包含每页的操作流程、异常分支、[预期]断言
4. 自动检查 API 覆盖率、路由一致性

### /spec-dev

按规格文档驱动开发 + 自动验证打回：
1. 检测 DESIGN.md / api-contract.yaml / flows.md 是否齐全（缺则 STOP）
2. 用任务关键词在契约里切出相关端点的完整 schema
3. 从 flows.md 提取 [预期] 断言（HARD REQUIREMENTS）
4. 组装「上下文包」注入子 agent 开发
5. 开发后调用 spec-verify，FAIL 则把问题回灌子 agent 重试，最多 3 轮
6. 超过 3 轮标记人工介入

### /spec-verify

代码与契约一致性检查（只读，不自动改代码）：
1. **API 路径一致性** — 前端调用路径 vs 契约定义，方法匹配
2. **API 参数一致性** — query/body 参数名、类型、必填项
3. **flows.md 断言覆盖率** — 每条 [预期] 在代码中是否有实现（语义匹配）
4. **CSS Token 合规** — 页面代码不硬编码颜色
5. **禁止模式扫描** — prompt()/alert()、纯文字 loading、伪造数据等

### /frontend-test

自动化组件测试 + 自修复：
1. 扫描组件，按依赖深度排序（叶子组件优先）
2. 推断交互规格（状态、事件、数据流）
3. 并行派发 subagent 写测试
4. 失败自动修复，最多 3 轮
5. 生成测试报告，在隔离分支上工作

## License

MIT
