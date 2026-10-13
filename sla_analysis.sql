-- =====================================================================
-- Operational & SLA Dashboard | MySQL 8
-- Author: Aiswarya Rani
-- Flow: load raw data -> data quality checks -> clean -> SLA view -> analysis
-- =====================================================================

-- ---------------------------------------------------------------------
-- STEP 1. Database and raw tables
-- tickets_raw keeps every column as text so blank cells load safely.
-- Data was loaded with MySQL Workbench > Table Data Import Wizard.
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS sla_ops;
USE sla_ops;

CREATE TABLE tickets_raw (
  ticket_id          VARCHAR(20),
  created_at         VARCHAR(30),
  first_response_at  VARCHAR(30),
  resolved_at        VARCHAR(30),
  priority           VARCHAR(20),
  channel            VARCHAR(20),
  category           VARCHAR(40),
  agent_id           VARCHAR(10),
  status             VARCHAR(20),
  csat_score         VARCHAR(5),
  reopened_flag      VARCHAR(5)
);

CREATE TABLE agents (
  agent_id   VARCHAR(10) PRIMARY KEY,
  agent_name VARCHAR(50),
  team       VARCHAR(30),
  shift      VARCHAR(20),
  hire_date  DATE
);

CREATE TABLE sla_policy (
  priority                  VARCHAR(20) PRIMARY KEY,
  first_response_target_hrs DECIMAL(5,2),
  resolution_target_hrs     DECIMAL(5,2)
);

-- Row counts after import: tickets_raw 8122 | agents 23 | sla_policy 4
SELECT 'tickets_raw' AS table_name, COUNT(*) AS total_rows FROM tickets_raw
UNION ALL SELECT 'agents', COUNT(*) FROM agents
UNION ALL SELECT 'sla_policy', COUNT(*) FROM sla_policy;

-- ---------------------------------------------------------------------
-- STEP 2. Data quality checks
-- ---------------------------------------------------------------------
-- Check 1: duplicates  -> 12 duplicate rows
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT ticket_id) AS unique_tickets,
       COUNT(*) - COUNT(DISTINCT ticket_id) AS duplicate_rows
FROM tickets_raw;

-- Check 2: inconsistent channel spellings -> 12 spellings for 4 channels
SELECT CONCAT('[', channel, ']') COLLATE utf8mb4_bin AS channel_value,
       COUNT(*) AS row_count
FROM tickets_raw
GROUP BY channel_value
ORDER BY channel_value;

-- Check 3: resolved before created -> 6 impossible rows
SELECT COUNT(*) AS resolved_before_created
FROM tickets_raw
WHERE resolved_at <> '' AND resolved_at < created_at;

-- Check 4: blank resolved_at only on unfinished tickets -> OK
SELECT status, COUNT(*) AS tickets,
       SUM(resolved_at = '' OR resolved_at IS NULL) AS blank_resolved_at
FROM tickets_raw
GROUP BY status
ORDER BY tickets DESC;

-- ---------------------------------------------------------------------
-- STEP 3. Clean table (8,122 -> 8,104 rows)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tickets;
CREATE TABLE tickets AS
SELECT DISTINCT
  ticket_id,
  CAST(created_at AS DATETIME)         AS created_at,
  CAST(first_response_at AS DATETIME)  AS first_response_at,
  CASE WHEN resolved_at = '' THEN NULL
       ELSE CAST(resolved_at AS DATETIME) END AS resolved_at,
  priority,
  CASE UPPER(TRIM(channel))
    WHEN 'EMAIL'    THEN 'Email'
    WHEN 'CHAT'     THEN 'Chat'
    WHEN 'PHONE'    THEN 'Phone'
    WHEN 'WHATSAPP' THEN 'WhatsApp'
  END                                  AS channel,
  category,
  agent_id,
  status,
  CASE WHEN csat_score = '' THEN NULL
       ELSE CAST(csat_score AS UNSIGNED) END AS csat_score,
  CAST(reopened_flag AS UNSIGNED)      AS reopened_flag
FROM tickets_raw
WHERE resolved_at = '' OR resolved_at IS NULL OR resolved_at >= created_at;

-- Check: 4 clean channels, total 8,104
SELECT channel, COUNT(*) AS tickets FROM tickets GROUP BY channel ORDER BY tickets DESC;

