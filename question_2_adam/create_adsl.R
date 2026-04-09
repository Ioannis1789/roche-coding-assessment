# ==============================================================================
# Question 2: ADaM ADSL Dataset Creation using {admiral}
# ==============================================================================
# Description: Creates an ADSL (Subject Level Analysis) dataset from SDTM
#              source data using {admiral} and tidyverse tools.
# Input:       pharmaversesdtm::dm, pharmaversesdtm::vs,
#              pharmaversesdtm::ex, pharmaversesdtm::ds,
#              pharmaversesdtm::ae
# Output:      ADSL dataset with derived variables: AGEGR9, AGEGR9N,
#              TRTSDTM, TRTSTMF, ITTFL, LSTAVLDT
# References:  - Pharmaverse ADSL example:
#                https://pharmaverse.github.io/examples/adam/adsl.html
#              - {admiral} ADSL vignette:
#                https://pharmaverse.github.io/admiral/articles/adsl.html
# ==============================================================================

# --- Load Required Libraries --------------------------------------------------
.libPaths("~/R/library")  # ensure user package library is on path
library(admiral)
library(pharmaversesdtm)
library(dplyr, warn.conflicts = FALSE)
library(lubridate)
library(stringr)

# --- Step 1: Read in SDTM Source Data -----------------------------------------
dm <- pharmaversesdtm::dm
vs <- pharmaversesdtm::vs
ex <- pharmaversesdtm::ex
ds <- pharmaversesdtm::ds
ae <- pharmaversesdtm::ae

# Convert blank strings to NA (standard admiral practice)
dm <- convert_blanks_to_na(dm)
vs <- convert_blanks_to_na(vs)
ex <- convert_blanks_to_na(ex)
ds <- convert_blanks_to_na(ds)
ae <- convert_blanks_to_na(ae)

# --- Step 2: Start from DM domain --------------------------------------------
# The DM domain is the basis of ADSL (one record per subject).
# We drop the DOMAIN column and add initial treatment variables.
adsl <- dm %>%
  select(-DOMAIN) %>%
  mutate(
    TRT01P = ARM,
    TRT01A = ACTARM
  )

cat("=== Initial ADSL from DM ===\n")
cat("Rows:", nrow(adsl), "| Columns:", ncol(adsl), "\n\n")

# --- Step 3: Derive AGEGR9 and AGEGR9N ---------------------------------------
# Spec: Age grouping into categories: "<18", "18 - 50", ">50"
#        Numeric groupings: 1, 2, 3

# Option A: Using admiral::derive_vars_cat() (admiral >= 1.2.0)
agegr9_lookup <- exprs(
  ~condition,             ~AGEGR9,  ~AGEGR9N,
  AGE < 18,                 "<18",        1,
  between(AGE, 18, 50),  "18 - 50",      2,
  AGE > 50,                 ">50",        3,
  is.na(AGE),         NA_character_,     NA_real_
)

adsl <- derive_vars_cat(
  dataset = adsl,
  definition = agegr9_lookup
)

cat("=== AGEGR9 Distribution ===\n")
print(table(adsl$AGEGR9, useNA = "ifany"))
cat("\n=== AGEGR9N Distribution ===\n")
print(table(adsl$AGEGR9N, useNA = "ifany"))

# --- Step 4: Derive TRTSDTM and TRTSTMF --------------------------------------
# Spec: Treatment start date-time from the first exposure record per patient.
#   - Only valid doses: EXDOSE > 0 OR (EXDOSE == 0 AND EXTRT contains 'PLACEBO')
#   - Datepart of EXSTDTC must be complete
#   - Impute completely missing time with 00:00:00
#   - Impute partially missing time: 00 for hours, 00 for minutes, 00 for seconds
#   - If only seconds are missing, do NOT populate TRTSTMF
#
# admiral::derive_vars_dtm() handles datetime conversion and imputation.
# time_imputation = "first" imputes missing time parts with 00.
# The flag_imputation parameter controls TRTSTMF population.

