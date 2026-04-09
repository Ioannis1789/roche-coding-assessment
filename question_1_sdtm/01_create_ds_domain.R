# ==============================================================================
# Question 1: SDTM DS Domain Creation using {sdtm.oak}
# ==============================================================================
# Description: Creates an SDTM Disposition (DS) domain dataset from raw
#              clinical trial data using the {sdtm.oak} package.
# Input:       pharmaverseraw::ds_raw (raw disposition data)
# Output:      DS domain with variables: STUDYID, DOMAIN, USUBJID, DSSEQ,
#              DSTERM, DSDECOD, DSCAT, VISITNUM, VISIT, DSDTC, DSSTDTC, DSSTDY
# References:  - Pharmaverse AE example: https://pharmaverse.github.io/examples/sdtm/ae.html
#              - {sdtm.oak} docs: https://pharmaverse.github.io/sdtm.oak/
#              - CDISC SDTMIG v3.4 DS domain
# ==============================================================================

# --- Load Required Libraries --------------------------------------------------
.libPaths("~/R/library")  # ensure user library is on path
library(sdtm.oak)
library(pharmaverseraw)
library(pharmaversesdtm)
library(dplyr)

# --- Step 1: Read in Raw Data ------------------------------------------------
# Load the raw disposition dataset from {pharmaverseraw}
ds_raw <- pharmaverseraw::ds_raw

# Inspect the raw data structure (for development/debugging)
cat("=== ds_raw Structure ===\n")
str(ds_raw)
cat("\n=== ds_raw Column Names ===\n")
print(names(ds_raw))
cat("\n=== ds_raw First 10 Rows ===\n")
print(head(ds_raw, 10))

# Load the DM domain (needed for derive_study_day)
dm <- pharmaversesdtm::dm

# --- Step 2: Create oak_id_vars -----------------------------------------------
# Generate oak_id_vars which are required by sdtm.oak mapping functions.
# These variables (oak_id, raw_source, patient_number) help track the
# provenance of each mapped record back to the raw source.
ds_raw <- ds_raw %>%
  generate_oak_id_vars(
    pat_var = "PATNUM",
    raw_src = "ds_raw"
  )

cat("\n=== ds_raw after oak_id_vars ===\n")
print(head(ds_raw, 5))

# --- Step 3: Define Study Controlled Terminology ------------------------------
# Controlled terminology for the DS domain (codelist C66727 = Disposition Event)
# This maps raw collected values to CDISC standardized terms.
study_ct <- data.frame(
  stringsAsFactors = FALSE,
  codelist_code = c(
    "C66727", "C66727", "C66727", "C66727", "C66727",
    "C66727", "C66727", "C66727", "C66727", "C66727"
  ),
  term_code = c(
    "C41331", "C25250", "C28554", "C48226", "C48227",
    "C48250", "C142185", "C49628", "C49632", "C49634"
  ),
  term_value = c(
    "ADVERSE EVENT", "COMPLETED", "DEATH", "LACK OF EFFICACY",
    "LOST TO FOLLOW-UP", "PHYSICIAN DECISION", "PROTOCOL VIOLATION",
    "SCREEN FAILURE", "STUDY TERMINATED BY SPONSOR",
    "WITHDRAWAL BY SUBJECT"
  ),
  # IT.DSTERM = tools::toTitleCase(tolower(DSTERM)) — matches title-cased SDTM terms
  collected_value = c(
    "Adverse Event", "Completed", "Death", "Lack of Efficacy",
    "Lost to Follow-Up", "Physician Decision", "Protocol Violation",
    "Screen Failure", "Study Terminated by Sponsor",
    "Withdrawal by Subject"
  ),
  term_preferred_term = c(
    "AE", "Completed", "Died", NA, NA, NA, "Violation",
    "Failure to Meet Inclusion/Exclusion Criteria", NA, "Dropout"
  ),
  term_synonyms = c(
    "ADVERSE EVENT", "COMPLETE", "Death", NA, NA, NA, NA, NA, NA,
    "Discontinued Participation"
  )
)

cat("\n=== Study Controlled Terminology ===\n")
print(study_ct)

# --- Step 4: Map Topic Variable -----------------------------------------------
# DSTERM is the topic variable for the DS domain.
# It represents the verbatim disposition term collected on the CRF.
# We first check what the raw variable name is by inspecting ds_raw columns.
cat("\n=== Available raw variables for mapping ===\n")
print(names(ds_raw))

# Map DSTERM - the collected disposition term (topic variable)
# Raw variable: IT.DSTERM = tools::toTitleCase(tolower(DSTERM))
# e.g. "COMPLETED" -> "Completed", "ADVERSE EVENT" -> "Adverse Event"
ds <- assign_no_ct(
  raw_dat = ds_raw,
  raw_var = "IT.DSTERM",
  tgt_var = "DSTERM",
  id_vars = oak_id_vars()
)

