# ==============================================================================
# Question 3 - Task 1: AE Summary Table using {gtsummary}
# ==============================================================================
# Description: Creates a summary table of treatment-emergent adverse events
#              (TEAEs) by System Organ Class and Preferred Term, stratified
#              by treatment group. Modeled after FDA Table 10.
# Input:       pharmaverseadam::adae, pharmaverseadam::adsl
# Output:      ae_summary_table.html (and .docx)
# References:  - FDA TLG Catalogue: https://pharmaverse.github.io/cardinal/
#              - {gtsummary} docs: https://www.danieldsjoberg.com/gtsummary/
# ==============================================================================

# --- Load Required Libraries --------------------------------------------------
.libPaths("~/R/library")
library(pharmaverseadam)
library(gtsummary)
library(dplyr)
library(gt)
library(cards)

# --- Step 1: Read and Prepare Input Data --------------------------------------
adae <- pharmaverseadam::adae
adsl <- pharmaverseadam::adsl

cat("=== ADAE dimensions ===\n")
cat("Rows:", nrow(adae), "| Columns:", ncol(adae), "\n")
cat("\n=== ADSL dimensions ===\n")
cat("Rows:", nrow(adsl), "| Columns:", ncol(adsl), "\n")

# Filter to treatment-emergent AEs only
adae_te <- adae %>%
  filter(TRTEMFL == "Y")

cat("\n=== Treatment-Emergent AEs ===\n")
cat("TEAE records:", nrow(adae_te), "\n")
cat("Unique subjects with TEAEs:", n_distinct(adae_te$USUBJID), "\n")

# Check treatment arms
cat("\n=== Treatment Arms (ACTARM) ===\n")
print(table(adsl$ACTARM, useNA = "ifany"))

# Remove screen failures from ADSL (denominator population)
# ACTARM must be a factor with the same levels as in adae_for_table
arm_levels <- c("Placebo", "Xanomeline High Dose", "Xanomeline Low Dose")
adsl_pop <- adsl %>%
  filter(!ACTARM %in% c("Screen Failure", "Not Assigned")) %>%
  mutate(ACTARM = factor(ACTARM, levels = arm_levels))

# --- Step 2: Build the Hierarchical AE Summary Table --------------------------
# The table shows SOC > Preferred Term, by treatment arm, with n (%)
# counting unique subjects per AE term.

# Approach: Build a subject-level dataset with one row per subject per SOC/AETERM
# combination, then use gtsummary::tbl_hierarchical() or manual approach.

# De-duplicate: keep one record per subject per SOC per AETERM
adae_dedup <- adae_te %>%
  distinct(USUBJID, AESOC, AETERM, .keep_all = TRUE)

# --- Method: Using tbl_hierarchical (gtsummary >= 2.0) ------------------------
# tbl_hierarchical creates nested SOC > AETERM tables automatically.
# If this function is not available in your version, see the fallback below.

# First, create overall TEAE summary row (subjects with any TEAE)
# We'll build the hierarchical table for SOC + AETERM

# Prepare data: need ACTARM as a factor for column ordering
adae_for_table <- adae_dedup %>%
  mutate(ACTARM = factor(ACTARM, levels = arm_levels))

# Build hierarchical table
ae_table <- adae_for_table %>%
  tbl_hierarchical(
    variables = c(AESOC, AETERM),
    by = ACTARM,
    denominator = adsl_pop,
    id = USUBJID,
    overall_row = TRUE,
    label = list(
      AESOC ~ "Primary System Organ Class",
      AETERM ~ "Reported Term for the Adverse Event"
    )
  ) %>%
  # Sort by descending overall frequency (gtsummary >= 2.0 API)
  sort_hierarchical(sort = "descending") %>%
  # Bold the SOC-level labels
  bold_labels() %>%
  # Update header
  modify_header(label ~ "**Primary System Organ Class
    Reported Term for the Adverse Event**") %>%
  modify_spanning_header(
    all_stat_cols() ~ "**Treatment Group**"
  )

# Print table to console
cat("\n=== AE Summary Table Preview ===\n")
print(ae_table)

# --- Step 3: Save Output Files ------------------------------------------------

# Save as HTML (output to question_3_tlg/ subfolder)
ae_table %>%
  as_gt() %>%
  gt::gtsave("question_3_tlg/ae_summary_table.html")
cat("\nTable saved to question_3_tlg/ae_summary_table.html\n")

# Note: .docx export requires the webshot2 package (not installed).
# HTML output is sufficient for review.

cat("\n=== Script 01 completed successfully ===\n")

# ==============================================================================
# FALLBACK: If tbl_hierarchical is not available in your gtsummary version,
# use the approach below instead. Uncomment and use if needed.
# ==============================================================================
#
# # Step A: Create an overall "Any TEAE" summary row
# overall_row <- adae_te %>%
#   distinct(USUBJID, ACTARM) %>%
#   mutate(AESOC = "Treatment Emergent AEs", AETERM = "Treatment Emergent AEs")
#
# # Step B: Create SOC-level summary
# soc_level <- adae_te %>%
#   distinct(USUBJID, ACTARM, AESOC) %>%
#   mutate(AETERM = AESOC)
#
# # Step C: Create AETERM-level (already de-duplicated)
# term_level <- adae_dedup %>%
#   select(USUBJID, ACTARM, AESOC, AETERM)
#
# # Step D: Combine and create the table using tbl_summary
# # For each level, count unique subjects by ACTARM
# # This requires more manual work but gives full control.
#
# # Simple approach: just SOC level with tbl_summary
# ae_simple <- adae_dedup %>%
#   mutate(ACTARM = factor(ACTARM, levels = c(
#     "Placebo", "Xanomeline High Dose", "Xanomeline Low Dose"
#   ))) %>%
#   select(USUBJID, ACTARM, AESOC) %>%
#   tbl_summary(
#     by = ACTARM,
#     include = AESOC,
#     statistic = all_categorical() ~ "{n} ({p}%)",
#     sort = all_categorical() ~ "frequency"
#   ) %>%
#   add_overall() %>%
#   bold_labels()
#
# ae_simple %>%
#   as_gt() %>%
#   gt::gtsave("ae_summary_table.html")