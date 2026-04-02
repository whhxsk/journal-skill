#!/bin/bash
# 每天 23:20 自动将当日 journal 精炼写入 memory/YYYY-MM-DD.md
# 用法: journal-daily-compact.sh [YYYY-MM-DD]
# 不带参数默认处理当天

# Detect workspace from script location: skills/journal/scripts/ -> workspace
JOURNAL_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MEMORY_DIR="$JOURNAL_ROOT/memory"
LOG="$JOURNAL_ROOT/logs/journal-compact.log"

# 解析日期
if [ -z "$1" ]; then
    TARGET_DATE=$(date +%Y-%m-%d)
else
    TARGET_DATE="$1"
fi
TARGET_DATE_NODASH=$(echo "$TARGET_DATE" | tr -d '-')

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始处理 $TARGET_DATE" >> "$LOG"

# 找 journal 文件（兼容新格式 YYYYMMDD.jsonl 和旧格式 YYYYMMDD-HHMMSS-main.jsonl）
JOURNAL_FILE=""
for pattern in \
    "$JOURNAL_ROOT/journals/current/${TARGET_DATE_NODASH}.jsonl" \
    "$JOURNAL_ROOT/journals/current/${TARGET_DATE_NODASH}"-*-main.jsonl; do
    if [ -f "$pattern" ]; then
        JOURNAL_FILE="$pattern"
        break
    fi
done

if [ -z "$JOURNAL_FILE" ] || [ ! -f "$JOURNAL_FILE" ]; then
    echo "[$(date)] 没有找到 $TARGET_DATE 的 journal，跳过" >> "$LOG"
    exit 0
fi

MEMORY_FILE="$MEMORY_DIR/${TARGET_DATE}.md"
mkdir -p "$MEMORY_DIR"

python3 - "$JOURNAL_FILE" "$MEMORY_FILE" "$TARGET_DATE" << 'PYEOF'
import json, sys

journal_file = sys.argv[1]
memory_file = sys.argv[2]
target_date = sys.argv[3]

with open(journal_file, 'r', encoding='utf-8') as f:
    rows = [json.loads(l) for l in f if l.strip()]

user_texts = []
for r in rows:
    if r.get('role') == 'user' and r.get('text'):
        text = r['text'].strip()
        if len(text) > 5:
            user_texts.append(text)

all_text = ' '.join(user_texts)
topics = []
kw_map = {
    '公众号/微信': ['公众号','微信','wechat','发布文章'],
    '搜索/Tavily': ['tavily','搜索','search'],
    '定时任务/Cron': ['cron','定时','凌晨'],
    '记账系统': ['记账','jizhang','消费','支出'],
    'OpenClaw': ['openclaw'],
    '记忆/Journal': ['memory','记忆','journal','会话'],
    '番茄小说': ['番茄','fanqienovel','小说'],
    '技术/脚本': ['python','脚本','code'],
    '飞书': ['飞书','feishu'],
    '文件管理': ['文件','上传','下载'],
}
for topic, kws in kw_map.items():
    if any(k in all_text for k in kws):
        topics.append(topic)

first_msg = user_texts[0] if user_texts else ''
last_msg = user_texts[-1] if len(user_texts) > 1 else ''

seen = set()
unique_msgs = []
for t in user_texts:
    key = t[:30].lower()
    if key not in seen and len(t) > 10:
        seen.add(key)
        unique_msgs.append(f"- {t[:120]}{'...' if len(t) > 120 else ''}")

time_str = target_date[11:] if len(target_date) > 11 else '23:20'

section = f"""
## {time_str} journal 精炼

**消息总数：** {len(rows)} 条 | **用户消息：** {len(user_texts)} 条
**主题：** {', '.join(topics) if topics else '一般对话'}

**开场意图：** {first_msg[:100]}{'...' if len(first_msg) > 100 else ''}
**终了意图：** {last_msg[:100]}{'...' if len(last_msg) > 100 else ''}
"""
if unique_msgs:
    section += '\n**消息节选：**\n' + '\n'.join(unique_msgs[:12])

with open(memory_file, 'a', encoding='utf-8') as f:
    f.write(section + '\n')

print(f"✅ 写入 {len(unique_msgs)} 条消息到 {memory_file}")
PYEOF

echo "[$(date)] 完成" >> "$LOG"