-- ---------------------------------------------------------------------
-- STEP 4. SLA view (one row per ticket, used by Power BI)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_ticket_sla AS
SELECT
  t.ticket_id, t.created_at, DATE(t.created_at) AS created_date,
  t.priority, t.channel, t.category, t.agent_id, a.agent_name, a.team,
  t.status, t.csat_score, t.reopened_flag,
  s.first_response_target_hrs, s.resolution_target_hrs,
  ROUND(TIMESTAMPDIFF(MINUTE, t.created_at, t.first_response_at) / 60, 2) AS first_response_hrs,
  ROUND(TIMESTAMPDIFF(MINUTE, t.created_at, t.resolved_at) / 60, 2)       AS resolution_hrs,
  CASE WHEN TIMESTAMPDIFF(MINUTE, t.created_at, t.first_response_at) <= s.first_response_target_hrs * 60
       THEN 1 ELSE 0 END AS frt_met,
  CASE WHEN t.resolved_at IS NULL THEN NULL
       WHEN TIMESTAMPDIFF(MINUTE, t.created_at, t.resolved_at) <= s.resolution_target_hrs * 60
       THEN 1 ELSE 0 END AS sla_met
FROM tickets t
JOIN agents a     ON t.agent_id = a.agent_id
JOIN sla_policy s ON t.priority = s.priority;

-- Overall: 8104 tickets | 5582 met | 2232 breached | 290 open | 71.4% SLA
SELECT COUNT(*) AS total_tickets,
       SUM(sla_met = 1) AS met, SUM(sla_met = 0) AS breached,
       SUM(sla_met IS NULL) AS not_resolved,
       ROUND(100 * AVG(sla_met), 1) AS sla_compliance_pct
FROM vw_ticket_sla;

-- ---------------------------------------------------------------------
-- STEP 5. Business questions
-- ---------------------------------------------------------------------
-- 5A. SLA by channel -> Email 49.6% vs Chat 87.4%
SELECT channel, COUNT(*) AS tickets,
       ROUND(AVG(first_response_hrs), 2) AS avg_first_response_hrs,
       ROUND(100 * AVG(frt_met), 1) AS frt_compliance_pct,
       ROUND(100 * AVG(sla_met), 1) AS sla_compliance_pct
FROM vw_ticket_sla
GROUP BY channel
ORDER BY sla_compliance_pct;

-- 5B. Share of breaches by category (window function) -> Refund & Payment 33.7%
SELECT category, COUNT(*) AS tickets,
       SUM(sla_met = 0) AS breaches,
       ROUND(100 * AVG(sla_met), 1) AS sla_compliance_pct,
       ROUND(100 * SUM(sla_met = 0) / SUM(SUM(sla_met = 0)) OVER (), 1) AS share_of_all_breaches_pct
FROM vw_ticket_sla
GROUP BY category
ORDER BY breaches DESC;

-- 5C. Month-over-month trend (CTE + LAG) -> March: +825 tickets, -17.0 pts
WITH monthly AS (
  SELECT DATE_FORMAT(created_at, '%Y-%m') AS month,
         COUNT(*) AS tickets,
         ROUND(100 * AVG(sla_met), 1) AS sla_compliance_pct
  FROM vw_ticket_sla
  GROUP BY DATE_FORMAT(created_at, '%Y-%m')
)
SELECT month, tickets,
       tickets - LAG(tickets) OVER (ORDER BY month) AS volume_change,
       sla_compliance_pct,
       ROUND(sla_compliance_pct - LAG(sla_compliance_pct) OVER (ORDER BY month), 1) AS sla_change_pts
FROM monthly
ORDER BY month;

-- 5D. Agent ranking within team (RANK + PARTITION BY)
SELECT team, agent_name, COUNT(*) AS tickets,
       ROUND(100 * AVG(sla_met), 1) AS sla_compliance_pct,
       ROUND(AVG(csat_score), 2) AS avg_csat,
       RANK() OVER (PARTITION BY team ORDER BY AVG(sla_met) DESC) AS rank_in_team
FROM vw_ticket_sla
GROUP BY team, agent_id, agent_name
ORDER BY team, rank_in_team;

-- 5E. CSAT within SLA vs breached -> 4.21 vs 3.14
SELECT CASE sla_met WHEN 1 THEN 'Within SLA' ELSE 'Breached' END AS sla_outcome,
       COUNT(csat_score) AS surveys,
       ROUND(AVG(csat_score), 2) AS avg_csat,
       ROUND(100 * AVG(csat_score <= 2), 1) AS pct_unhappy_1_or_2
FROM vw_ticket_sla
WHERE csat_score IS NOT NULL
GROUP BY sla_outcome
ORDER BY avg_csat DESC;

-- Export for Power BI: run the line below and use Result Grid > Export > CSV
SELECT * FROM sla_ops.vw_ticket_sla;
