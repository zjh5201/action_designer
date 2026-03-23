# 行为设计 APP 实现方案

## 项目背景

用户读完《福格行为模型》和《掌控习惯》后，希望借助 AI 将书中理论落地应用。

核心痛点：理论懂了，但真正设计行为方案时脑袋卡壳。

解决方案：AI 引导用户完成行为设计 → 生成可执行的习惯计划 → 每日打卡追踪 → 周期性复盘。

---

## 技术栈

| 层级 | 技术 |
|------|------|
| iOS 客户端 | SwiftUI |
| 服务端 | Python + FastAPI |
| 数据库 | PostgreSQL + SQLAlchemy (async) |
| AI 服务 | OpenAI 兼容 API（用户自行配置 URL / API Key / Model Name） |

---

## 核心理念：福格行为模型 B = MAP

- **M (Motivation)** 动机：目标是什么，为什么重要
- **A (Ability)** 能力：时间、精力、当前技能评估，行为要从微习惯开始（2分钟规则）
- **P (Prompt)** 提示：绑定现有习惯或特定场景作为触发锚点
- **阶段递进**：第1周极简，逐周加码约 20%
- **即时奖励**：完成打卡后 AI 给出个性化正向反馈

---

## MVP 核心流程

### 阶段1：行为设计对话

1. 用户在「新建习惯」入口发起会话
2. AI 进入引导模式，按 M → A → P 顺序逐步收集信息：
   - 目标与动机（想达成什么，为什么重要）
   - 能力评估（每天可用时间、当前水平、精力状态）
   - 触发锚点（现有习惯、特定时间/场景）
   - 障碍预判（什么情况会让你放弃）
3. 信息收集完成后，切换为自由对话模式，用户可反复调整
4. AI 生成行为方案草稿（含具体行为、时间、触发条件、阶段递进计划）

### 阶段2：确认行为时间表

- 以结构化卡片展示 AI 生成的方案
- 用户可通过自然语言对话调整（例："把阅读改到晚上10点"）
- 确认后方案固化为每日任务

### 阶段3：每日打卡

- 首页按天展示任务列表（今日任务，带时间标注）
- 完成任务后点击打卡
- 打卡后 AI 给出即时正向反馈（简短，多样化）
- iOS 本地推送通知 + APP 内消息提醒

### 阶段4：周期报告

- 每周自动生成：可视化卡片（完成率、连续天数、最佳习惯）+ AI 个性化分析与建议
- 月报同上，维度更宏观
- 用户可与 AI 对话深入探讨报告内容

---

## 数据库设计

```
behavior_plans
  id            UUID, PK
  title         VARCHAR         -- 计划名称
  goal          TEXT            -- 目标描述
  motivation    TEXT            -- 动机说明
  ability_notes TEXT            -- 能力评估备注
  trigger_anchor TEXT           -- 触发锚点描述
  status        ENUM            -- active / paused / archived
  created_at    TIMESTAMP

behaviors
  id            UUID, PK
  plan_id       UUID, FK → behavior_plans
  name          VARCHAR         -- 行为名称（如：早起后喝一杯水）
  description   TEXT
  scheduled_time TIME           -- 建议执行时间
  duration_min  INTEGER         -- 预计耗时（分钟）
  stage_week    INTEGER         -- 第几周开始执行
  stage_target  VARCHAR         -- 该阶段目标（如：5分钟）

daily_tasks
  id            UUID, PK
  behavior_id   UUID, FK → behaviors
  scheduled_date DATE
  scheduled_time TIME
  status        ENUM            -- pending / done / skipped
  completed_at  TIMESTAMP

check_ins
  id            UUID, PK
  daily_task_id UUID, FK → daily_tasks
  checked_at    TIMESTAMP
  ai_feedback   TEXT            -- AI 即时反馈内容
  note          TEXT            -- 用户备注

conversations
  id            UUID, PK
  type          ENUM            -- design / adjust / report / checkin_feedback
  plan_id       UUID, FK → behavior_plans (nullable)
  messages      JSONB           -- [{role, content, timestamp}]
  created_at    TIMESTAMP
  updated_at    TIMESTAMP

settings
  key           VARCHAR, PK     -- ai_base_url / ai_api_key / ai_model_name
  value         TEXT
```

---

## 项目目录结构