# First, derive datetime variables on the EX domain
ex_ext <- ex %>%
  derive_vars_dtm(
    dtc = EXSTDTC,
    new_vars_prefix = "EXST",
    # Impute missing time parts: hours->00, minutes->00, seconds->00
    time_imputation = "first",
    # Only set imputation flag when hours or minutes are imputed, not seconds
    flag_imputation = "time"
  ) %>%
  derive_vars_dtm(
    dtc = EXENDTC,
    new_vars_prefix = "EXEN",
    time_imputation = "last"
  )

# Merge first valid exposure record per subject into ADSL
# Valid dose: EXDOSE > 0, or EXDOSE == 0 for PLACEBO
adsl <- adsl %>%
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add = (EXDOSE > 0 |
      (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) &
      !is.na(EXSTDTM),
    new_vars = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
    order = exprs(EXSTDTM, EXSEQ),
    mode = "first",
    by_vars = exprs(STUDYID, USUBJID)
  )

# Also derive TRTEDTM (needed for LSTAVLDT calculation later)
adsl <- adsl %>%
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add = (EXDOSE > 0 |
      (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) &
      !is.na(EXENDTM),
    new_vars = exprs(TRTEDTM = EXENDTM, TRTETMF = EXENTMF),
    order = exprs(EXENDTM, EXSEQ),
    mode = "last",
    by_vars = exprs(STUDYID, USUBJID)
  )

# Derive TRTSDT and TRTEDT (date parts) from datetime variables
adsl <- adsl %>%
  derive_vars_dtm_to_dt(source_vars = exprs(TRTSDTM, TRTEDTM))

cat("\n=== TRTSDTM Sample (first 10) ===\n")
adsl %>%
  select(USUBJID, TRTSDTM, TRTSTMF, TRTSDT) %>%
  head(10) %>%
  print()

# --- Step 5: Derive ITTFL (Intent-to-Treat Flag) -----------------------------
# Spec: "Y" if DM.ARM is not missing, "N" otherwise.
# This identifies randomized patients.
adsl <- adsl %>%
  mutate(
    ITTFL = if_else(!is.na(ARM), "Y", "N")
  )

cat("\n=== ITTFL Distribution ===\n")
print(table(adsl$ITTFL, useNA = "ifany"))

# --- Step 6: Derive LSTAVLDT (Last Known Alive Date) -------------------------
# Spec: Maximum of these four dates per subject:
#   (1) Last complete VS date with valid result (VSSTRESN and VSSTRESC not
#       both missing), datepart of VSDTC not missing
#   (2) Last complete AE onset date (datepart of AESTDTC)
#   (3) Last complete disposition date (datepart of DSSTDTC)
#   (4) Last treatment administration date where valid dose (datepart of TRTEDTM)
#
# admiral >= 1.2.0: use event() + derive_vars_extreme_event()
# (date_source() + derive_var_extreme_dt() are deprecated since 1.2.0)

adsl <- adsl %>%
  derive_vars_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    events = list(
      # Source 1: Vital Signs — last date with a valid result
      event(
        dataset_name = "vs",
        condition = !(is.na(VSSTRESN) & is.na(VSSTRESC)) & !is.na(VSDTC),
        set_values_to = exprs(LSTAVLDT = convert_dtc_to_dt(VSDTC))
      ),
      # Source 2: Adverse Events — last onset date
      event(
        dataset_name = "ae",
        condition = !is.na(AESTDTC),
        set_values_to = exprs(LSTAVLDT = convert_dtc_to_dt(AESTDTC))
      ),
      # Source 3: Disposition — last disposition date
      event(
        dataset_name = "ds",
        condition = !is.na(DSSTDTC),
        set_values_to = exprs(LSTAVLDT = convert_dtc_to_dt(DSSTDTC))
      ),
      # Source 4: Treatment end date from ADSL (already derived as TRTEDT)
      event(
        dataset_name = "adsl",
        condition = !is.na(TRTEDT),
        set_values_to = exprs(LSTAVLDT = TRTEDT)
      )
    ),
    source_datasets = list(vs = vs, ae = ae, ds = ds, adsl = adsl),
    order = exprs(LSTAVLDT),
    new_vars = exprs(LSTAVLDT),
    mode = "last",
    check_type = "none"  # duplicates expected when multiple sources share the same date
  )

