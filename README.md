# 🛠 Claude Code Skills — API Design to Frontend Testing Pipeline

三个 Claude Code 自定义 skill，覆盖从 API 设计到前端测试的完整前端开发流程。

## Skills

| Skill | 命令 | 功能 |
|-------|------|------|
| **api-design** | `/api-design` | 从设计文档自动生成 API 契约（OpenAPI YAML + Markdown） |
| **flow-extract** | `/flow-extract` | 从 API 契约推断前端页面结构和交互流程 |
| **frontend-test** | `/frontend-test` | 自动化前端组件测试，含自修复循环 |

### 流水线关系

```
/api-design → api-contract.md/yaml → /flow-extract → flows.md → /frontend-test
```

## 安装

### 方式一：一键安装（推荐）

```bash
git clone https://github.com/rainmancswh-dot/claude-skills.git /tmp/claude-skills
bash /tmp/claude-skills/install.sh
```

### 方式二：只安装指定 skill

```bash
bash /tmp/claude-skills/install.sh api-design flow-extract
```

### 方式三：curl 一行安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rainmancswh-dot/claude-skills/main/install.sh)
```

> 注意：curl 方式需要先将仓库推到 GitHub。此方式会 clone 仓库到临时目录后执行安装。

## 卸载

```bash
bash /tmp/claude-skills/uninstall.sh
# 或只卸载指定的
bash /tmp/claude-skills/uninstall.sh frontend-test
```

## 前置依赖

### api-design

- **必需**：Git 仓库
- **可选**：gstack 的 `/office-hours` 输出（设计文档）和 `/plan-eng-review` 输出（技术方案）
- 没有设计文档也能用，但需要手动描述需求

### flow-extract

- **必需**：`api-contract.md`（由 `/api-design` 生成）
- **可选**：设计文档、eng-review 输出

### frontend-test

- **必需**：前端项目（React / Vue / Next.js），已安装 Vitest + Testing Library
- **可选**：gstack browse（用于失败组件截图）
- 自动检测框架和测试依赖，缺少时会提示安装命令

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

### /frontend-test

自动化组件测试 + 自修复：
1. 扫描组件，按依赖深度排序（叶子组件优先）
2. 推断交互规格（状态、事件、数据流）
3. 并行派发 subagent 写测试
4. 失败自动修复，最多 3 轮
5. 生成测试报告，在隔离分支上工作

## License

MIT
