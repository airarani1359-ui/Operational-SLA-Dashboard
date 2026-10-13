# Operational & SLA Dashboard | MySQL + Power BI

**Business question:** A customer support team handling 8,000+ e-commerce tickets is missing its 85% SLA target. Where do the breaches come from, and what should the operations manager fix first?

> **Data:** simulated support tickets (Jan–Jun 2025), designed from my experience in e-commerce customer support operations. It includes deliberate data-quality issues to clean.

![Executive Overview](screenshots/01_executive_overview.png)

## Tools
- **MySQL 8 (Workbench):** raw-data staging, data-quality checks, cleaning, a reusable SLA view, and analysis with JOINs, CASE WHEN, a CTE and window functions (`LAG`, `RANK`, `SUM() OVER()`)
- **Power BI:** Power Query, 10 DAX measures, 2 calculated columns, conditional formatting against target, slicers, 3 report pages

## Process
1. **Load:** imported 3 CSVs into MySQL. Raw ticket columns are stored as text so blank cells load safely.
2. **Check:** found 12 duplicate tickets, 12 spellings for 4 channels (`email`, `EMAIL `…), and 6 tickets resolved before they were created.
3. **Clean:** built a clean `tickets` table (8,122 → 8,104 rows) with proper date and number types. The raw table is kept unchanged.
4. **Transform:** created `vw_ticket_sla`, which joins tickets to agents and SLA targets and flags each ticket as met or breached for first response and resolution.
5. **Analyse:** answered 5 business questions in SQL (channel, category, month, agent, CSAT).
6. **Visualise:** built the Power BI report and reconciled every KPI with SQL (71.4% in both).

## Headline KPIs
| Tickets | SLA compliance | First-response compliance | Avg resolution | Avg CSAT | Backlog |
|---|---|---|---|---|---|
| 8,104 | **71.4%** (target 85%) | 65.7% | 22.2 hrs | 3.90 / 5 | 290 |

## Key findings
1. **Email is the weakest channel:** 49.6% SLA vs 87.4% on Chat. Only Chat meets the target.
2. **Refund & Payment causes 33.7% of all breaches** with only 20% of volume, and fails at every priority level (about 50–53%).
3. **March peak:** volume rose 73% and SLA dropped 17 points, then recovered in April. This is a capacity issue during seasonal peaks.
4. **Late tickets hurt satisfaction:** CSAT falls from 4.21 to 3.14, and unhappy ratings rise from 2.1% to 25.4%.
5. **5 agents are below 70%** while most of their teams sit at 70–80%. This calls for targeted coaching.
6. **Ageing backlog:** 224 of 290 open tickets (77%) are over 7 days old, and 59 of them are Critical or High.

## Recommendations
- Email auto-acknowledgement plus a dedicated email queue.
- A dedicated refund queue, or approval limits for agents, to remove the refund bottleneck.
- Staffing plans before Ramadan and sale periods.
- 1-to-1 coaching for the lowest-performing agents.
- A weekly backlog review with an owner and a closure deadline for escalations.

## Report pages
| Executive Overview | SLA Drill-down | Agent Performance & Backlog |
|---|---|---|
| ![](screenshots/01_executive_overview.png) | ![](screenshots/02_sla_drilldown.png) | ![](screenshots/03_agent_backlog.png) |

## Files
| File | Contents |
|---|---|
| `sla_analysis.sql` | All SQL: tables, quality checks, cleaning, view, analysis |
| `dax_measures.dax` | All DAX measures and calculated columns |
| `SLA_Dashboard.pbix` | Power BI report |
| `data/` | tickets.csv, agents.csv, sla_policy.csv, vw_ticket_sla.csv |
| `screenshots/` | Report page images |
