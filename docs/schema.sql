-- ============================================================
-- 行为设计 APP - MVP 数据库表结构
-- PostgreSQL
-- 核心理论：福格行为模型 B=MAP + 掌控习惯（身份认同）
-- ============================================================

-- ============================================================
-- 1. 行为计划 behavior_plans
--    用户通过 AI 对话设计的完整行为方案
--    融合：MAP 三要素 + 身份认同
-- ============================================================
CREATE TYPE plan_status AS ENUM ('active', 'paused', 'archived');

CREATE TABLE behavior_plans (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title           VARCHAR(200)    NOT NULL,           -- 计划名称，如"每日阅读习惯"
    identity        VARCHAR(300),                       -- 身份认同，如"我是一个持续学习的人"
    goal            TEXT,                               -- 目标描述（M - 动机）
    motivation      TEXT,                               -- 为什么重要（M - 动机）
    ability_notes   TEXT,                               -- 能力评估备注（A - 能力）
    trigger_anchor  TEXT,                               -- 触发锚点描述（P - 提示）
    obstacle_notes  TEXT,                               -- 障碍预判
    status          plan_status     NOT NULL DEFAULT 'active',
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_plans_status ON behavior_plans(status);

-- ============================================================
-- 2. 行为 behaviors
--    计划下的具体行为项，支持 cron 调度 + 阶段递进
-- ============================================================
CREATE TABLE behaviors (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plan_id         BIGINT          NOT NULL REFERENCES behavior_plans(id) ON DELETE CASCADE,
    name            VARCHAR(200)    NOT NULL,           -- 行为名称，如"睡前阅读"
    description     TEXT,                               -- 详细说明
    trigger_desc    TEXT,                               -- 触发条件，如"刷牙后立即拿起书"
    -- 调度规则
    recurrence_rule VARCHAR(100)    NOT NULL DEFAULT '0 0 * * *',
                                                        -- cron 表达式，示例：
                                                        -- '0 9 * * 1,3,5'  每周一三五 9:00
                                                        -- '0 22 * * *'     每天 22:00
                                                        -- '0 9 * * 1-5'   工作日 9:00
    duration_min    INTEGER         NOT NULL DEFAULT 2, -- 预计耗时（分钟），默认2分钟规则
    remind_before_min INTEGER       NOT NULL DEFAULT 10,-- 提前多少分钟发送通知
    -- 阶段递进
    stage_week      INTEGER         NOT NULL DEFAULT 1, -- 第几周开始执行
    stage_target    VARCHAR(200),                       -- 该阶段目标，如"读2页"
    sort_order      INTEGER         NOT NULL DEFAULT 0,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_behaviors_plan_id ON behaviors(plan_id);
CREATE INDEX idx_behaviors_active ON behaviors(plan_id, is_active);

-- ============================================================
-- 3. 每日任务 daily_tasks
--    由 behaviors 按 cron 规则展开生成，支撑日历视图
-- ============================================================
CREATE TYPE task_status AS ENUM ('pending', 'done', 'skipped');

CREATE TABLE daily_tasks (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    behavior_id     BIGINT          NOT NULL REFERENCES behaviors(id) ON DELETE CASCADE,
    plan_id         BIGINT          NOT NULL REFERENCES behavior_plans(id) ON DELETE CASCADE,
                                                        -- 冗余 plan_id，方便日历按计划筛选
    scheduled_date  DATE            NOT NULL,
    scheduled_time  TIME,                               -- 从 cron 解析出的执行时间
    status          task_status     NOT NULL DEFAULT 'pending',
    completed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- 防止同一行为同一天重复生成
CREATE UNIQUE INDEX idx_tasks_behavior_date ON daily_tasks(behavior_id, scheduled_date);
-- 日历视图：按月查询某天有哪些任务
CREATE INDEX idx_tasks_date ON daily_tasks(scheduled_date);
-- 首页：今日任务按状态筛选
CREATE INDEX idx_tasks_date_status ON daily_tasks(scheduled_date, status);
-- 按计划筛选日历
CREATE INDEX idx_tasks_plan_date ON daily_tasks(plan_id, scheduled_date);

-- ============================================================
-- 4. 打卡记录 check_ins
--    打卡详情 + AI 即时反馈
-- ============================================================
CREATE TABLE check_ins (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    daily_task_id   BIGINT          NOT NULL REFERENCES daily_tasks(id) ON DELETE CASCADE,
    checked_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    ai_feedback     TEXT,                               -- AI 即时正向反馈
    note            TEXT,                               -- 用户备注（可选）
    mood            SMALLINT CHECK (mood BETWEEN 1 AND 5)  -- 心情评分 1-5
);

CREATE INDEX idx_checkins_task_id ON check_ins(daily_task_id);
CREATE INDEX idx_checkins_checked_at ON check_ins(checked_at);

-- ============================================================
-- 5. 对话记录 conversations
--    所有 AI 对话，按类型区分用途
-- ============================================================
CREATE TYPE conversation_type AS ENUM ('design', 'adjust', 'report', 'checkin_feedback');

CREATE TABLE conversations (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type            conversation_type NOT NULL,
    plan_id         BIGINT          REFERENCES behavior_plans(id) ON DELETE SET NULL,
    title           VARCHAR(200),
    messages        JSONB           NOT NULL DEFAULT '[]'::jsonb,  -- [{role, content, timestamp}]
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_conversations_plan_id ON conversations(plan_id);
CREATE INDEX idx_conversations_type ON conversations(type);

-- ============================================================
-- 6. AI 配置 ai_configs
--    支持多套配置，仅一套激活
-- ============================================================
CREATE TABLE ai_configs (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(100)    NOT NULL,           -- 配置名称，如"DeepSeek"、"GPT-4o"
    api_base_url    VARCHAR(500)    NOT NULL,           -- API 地址
    api_key         VARCHAR(500)    NOT NULL,           -- API Key
    model_name      VARCHAR(200)    NOT NULL,           -- 模型名，如"gpt-4o"、"deepseek-chat"
    is_active       BOOLEAN         NOT NULL DEFAULT FALSE,  -- 是否当前选中
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- 保证最多只有一条 is_active = true（部分索引）
CREATE UNIQUE INDEX idx_ai_configs_active ON ai_configs(is_active) WHERE is_active = TRUE;
