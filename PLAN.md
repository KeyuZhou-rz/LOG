# LOG 系统规划

## 目标

将随手写的 `.txt` 片段（学习体会、开发问题、解决方案等）整理成结构化的按日 `.md` 文档，并通过 launchd 定时自动同步到 GitHub，形成一个可检索的统一入口。

---

## 目录结构

```
LOG/
├── inbox/                          # [git] 待处理的 .txt 片段，自由写入
├── daily/                          # [git] 整理后的 .md 文档
│   └── YYYY/
│       └── MM/
│           └── YYYY-MM-DD.md       # 基于日期的扁平结构
├── archive/                        # [git] 已处理的 .txt 移入此处
│   └── YYYY/
│       └── MM/
│           └── <原始文件名>.txt
├── sync.sh                         # [git] 同步脚本，所有设备共用
├── com.log.sync.plist              # [本地] launchd 配置，每台设备独立管理
├── .gitignore
└── .claude/
    └── settings.local.json         # [本地] 权限配置，每台设备独立管理
```

---

## 工作流

```
launchd 触发 sync.sh
    ↓
  git pull --rebase（先拉远端最新）
    ↓
  检查 inbox/ 是否有 .txt 文件
    ├── 有：Agent 读取 → 整理到 daily/YYYY/MM/YYYY-MM-DD.md → .txt 移入 archive/
    │       → git add -A → git commit → git push
    │       → push 失败（冲突）→ pull --rebase 重试 → push
    └── 无：静默退出
```

---

## 组件说明

### 1. inbox/ — 入口

- 无格式要求的自由 `.txt` 文件。
- 用户随时写入任意内容，文件名任意。
- 整理完成后被移入 `archive/`。

### 2. daily/YYYY/MM/YYYY-MM-DD.md — 输出

Agent 会从原始 `.txt` 中提取内容，重新组织为结构化记录：

- 保留原始内容，**不扩充**。
- 为其添加标签，例如：
  - `【开发】[c#] yield return null — 配合 while 循环控制协程执行`
  - `【学习】[rust] 所有权与借用规则 — 理解与常见误区`
- 附带几个简短的回顾方向 + 代码示例（由 Agent 生成，作为延伸提示）。

每日一个文件，文件内按条目排列，不做分类聚合。

### 3. sync.sh — 同步脚本

核心逻辑：

```bash
#!/bin/bash
# 1. git pull --rebase（先拉远端，同步其他设备的工作）
# 2. 检查 inbox/ 是否有 .txt 文件
# 3. 有 → 调用 claude CLI 让 Agent 整理
# 4. → git add -A && git commit && git push
# 5. → push 失败则 pull --rebase --rebase 后重试 push
# 6. 无 → exit 0
```

脚本提交到 git 仓库，所有设备共用同一份。

原则：**先拉后推**。始终以远端最新状态为基础开始处理，避免多设备同时修改同一日 `.md` 产生冲突。

### 4. launchd plist — 定时调度

文件路径：`~/Library/LaunchAgents/com.log.sync.plist`

触发时机：
- `RunAtLoad: true` — 开机/登录时立即执行一次
- `StartCalendarInterval` — 每天 10:00、16:00、00:00 各执行一次

---

## Agent Prompt 要求

传给 Claude CLI 的 prompt 需包含以下指令：

1. 读取 `inbox/` 下所有 `.txt` 文件。
2. 对每条记录：
   - 识别其领域和主题（开发/学习/工具/其他）。
   - 添加标签头，如 `【开发】[c#] ...`。
   - 在原始内容下方附上 2-3 个回顾方向或代码示例。
   - **不改变、不扩充原始记录的文字本身**。
3. 将整理结果写入当日 `daily/YYYY/MM/YYYY-MM-DD.md`，若文件已存在则追加。
4. 将已处理的 `.txt` 移入 `archive/YYYY/MM/`。
5. 完成后不发起交互请求，直接退出。

---

## .claude/settings.local.json 权限

需确保允许以下操作：

```json
{
  "permissions": {
    "allow": [
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git pull *)",
      "Bash(git push *)"
    ]
  }
}
```

---

## .gitignore

```
.DS_Store
.claude/
.scheduled_tasks.json
```

---

## 多设备协同

### 原理

每台设备上都是一个 `git clone` 的副本，`sync.sh` 以 **先拉后推** 模式工作，保证任意一台设备整理的内容都能同步到其他设备。

### 冲突场景与处理

| 场景 | 处理方式 |
|------|----------|
| A 整理的 .md 已 push，B 才开始处理 | B 先 `pull --rebase` 拿到 A 的版本，再 append 自己 inbox 的内容，无冲突 |
| A 和 B 同时 push 到同一个 .md | 先到先得，后到的 push 被拒绝 → `pull --rebase` 重试 → 再 push |
| 网络不通 / push 失败 | 本地 commit 保留，下次 sync.sh 执行时重新 pull + amend + push |

**关键设计**：`.md` 文件只追加不修改已有内容，因此即使两个设备同时操作同一文件，rebase 合并也几乎不会产生语义冲突。

### 每台设备需要做的

sync.sh 和目录结构都跟随 git 仓库，新设备只需：

1. `git clone` 仓库到本地相同路径（如 `~/Desktop/LOG/`）
2. 将 `com.log.sync.plist` 拷贝/软链到 `~/Library/LaunchAgents/`
3. `launchctl load ~/Library/LaunchAgents/com.log.sync.plist`
4. 确保 Claude Code CLI 已安装并可用

launchd plist 不同步到 git（每台设备独立管理），`.claude/settings.local.json` 同理。

---

## 实施步骤

1. 创建目录结构（`inbox/`、`archive/`、`daily/`）。
2. 编写 `sync.sh` 脚本。
3. 编写 `com.log.sync.plist` 并加载到 launchd。
4. 更新 `.claude/settings.local.json` 权限。
5. 创建 `.gitignore`。
6. 用一条示例 `.txt` 手动测试完整流程。
7. 验证 launchd 定时触发是否正常。

---

## 验证方法

1. 在 `inbox/` 放入一个测试 `.txt` 文件。
2. 手动运行 `./sync.sh`，确认：
   - `daily/` 中生成了正确的 `.md` 文件。
   - `inbox/` 中的文件被移入 `archive/`。
   - `git log` 可见新 commit，远程仓库已收到 push。
3. 用 `launchctl list | grep com.log.sync` 确认 plist 已加载。
4. 保持 inbox 为空，运行 `sync.sh`，确认静默退出。
