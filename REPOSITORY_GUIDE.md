# DeepSeek Harness 项目导览

> 本文件是仓库的「地图」：告诉你每个目录/文件是干什么的。想深入某个子系统，按每节末尾的链接跳到官方文档。

DeepSeek Harness（简称 `dsh`）是 DeepSeek AI 开源的 **Agent Harness**（智能体运行框架），核心架构是 **「一切皆插件」（everything-is-a-plugin）**，插件运行时由 [Cordis](https://github.com/cordiverse/cordis) 提供。整个仓库是一个 **pnpm monorepo**，几乎所有功能都以 `@deepseek-ai/dsh-*` 的 npm 工作区包形式存在。

---

## 1. 顶层目录速览

| 目录 | 用途 |
|---|---|
| `apps/` | 4 个可直接运行的应用入口（CLI / Web / Electron 桌面 / 桌面宿主） |
| `packages/` | 插件库主体，所有 `@deepseek-ai/dsh-*` 包（按 `<group>/<pkg>` 组织） |
| `vendor/` | 内置的 Cordis 生态源码副本（pinned） |
| `native/` | 原生 C 系统二进制（节点插件）源码 |
| `python/` | Python SDK 与运行时 |
| `docs/` | 文档（架构 / 开发 / 用户指南等） |
| `scripts/` | 构建、门禁（gate）、代码生成器脚本 |
| `website/` | VitePress 文档站点（把 `docs/` 投影成网站） |
| `benchmarks/` | 性能基准（benchmark）门槛 |
| `snapshots/` | 录制的会话回放快照（测试期望输出） |
| `.agents/` | Agent 工作流配置与「决策笔记」（agent notes） |
| `.github/` | GitHub 上的 CI/CD、Issue 模板、review 规则等 |
| `patches/` | 通过 pnpm `patchedDependencies` 打的第三方依赖补丁 |

具体布局和约定以 [AGENTS.md](AGENTS.md) 与 [packages/README.md](packages/README.md) 为准。

---

## 2. apps/ — 可运行的应用入口

每个应用都建立在 `packages/` 的插件之上，本身只负责「组装 + 启动」。

| 目录 | 包名 | 干什么 |
|---|---|---|
| `apps/cli` | `@deepseek-ai/dsh` | **`dsh` 命令行入口**。负责 profile 启动、插件管理（install/uninstall）、配置检查（dump-config）。`dsh web`、`dsh --profile headless '任务'` 等命令都从这里发起。 |
| `apps/web` | `@deepseek-ai/dsh-web-frontend` | **Web 前端**。用 Vite 构建，产物 `dist/` 由 `dsh web` 提供。是全平台通用的 GUI 壳。 |
| `apps/desktop` | `@deepseek-ai/dsh-desktop` | **Electron 桌面壳**。把内置的 dsh 运行时 + 外部插件装进一个桌面应用（欢迎页、系统账户登录、自动更新等）。**注意：官方只打包 macOS（arm64/x64）和 Windows（x64），没有 Linux 目标**（见 `apps/desktop/README.zh.md`）。 |
| `apps/desktop-host` | `@deepseek-ai/dsh-desktop-host` | **桌面的私有宿主进程**。Electron 主进程以 Node 模式启动它，它在 `:19387` 跑起 Web 后端并回报 URL 给壳。 |

---

## 3. packages/ — 插件库主体

`packages/<group>/<pkg>/` 里每个包都是 `@deepseek-ai/dsh-<pkg>`。分组含义如下（按 [AGENTS.md](AGENTS.md) 的 layout）。

### 核心能力（Agent / 模型）

| 分组 | 用途 | 代表包 |
|---|---|---|
| `core/` | Agent/会话核心 API | `agent`、`agent-loop`、`session`、`scope`、`tools`、`system-prompt` |
| `llm/` | 模型提供商 | `llm`、`llm-deepseek`、`llm-pi-ai`、`llm-retry`、`token-meter` |
| `typert/` | 类型图（协议 / 生成器 / 注册表） | `protocol`、`generator`、`registry`、`loader` |
| `context/` | 请求上下文 | `agent-instructions`、`file-reference`、`time-context`、`tmux-context` |
| `compaction/` | 上下文压缩 | `compaction`、`compaction-basic`、`compaction-image-offload` |

### 执行能力（命令 / 进程 / 环境）

| 分组 | 用途 | 代表包 |
|---|---|---|
| `shell/` | 命令执行 | `tool-bash`、`shell`、`bash-local`、`bash-sandbox`、`pwsh-*` |
| `subprocess/` | 子进程管理 | `subprocess`、`subprocess-local` |
| `ssh/` | 通过 SSH 执行 | `ssh`、`fs-ssh`、`sandbox-ssh`、`subprocess-ssh` |
| `terminal/` | 持久终端 | `terminal`、`tool-terminal` |
| `ptc-runtime/` | PTC 执行（持久工具调用运行时） | `ptc-runtime`、`ptc-runtime-node` |
| `sandbox/` | 进程隔离（文件沙箱等） | `sandbox`、`sandbox-policy`、`sandbox-local` |
| `fs/` | 文件系统访问 | `tool-fs`、`fs`、`fs-local`、`tool-fs-search`、`tool-str-replace-editor` |
| `lsp/` | 语言服务器 | `lsp`、`lsp-stdio`、`tool-lsp` |
| `computer-use/` | 计算机交互（视觉操作） | `computer-use` |
| `browser-use/` | 浏览器交互 | `browser-use` |
| `web/` | 搜索/抓取工具 | `tool-web`、`web-fetch-http`、`web-search-deepseek/exa/perplexity` |

### 工具 / 技能 / 协议

| 分组 | 用途 | 代表包 |
|---|---|---|
| `skill/` | 技能加载 | `skill`、`tool-skill`、`skill-filesystem`、`skill-office` |
| `mcp/` | 外部工具（MCP 客户端） | `mcp-client`、`mcp-resources` |
| `acp/` | 仅自动化的 ACP（Agent Client Protocol） | `acp` |
| `deliverables/` | 轮次交付物 | `tool-present`、`workspace-changes` |
| `todo/` | `todo_write` 工具 | `tool-todo` |
| `webhook/` | Webhook 入口 | `webhook`、`webhook-github` |

### 多步骤 / 编排

| 分组 | 用途 | 代表包 |
|---|---|---|
| `workflow/` | 工作流执行 | `workflow`、`tool-workflow`、`tool-ralph` |
| `plan/` | 计划模式（带日志的计划） | `plan-mode` |
| `goal/` | 会话目标（长任务延续） | `goal`、`tool-goal`、`command-goal` |
| `schedule/` | 定时跟进 | `schedule` |
| `subagent/` | 委派子代理 | `tool-subagent`、`subagent-codex/claude-code/dsh-sdk/...` |
| `jobs/` | 后台任务 | `jobs`、`tool-jobs` |

### 会话 / 存储 / 数据

| 分组 | 用途 | 代表包 |
|---|---|---|
| `session/` | 持久会话（日志、格式、投影） | `session-format`（多版本迁移）、`session-persistence`、`session-projection` |
| `session-query/` | 会话浏览/搜索/导出 | `session-query`、`session-query-sqlite`、`session-log-export` |
| `attachment/` | 二进制附件 | `attachment`、`attachment-local` |
| `spill/` | 输出溢出（大输出落盘） | `spill`、`spill-local`、`spill-policy` |
| `storage/` | 非会话存储 | `storage`、`storage-json`、`storage-sqlite` |
| `workspace/` | 工作区实体 | `workspace` |

### 人机交互 / 身份 / 设置

| 分组 | 用途 | 代表包 |
|---|---|---|
| `interaction/` | 人工交互（确认 / 提问） | `tool-ask-user`、`user-approval`、`user-questions` |
| `feedback/` | 人工反馈（点赞点踩、命令反馈） | `message-feedback`、`command-feedback` |
| `identity/` | 匿名身份 | `anonymous-user-id` |
| `settings/` | 用户设置 | `settings` |
| `credentials/` | 凭证 / 授权 | `credentials`、`credentials-local`、`authorization`、`deepseek-account` |

### 启动 / 宿主 / 客户端

| 分组 | 用途 | 代表包 |
|---|---|---|
| `boot/` | 应用启动（profile、配置、插件管理） | `app-boot`、`plugin-manager`、`cmdline`、`config-editor` |
| `sdk/` | JSON-RPC SDK（对外扩展） | `protocol`、`server`、`client` |
| `host/` | GUI 宿主后端 | `webserver`、`directory-picker-*`、`frontend-static`、`open-in-app` |
| `client/` | GUI 客户端 | `connection`、`modules`、`resources`、`store`、`locale`，以及大量 `ui-*` 组件 |
| `extensions/` | 运行时自修改（Cordis runner） | `cordis-host-runner`、`cordis-client-runner`、`tool-cordis`、`ui-cordis` |
| `hooks/` | 桥接 Claude Code / Codex | `hook-protocol`、`hooks-claude-code`、`hooks-codex` |

### 其他

| 分组 | 用途 | 代表包 |
|---|---|---|
| `guard/` | 循环/工具守卫 | `timeout-policy`、`repeat-tool-reminder` |
| `preset/` | Agent 组合 | `agent-preset`、`agent-preset-registry`、`persona` |
| `document/` | Office 转 PDF | `office-to-pdf` |
| `experimental/` | 实验性原型（默认公开） | `inspector`、`agent-team`、`browser-use-*`、`speech-to-text*`、`webworker-*` |
| `test-support/` | 测试基础设施 | `llm-mock-server`、`llm-replay`、`agent-loop-testkit`、`remote-mock` |
| `runtime-diagnostics/` | 运行时不变量 | `invariants` |
| `util/` | 零依赖工具库 | `brand`、`crypto`、`home-paths`、`package-manifest`、`atomic-write`、`timeout` |

---

## 4. vendor/ — 内置的 Cordis 生态

`vendor/` 是 Cordis 生态的 **pinned 源码副本**（记录上游 SHA，见 `vendor/README.md`）。包括：

- `cordis` — 插件运行时核心
- `cosmokit` / `schemastery` — 配置/模式工具
- `loader`、`group`、`timer`、`hmr`、`logger-console`、`include` — Cordis 周边

这些是 monorepo 的基石依赖，通过 workspace 直接引用。

---

## 5. native/ — 原生系统插件

`native/system` = `@deepseek-ai/node-addon-system`，用 C 编译的原生二进制：

- **flock** — 稳定 Node-API 的文件锁（跨进程互斥）
- **landlock-run** — 静态 musl 的 Landlock 启动器（进程级文件隔离）

构建产物是编译出的 `system.node`（`tsx native/system/scripts/build.ts --host-addon-only`）。详见 `native/README.md`。

---

## 6. python/ — Python SDK 与运行时

- `python/sdk` — Python 版 SDK（把 Agent 循环投影成 Python 接口）
- `python/sdk-runtime` — Python 运行时部署清单（供打包/分发）

详见 `python/README.md`。

---

## 7. docs/ — 文档

关键入口文件（英文 `.md`，中文 `.zh.md` 成对存在，`*.i18n.yaml` 是翻译配对元数据）：

| 文件 | 内容 |
|---|---|
| `architecture.md` | 架构总览（改 `packages/` 前必读） |
| `development.md` | 开发指南（构建系统、TS 项目布局、命令表） |
| `agent-lifecycle.md` | Agent 生命周期 |
| `cordis-primer.md` / `cordis-tutorial/` / `cookbook/` | Cordis 入门 / 教程 / 实践手册 |
| `testing.md` | 测试策略 |
| `glossary.md` | 术语表（如 capability seam） |
| `tool-catalog.md` / `config-catalog.md` | 工具 / 配置目录 |
| `persistence-catalog.md` / `session-format-status.md` | 持久化与会话格式状态 |
| `defensive-patterns.md` | 生命周期/并发/子进程的防御式模式 |
| `subsystems/` | 各子系统专页 |
| `user/` | 用户指南（Web UI 等） |

---

## 8. scripts/ — 构建、门禁、生成器

`scripts/` 里有大量脚本，主要三类：

- **构建/运行**：`build.ts`（完整构建）、`dev-web.ts`（Web 开发服务器）
- **生成器**（产物生成到 `docs/` 或各包）：`gen-*`（工具目录、配置目录、Cordis API、依赖目录、模块图等）
- **校验门禁**：`verify-*`（文档、包路径、第三方声明、许可证、持久化格式等）、`run-gates.ts`（聚合门禁）

根 `package.json` 的 `scripts` 字段是这些脚本的入口（`build`、`typecheck`、`lint`、`test:*`、`check:*`、`verify-*` 等）。

---

## 9. website/ — 文档站点

用 **VitePress** 把 `docs/` 投影成文档网站（`pnpm run website:build`）。`build.ts` 负责构建，同时兼作死链检查。

---

## 10. 其余目录

| 目录 | 用途 |
|---|---|
| `benchmarks/` | 性能基准门槛（会话打开、长会话浏览器、终端 IO 等） |
| `snapshots/` | 录制会话回放快照，作为测试期望输出（`snapshots/AGENTS.md`） |
| `.agents/` | Agent 工作流与「决策笔记」（`notes/`、`skills/`） |
| `.github/` | GitHub CI (`workflows/`)、Issue/PR 模板、review 规则 |
| `patches/` | pnpm `patchedDependencies` 的第三方补丁（`exceljs`、`node-pty`、`@yao-pkg/pkg` 等） |

---

## 11. 关键顶层文件

| 文件 | 用途 |
|---|---|
| `package.json` | 根 manifest + 全部脚本（`build`、`test`、`dev:web`、`dsh` 等） |
| `pnpm-workspace.yaml` | workspace 定义 + `allowBuilds` 白名单 + 依赖补丁 + peer 规则 |
| `pnpm-lock.yaml` | 锁文件（pnpm 11.7.0） |
| `tsconfig.base.json` / `tsconfig.host.json` / `tsconfig.client.json` | TS 编译配置（host / client 两个「编译器面」） |
| `tsconfig.json` | 根 solution（指向子项目） |
| `tsdown.config.ts` | 各包打包配置 |
| `vitest*.ts` | 测试配置（单测/覆盖率/web/snapshot/e2e 等） |
| `lefthook.yml` | git 钩子（pre-commit 等） |
| `Makefile` | Web/Desktop 命令的快捷别名（`make web`、`make dev-desktop` 等） |
| `.oxlintrc.json` / `.jscpd.json` | lint / 克隆检测配置 |
| `pytest.ini` | Python 测试配置 |
| `AGENTS.md`（`CLAUDE.md` 软链到它） | Agent 工作协议（规范与仓库约定） |
| `README*` / `CONTRIBUTING*` / `SAFETY*` / `BRAND_GUIDELINES*` / `BENCHMARK.md` / `THIRD_PARTY_NOTICES.md` | 各类项目级说明文档 |

---

## 12. 常用命令速查

```sh
pnpm install                 # 安装依赖（pnpm workspaces）
pnpm run build               # 完整构建（原生 + lib + Web）
pnpm dsh web                 # 用已构建产物启动 Web UI（默认 http://127.0.0.1:3080）
pnpm run dev:web             # 构建 + 启动 Web，编辑时增量重建
pnpm run start:web           # 跳过构建，直接启动 Web
pnpm run dev:desktop         # 构建 + 启动 Electron 桌面端
pnpm run start:desktop       # 跳过构建，直接启动桌面端
pnpm run test                # 单元测试
pnpm run test:coverage       # CI 覆盖率门禁
pnpm run typecheck           # 类型检查
pnpm run lint                # lint
make web desktop dev-web dev-desktop build   # 同上的 Make 别名
```

> 桌面端（`desktop`）只支持 macOS / Windows；在 Linux 上需要 `DSH_DESKTOP_TARGET_PLATFORM=win32` 等绕过目标检查，且 Office/Python 相关能力不可用。图形化推荐用 `dsh web`。

---

## 13. 建议的阅读顺序

1. `README.md` — 项目是干什么的
2. 本文件 — 整体地图
3. `docs/architecture.md` — 架构
4. `docs/development.md` — 怎么开发
5. `packages/README.md` — 包组织规则
