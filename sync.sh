#!/bin/bash
set -e

cd "$(dirname "$0")"

# ============================================================
# LOG Sync Script
# 多设备协同：先拉后推，只追加不修改
# ============================================================

LOG_DIR="$(pwd)"
INBOX="$LOG_DIR/inbox"

# 1. 同步远端（获取其他设备的更新）
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pulling from remote..."
git pull --rebase origin main 2>&1 || true

# 2. 检查是否有待处理的 .txt
shopt -s nullglob
TXT_FILES=("$INBOX"/*.txt)
COUNT=${#TXT_FILES[@]}

if [ "$COUNT" -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No new entries. Silent exit."
    exit 0
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found $COUNT txt file(s). Processing..."

# 3. 调用 Claude Code 整理
claude -p "处理 inbox/ 目录下的 .txt 文件，按以下规则整理：

## 整理规则

1. 读取 inbox/ 下所有 .txt 文件，每份文件视为一条独立的记录。
2. 为每条记录做结构化标注：
   - 识别领域：开发 / 学习 / 工具 / 其他
   - 识别技术栈：如 c# / python / rust / git 等
   - 生成标题行：**【领域】[技术栈] 一句话摘要**
   - 保留原始内容原文，**不扩充、不改写**
   - 在原文下方附 2-3 条 **回顾方向** 或 **代码示例**（简短，作为延伸提示）
3. 输出到 daily/YYYY/MM/YYYY-MM-DD.md（目录不存在则创建），文件已存在则追加到末尾。
4. 处理完毕的 .txt 移入 archive/YYYY/MM/（保留原始文件名）。
5. 完成后直接退出，不发起交互请求。"

# 4. 提交并推送
git add -A
git commit -m "sync: $(date '+%Y-%m-%d') — $(date '+%H:%M')" || {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Nothing to commit."
    exit 0
}

git push origin main || {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Push conflict, retrying after pull..."
    git pull --rebase origin main
    git push origin main
}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync complete."