cat("\n=== After mapping DSTERM (topic variable) ===\n")
print(head(ds, 5))

# --- Step 5: Map Qualifier and Timing Variables -------------------------------
# Map DSDECOD using controlled terminology (C66727)
# DSDECOD is the standardized/decoded disposition term
ds <- ds %>%
  assign_ct(
    raw_dat = ds_raw,
    raw_var = "IT.DSTERM",
    tgt_var = "DSDECOD",
    ct_spec = study_ct,
    ct_clst = "C66727",
    id_vars = oak_id_vars()
  )

# DSCAT is not collected on the CRF — all records from the DS aCRF are
# "DISPOSITION EVENT". Derive it as a constant using hardcode_ct().
ds <- ds %>%
  hardcode_ct(
    raw_dat = ds_raw,
    raw_var = "IT.DSTERM",
    tgt_var = "DSCAT",
    tgt_val = "DISPOSITION EVENT",
    id_vars = oak_id_vars()
  )

# Map DSSTDTC - Disposition Start Date/Time
# IT.DSSTDAT is stored as "mm-dd-yyyy" (format: %m-%d-%Y)
ds <- ds %>%
  assign_datetime(
    raw_dat = ds_raw,
    raw_var = "IT.DSSTDAT",
    tgt_var = "DSSTDTC",
    raw_fmt = "m-d-y",
    id_vars = oak_id_vars()
  )

# Map DSDTC - Date/Time of Collection
# DSDTCOL = date ("mm-dd-yyyy"), DSTMCOL = time ("HH:MM") — combine for full ISO 8601
ds <- ds %>%
  assign_datetime(
    raw_dat = ds_raw,
    raw_var = c("DSDTCOL", "DSTMCOL"),
    tgt_var = "DSDTC",
    raw_fmt = c("m-d-y", "H:M"),
    id_vars = oak_id_vars()
  )

# VISITNUM is not in ds_raw — omit it (no numeric visit number on DS CRF).
# VISIT maps from INSTANCE (the CRF page/visit label, e.g. "Informed Consent")
ds <- ds %>%
  assign_no_ct(
    raw_dat = ds_raw,
    raw_var = "INSTANCE",
    tgt_var = "VISIT",
    id_vars = oak_id_vars()
  )

cat("\n=== After mapping all qualifier/timing variables ===\n")
print(head(ds, 5))

# --- Step 6: Create SDTM Derived Variables ------------------------------------
# Derive STUDYID, DOMAIN, USUBJID, DSSEQ, and DSSTDY
ds <- ds %>%
  dplyr::mutate(
    STUDYID = ds_raw$STUDY[match(oak_id, ds_raw$oak_id)],
    DOMAIN  = "DS",
    USUBJID = paste0("01-", ds_raw$PATNUM[match(oak_id, ds_raw$oak_id)])
  ) %>%
  # Derive DSSEQ - sequence number within subject
  derive_seq(
    tgt_var = "DSSEQ",
    rec_vars = c("USUBJID", "DSTERM")
  ) %>%
  # Derive DSSTDY - Study Day of Disposition Start Date
  derive_study_day(
    sdtm_in = .,
    dm_domain = dm,
    tgdt = "DSSTDTC",
    refdt = "RFXSTDTC",
    study_day_var = "DSSTDY"
  )

# --- Step 7: Select and Order Final Variables ---------------------------------
# Select only the required DS domain variables in the correct order
# Note: VISITNUM excluded — not available in raw data
ds_final <- ds %>%
  select(
    STUDYID, DOMAIN, USUBJID, DSSEQ, DSTERM, DSDECOD,
    DSCAT, VISIT, DSDTC, DSSTDTC, DSSTDY
  )

# --- Step 8: Quality Checks --------------------------------------------------
cat("\n=== Final DS Domain Dataset ===\n")
print(ds_final)

cat("\n=== Dataset Dimensions ===\n")
cat("Rows:", nrow(ds_final), "| Columns:", ncol(ds_final), "\n")

cat("\n=== Variable Summary ===\n")
str(ds_final)

cat("\n=== Check for missing USUBJID ===\n")
cat("Missing USUBJID count:", sum(is.na(ds_final$USUBJID)), "\n")

cat("\n=== DSDECOD Distribution ===\n")
print(table(ds_final$DSDECOD, useNA = "ifany"))

cat("\n=== DSCAT Distribution ===\n")
print(table(ds_final$DSCAT, useNA = "ifany"))

# --- Step 9: Save Output Dataset ----------------------------------------------
# Save as RDS (native R format)
saveRDS(ds_final, file = "ds_domain.rds")
cat("\nDS domain saved to ds_domain.rds\n")

# Save as CSV for easy review
write.csv(ds_final, file = "ds_domain.csv", row.names = FALSE)
cat("DS domain saved to ds_domain.csv\n")

cat("\n=== Script completed successfully ===\n")