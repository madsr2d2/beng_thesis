<style>
hr {
  border: none !important;
  border-top: 3px solid #ccc !important;
  margin: 2em 0 !important;
  height: 0 !important;
  display: block !important;
}
</style>

<!-- omit in toc -->

# B.Eng Thesis Project Plan

**Author:** Mads Richardt, s224948

---

<!-- omit in toc -->

## Table of Contents

- [Document Overview](#document-overview)
- [Key Stakeholders](#key-stakeholders)
- [Project Brief (from Company Advisor)](#project-brief-from-company-advisor)
- [Gantt Chart](#gantt-chart)
- [Risks and Mitigation Strategies](#risks-and-mitigation-strategies)

---

## Document Overview

This document presents the project plan for a Bachelor of Engineering thesis, conducted in collaboration with the company Everllence, focused on extending an existing CAN bus VHDL module to support the Flexible Data rate (FD) protocol ([ISO 11898-1:2024](https://www.iso.org/standard/86384.html)). The project runs from 23-02-2026 to 07-06-2026 (15 weeks) and will deliver a thesis report, VHDL implementation, and a verification suite (VHDL + Python). The plan outlines the objectives, timeline, deliverables, and key risks for the project.

---

## Key Stakeholders

- **Student:** Mads Richardt (DTU B.Eng candidate, s224948, <mads.richardt@gmail.com>)
- **DTU Advisor:** Edward Alexandru Todirica (Associate Professor, <eato@dtu.dk>)
- **Company Advisor:** Fredrik Kristensen (Everllence, <fredrik.kristensen@man-es.com>)

---

## Project Brief (from Company Advisor)

> **FD CAN bus extension.**
>
> The goal of the project is to extend the, by Mads, previously designed CAN bus VHDL module to also include the Flexible Data rate (FD) protocol.
> This work will cover:
>
> 1. Initial project planning
> 2. Read and understand the FD CAN bus standard
> 3. Identify updates and how to test these updates
> 4. Implementation and testing on a module level
> 5. Incorporate the design into the existing engine controller
> 6. Write test SW in Python
> 7. Document the design

---

## Gantt Chart

```mermaid
gantt
    dateFormat  YYYY-MM-DD
    axisFormat  %d/%m
    tickInterval 1week
    excludes    weekends
    title       B.Eng Thesis Project Plan

    section Report writing
    Daily report updates        :active,report, after project_plan, 71d
    Create report framework     :done,milestone, ver_plan_done, 2026-02-26, 0d
    First report draft complete        :crit, milestone, first_draft, after full_test, 0d
    All deliverables submitted  :crit, milestone, report_done, after report, d0

    section Setup
    Project start date                  :crit, milestone, complete, 2026-02-23, 0d
    Environment & tool-chain setup      :done, setup, 2026-02-23, 2d
    Create project plan (this document) :active, project_plan, after setup, 1d

    section Verification Plan
    Read and understand ISO 11898-1 2024            :done,milestone, read, after plan, 0d
    Create verification plan                        :ver_plan, after plan, 4d
    Status update with company advisor              :milestone, udp, 2026-03-02, 0d
    Status update with DTU advisor                  :milestone, dtu_udp_1, after ver_plan, 0d
    Verification plan review with company advisor:  crit,milestone, ver_plan_rew, after ver_plan, 0d

    section Design
    Design space exploration & architecture definition :design, after ver_plan_rew, 8d
    Status update with company advisor                 :milestone, ver_plan_udp, 2026-03-09, 0d
    Status update with DTU advisor                     :milestone, dtu_udp_2, after design, 0d
    Design review with company advisor                 :crit,milestone, design_rew, after design, 0d

    section VHDL Implementation & Testing
    VHDL implementation & testbenches               :imp, after design_rew, 30d
    Status update with company advisor              :milestone, imp_upd_1, after design_rew, 10d
    Status update with company advisor              :milestone, imp_upd_2, after design_rew, 20d
    Status update with company advisor              :milestone, imp_upd_3, after design_rew, 30d
    Status update with DTU advisor                  :milestone, dtu_udp_3, after design_rew, 30d
    Status update with company advisor              :milestone, imp_upd_4, after design_rew, 40d
    Status update with company advisor              :milestone, imp_upd_4, after design_rew, 50d
    Status update with DTU advisor                  :milestone, dtu_udp_4, after imp, 0d
    VHDL implementation review with company advisor :crit,milestone, imp_done, after imp, 0d

    section Integration testing
    Integration testing                 :inte, after imp_done, 15d
    Python reference model              :milestone, python_ref, after imp_done, 10d
    Status update with company advisor  :milestone, inte_upd, after imp_done, 20d
    Status update with DTU advisor  :milestone, imp_upd_4, after inte, 0d
    Full test coverage                  :crit, milestone, full_test, after inte, 0d

    section Buffer
    Buffer time for unexpected delays or issues :buffer, after full_test, 15d
    Wife pregnancy due date                     :crit, milestone, m10, 2026-05-27, 0d
    Project end date                            :crit, milestone, complete, 2026-06-07, 0d
```

---

## Risks and Mitigation Strategies

|Risk|Mitigation|
|:---|:---|
|Project schedule slips due to underestimated tasks or unforeseen issues.|Build in buffer time. Review progress weekly. Prioritize critical tasks|
|Report writing takes longer than expected.|Maintain ongoing documentation. Set internal deadlines for drafts. Seek feedback regularly.|
|Late discovery of design or verification issues.|Develop and follow a detailed verification plan. Run regression tests frequently. Review design with advisors.|
| Python reference model development takes longer than expected.|Limit reference model to essential features (CRC reference, frame generator, bit stuffing check). Prototype early. Plan for integration testing with hardware and ensure tools are compatible with the target environment.| 
|Hardware integration or testing reveals unexpected issues.|Plan for early integration testing. Coordinate with company advisor for access to hardware and test environments. Document hardware requirements and constraints.|
| External factors (e.g., family emergencies, advisor availability) impact timeline. | Maintain flexibility. Communicate proactively with stakeholders. Adjust plan as needed.|