cat("\n=== LSTAVLDT Sample (first 10) ===\n")
adsl %>%
  select(USUBJID, LSTAVLDT, TRTEDT) %>%
  head(10) %>%
  print()

# --- Step 7: Derive Additional Standard ADSL Variables ------------------------
# These are commonly expected in ADSL and follow the Pharmaverse example.

# Safety Population Flag
adsl <- adsl %>%
  derive_var_merged_exist_flag(
    dataset_add = ex,
    by_vars = exprs(STUDYID, USUBJID),
    new_var = SAFFL,
    false_value = "N",
    missing_value = "N",
    condition = (EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO")))
  )

# End of Study Date and Status
ds_ext <- derive_vars_dt(
  ds,
  dtc = DSSTDTC,
  new_vars_prefix = "DSST"
)

format_eosstt <- function(x) {
  case_when(
    x == "COMPLETED"     ~ "COMPLETED",
    x == "SCREEN FAILURE" ~ NA_character_,
    TRUE                  ~ "DISCONTINUED"
  )
}

adsl <- adsl %>%
  derive_vars_merged(
    dataset_add = ds_ext,
    by_vars = exprs(STUDYID, USUBJID),
    new_vars = exprs(EOSDT = DSSTDT),
    filter_add = DSCAT == "DISPOSITION EVENT" & DSDECOD != "SCREEN FAILURE"
  ) %>%
  derive_vars_merged(
    dataset_add = ds,
    by_vars = exprs(STUDYID, USUBJID),
    filter_add = DSCAT == "DISPOSITION EVENT",
    new_vars = exprs(EOSSTT = format_eosstt(DSDECOD)),
    missing_values = exprs(EOSSTT = "ONGOING")
  )

# Death Date
adsl <- adsl %>%
  derive_vars_dt(
    new_vars_prefix = "DTH",
    dtc = DTHDTC,
    highest_imputation = "M",
    date_imputation = "first"
  )

# Treatment Duration
adsl <- adsl %>%
  derive_var_trtdurd()

cat("\n=== SAFFL Distribution ===\n")
print(table(adsl$SAFFL, useNA = "ifany"))

# --- Step 8: Quality Checks --------------------------------------------------
cat("\n=== Final ADSL Dataset ===\n")
cat("Rows:", nrow(adsl), "| Columns:", ncol(adsl), "\n")

# Check the key derived variables
cat("\n=== Key Derived Variables Summary ===\n")
adsl %>%
  select(USUBJID, AGEGR9, AGEGR9N, TRTSDTM, TRTSTMF,
         ITTFL, LSTAVLDT, SAFFL) %>%
  head(15) %>%
  print()

cat("\n=== Missing Value Counts for Key Variables ===\n")
cat("AGEGR9  NA:", sum(is.na(adsl$AGEGR9)), "\n")
cat("AGEGR9N NA:", sum(is.na(adsl$AGEGR9N)), "\n")
cat("TRTSDTM NA:", sum(is.na(adsl$TRTSDTM)), "\n")
cat("ITTFL   NA:", sum(is.na(adsl$ITTFL)), "\n")
cat("LSTAVLDT NA:", sum(is.na(adsl$LSTAVLDT)), "\n")

# --- Step 9: Save Output Dataset ----------------------------------------------
# Paths are relative to the project root (roche-coding-assessment/)
# Run scripts with setwd() at the project root, or use source() from the root.
saveRDS(adsl, file = "question_2_adam/adsl.rds")
cat("\nADSL saved to question_2_adam/adsl.rds\n")

write.csv(adsl, file = "question_2_adam/adsl.csv", row.names = FALSE)
cat("ADSL saved to question_2_adam/adsl.csv\n")

cat("\n=== Script completed successfully ===\n")