# Roche Coding Assessment

**Candidate:** Ioannis Vasilas  
**Date:** April 2026  
**Repo:** https://github.com/Ioannis1789/roche-coding-assessment

---

## Overview

Four-question pharmaverse coding assessment covering SDTM, ADaM, TLG, and GenAI/Python, using the CDISC CDISCPILOT01 Alzheimer's study dataset.

---

## Q1 — SDTM DS Domain (`question_1_sdtm/`)

**Package:** `{sdtm.oak}` v0.2.0  
**Input:** `pharmaverseraw::ds_raw` (raw CRF disposition data)  
**Output:** DS domain with 850 records, 11 SDTM variables

**Key decisions:**
- Used `assign_no_ct()` for DSTERM from `IT.DSTERM` (title-cased raw CRF field)
- Used `assign_ct()` for DSDECOD with custom `study_ct` controlled terminology (C66727)
- Used `hardcode_no_ct()` for DSCAT = "DISPOSITION EVENT" (constant, not on CRF)
- Used `assign_datetime()` with `raw_fmt = "m-d-y"` for `IT.DSSTDAT` → DSSTDTC
- Merged date + time columns (`DSDTCOL`, `DSTMCOL`) for DSDTC
- `INSTANCE` → VISIT (no VISITNUM in raw data)
- `derive_seq()` for DSSEQ, `derive_study_day()` for DSSTDY

**Files:**
- `01_create_ds_domain.R` — script
- `ds_domain.rds` / `ds_domain.csv` — output dataset
- `01_create_ds_domain_log.txt` — execution log

---

## Q2 — ADaM ADSL (`question_2_adam/`)

**Package:** `{admiral}` v1.4.1  
**Input:** `pharmaversesdtm::dm`, `ex`, `vs`, `ae`, `ds`  
**Output:** ADSL with 306 subjects, 45 variables

**Key decisions:**
- `derive_vars_cat()` for AGEGR9/AGEGR9N (admiral ≥ 1.2.0 API)
- `derive_vars_dtm()` with `flag_imputation = "time"` for TRTSDTM/TRTSTMF — hours imputed for all 254 treated subjects (date-only EXSTDTC), flag = "H"
- ITTFL: all 306 subjects `"Y"` (ARM populated including Screen Failures in this dataset)
- `derive_vars_extreme_event()` + `event()` for LSTAVLDT from 4 sources: VS, AE, DS, ADSL.TRTEDT (replaced deprecated `date_source()` API)
- 17 NA in LSTAVLDT = Screen Failure subjects with no post-randomisation observations

**Files:**
- `create_adsl.R` — script
- `adsl.rds` / `adsl.csv` — output dataset
- `create_adsl_log.txt` — execution log

---

## Q3 — TLG Adverse Events Reporting (`question_3_tlg/`)

**Packages:** `{gtsummary}` v2.5.0, `{ggplot2}` v3.5+  
**Input:** `pharmaverseadam::adae`, `pharmaverseadam::adsl`  
**Output:** HTML table + 2 PNG plots

**Script 1 — AE Summary Table:**
- `tbl_hierarchical()` for SOC → Preferred Term nested table (gtsummary ≥ 2.0 API)
- De-duplicated one record per subject per SOC/AETERM before tabulation
- `sort_hierarchical(sort = "descending")` for frequency ordering
- Denominator: 254 subjects (Screen Failures excluded)
- 254-row table across 3 treatment arms

**Script 2 — Visualisations:**
- Plot 1: Stacked bar chart of TEAE severity by treatment arm (MILD/MODERATE/SEVERE)
- Plot 2: Forest-style dot plot of top 10 AEs with 95% Clopper-Pearson exact binomial CIs

**Files:**
- `01_create_ae_summary_table.R`, `02_create_visualizations.R`
- `ae_summary_table.html`, `plot1_ae_severity.png`, `plot2_top10_ae.png`
- `01_create_ae_summary_table_log.txt`, `02_create_visualizations_log.txt`

---

## Q4 — GenAI Clinical Data Assistant (`question_4_python/`)

**Language:** Python 3.11  
**Packages:** `pandas`, `langchain` (optional)  
**Input:** `adae.csv` (1191 rows, 107 columns)

**Architecture — Prompt → Parse → Execute pipeline:**

```
User question (natural language)
        ↓
  _parse_question()   ← LLM (OpenAI/Anthropic) OR mock rule-based parser
        ↓
  {"target_column": "AESEV", "filter_value": "MODERATE"}
        ↓
  _execute_query()    ← Pandas .str.contains() case-insensitive filter
        ↓
  {subject_count: 136, subject_ids: [...]}
```

**LLM integration:** Supports OpenAI (`gpt-4o-mini`) and Anthropic Claude via LangChain.  
Auto-detects API keys; falls back to rule-based mock parser when none are set.

**Test results (mock mode):**
| Query | Column | Value | Subjects |
|---|---|---|---|
| Moderate severity AEs | AESEV | MODERATE | 136 |
| Patients with Headache | AETERM | HEADACHE | 16 |
| Cardiac adverse events | AESOC | CARDIAC DISORDERS | 44 |

**Files:**
- `clinical_data_agent.py` — `ClinicalTrialDataAgent` class
- `test_queries.py` — 3-query test script
- `adae.csv` — ADAE dataset exported from R

---

## Running the Code

### R (Q1–Q3)
```r
# In R, from project root:
.libPaths("~/R/library")  # adjust to your R library path

# Q1
source("question_1_sdtm/01_create_ds_domain.R")

# Q2
source("question_2_adam/create_adsl.R")

# Q3
source("question_3_tlg/01_create_ae_summary_table.R")
source("question_3_tlg/02_create_visualizations.R")
```

### Python (Q4)
```bash
cd question_4_python
python test_queries.py
# Optional: export OPENAI_API_KEY="sk-..." for real LLM mode
```

### R Package Versions Used
| Package | Version |
|---|---|
| admiral | 1.4.1 |
| sdtm.oak | 0.2.0 |
| pharmaverseraw | 0.1.1 |
| pharmaversesdtm | 1.4.1 |
| pharmaverseadam | 1.3.0 |
| gtsummary | 2.5.0 |
| ggplot2 | 3.5.x |
| R | 4.5.3 |