```
action_designer/
├── docs/
│   └── implementation-plan.md     # 本文件
│
├── backend/
│   ├── app/
│   │   ├── main.py                # FastAPI 入口，注册路由
│   │   ├── database.py            # 异步数据库连接与 session
│   │   ├── models/                # SQLAlchemy ORM 模型
│   │   │   ├── __init__.py
│   │   │   ├── plan.py
│   │   │   ├── behavior.py
│   │   │   ├── task.py
│   │   │   ├── checkin.py
│   │   │   ├── conversation.py
│   │   │   └── setting.py
│   │   ├── schemas/               # Pydantic 请求/响应模型
│   │   │   ├── plan.py
│   │   │   ├── task.py
│   │   │   ├── checkin.py
│   │   │   └── conversation.py
│   │   ├── routers/
│   │   │   ├── ai.py              # POST /ai/chat（SSE 流式）
│   │   │   ├── plans.py           # 行为计划 CRUD
│   │   │   ├── tasks.py           # 每日任务管理
│   │   │   ├── checkins.py        # 打卡
│   │   │   ├── reports.py         # 周报/月报
│   │   │   └── settings.py        # AI 配置读写
│   │   ├── services/
│   │   │   ├── ai_service.py      # OpenAI 兼容 API 封装
│   │   │   ├── task_scheduler.py  # behaviors → daily_tasks 生成逻辑
│   │   │   └── report_service.py  # 统计数据聚合
│   │   └── prompts/
│   │       ├── behavior_design.py # 行为设计引导 system prompt
│   │       ├── checkin_feedback.py
│   │       └── report_analysis.py
│   ├── alembic/                   # 数据库迁移脚本
│   ├── alembic.ini
│   ├── requirements.txt
│   └── .env.example               # 环境变量模板
│
└── ios/
    └── ActionDesigner/
        ├── Views/
        │   ├── HomeView.swift          # 今日任务列表首页
        │   ├── ConversationView.swift  # AI 对话界面（设计+调整）
        │   ├── PlanDetailView.swift    # 行为方案详情与管理
        │   ├── ReportView.swift        # 周报/月报
        │   └── SettingsView.swift      # AI API 配置
        ├── Models/                     # 本地数据模型
        ├── Services/
        │   ├── APIService.swift        # 后端 API 调用封装
        │   └── NotificationService.swift # 本地推送注册与调度
        └── ActionDesignerApp.swift
```

---

## API 接口设计

| Method | Path | 说明 |
|--------|------|------|
| POST | /ai/chat | AI 对话，SSE 流式返回 |
| POST | /plans | 创建行为计划 |
| GET | /plans | 获取所有计划列表 |
| GET | /plans/{id} | 获取单个计划详情 |
| PATCH | /plans/{id} | 更新计划状态 |
| GET | /tasks/today | 今日任务列表 |
| GET | /tasks?date=YYYY-MM-DD | 指定日期任务列表 |
| POST | /tasks/{id}/checkin | 打卡（返回 AI 即时反馈） |
| GET | /reports/weekly?week=YYYY-Www | 周报数据 |
| GET | /reports/monthly?month=YYYY-MM | 月报数据 |
| GET | /settings | 读取 AI 配置 |
| PUT | /settings | 更新 AI 配置 |

---

## AI Prompt 设计

### 行为设计引导（system prompt 核心要点）
- 角色：行为设计教练，精通福格行为模型（B=MAP）和《掌控习惯》
- 引导阶段：按 M→A→P 顺序提问，每次只问一个问题，不要一次抛出多个问题
- 方案生成：完成引导后输出结构化 JSON，格式如下：
  ```json
  {
    "title": "每日阅读习惯",
    "behaviors": [
      {
        "name": "睡前阅读",
        "scheduled_time": "22:00",
        "duration_min": 5,
        "trigger": "刷牙后立即拿起书",
        "stage_week": 1,
        "stage_target": "读2页"
      }
    ]
  }
  ```
- 核心原则：第一步必须极小（2分钟规则），后续逐周加码约20%

### 打卡即时反馈
- 简短（1-2句），正向，多样化，避免重复
- 根据场景差异化：首次完成 / 连续7天 / 今日恢复 / 阶段升级

### 周报/月报分析
- 先呈现数据摘要（完成率、连续天数、最难坚持的习惯）
- 再给出 1-2 条具体可操作的调整建议
- 语气：鼓励为主，客观分析为辅

---

## MVP 开发顺序

1. **后端基础**：FastAPI 项目结构 + PostgreSQL 连接 + Alembic 迁移
2. **AI 服务封装**：OpenAI 兼容调用 + SSE 流式输出
3. **行为设计对话接口**：引导 Prompt + 方案 JSON 解析存储
4. **任务生成逻辑**：behaviors → daily_tasks 按日展开
5. **打卡接口**：check-in 记录 + AI 即时反馈
6. **iOS 基础界面**：对话页 + 今日任务列表 + 打卡 + 设置页
7. **统计与报告**：数据聚合 + 可视化图表 + AI 分析对话
8. **推送通知**：iOS 本地通知注册与按任务时间调度

---

## 验证方式

1. 启动后端：`uvicorn app.main:app --reload`
2. 访问 Swagger UI (`/docs`) 测试 `/ai/chat` 接口，验证 SSE 流式返回
3. iOS 模拟器完整流程验证：
   - 新建习惯 → AI 引导对话 → 确认方案 → 查看今日任务 → 打卡 → 查看即时反馈
4. 验证第二天 `daily_tasks` 自动生成
5. 手动调用周报接口，验证统计数据正确性
