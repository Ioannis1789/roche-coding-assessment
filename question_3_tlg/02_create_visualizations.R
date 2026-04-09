# ==============================================================================
# Question 3 - Task 2: AE Visualizations using {ggplot2}
# ==============================================================================
# Description: Creates two plots for adverse events reporting:
#   Plot 1: AE severity distribution by treatment (stacked bar chart)
#   Plot 2: Top 10 most frequent AEs with 95% Clopper-Pearson CIs
# Input:       pharmaverseadam::adae, pharmaverseadam::adsl
# Output:      plot1_ae_severity.png, plot2_top10_ae.png
# References:  - ggplot2 docs: https://ggplot2.tidyverse.org/
# ==============================================================================

# --- Load Required Libraries --------------------------------------------------
.libPaths("~/R/library")
library(pharmaverseadam)
library(ggplot2)
library(dplyr)

# --- Step 1: Read and Prepare Input Data --------------------------------------
adae <- pharmaverseadam::adae
adsl <- pharmaverseadam::adsl

# Filter to treatment-emergent AEs
adae_te <- adae %>%
  filter(TRTEMFL == "Y")

# Define analysis population (exclude screen failures)
adsl_pop <- adsl %>%
  filter(!ACTARM %in% c("Screen Failure", "Not Assigned"))
n_pop <- nrow(adsl_pop)

cat("=== Population for Analysis ===\n")
cat("Total subjects (denominator):", n_pop, "\n")
cat("TEAE records:", nrow(adae_te), "\n")

# ==============================================================================
# PLOT 1: AE Severity Distribution by Treatment (Stacked Bar Chart)
# ==============================================================================
# Uses AESEV variable, grouped by ACTARM (treatment arm)

cat("\n=== Building Plot 1: AE Severity Distribution ===\n")
cat("AESEV levels:\n")
print(table(adae_te$AESEV, useNA = "ifany"))

# Prepare data - order severity levels and treatment arms
adae_sev <- adae_te %>%
  mutate(
    AESEV = factor(AESEV, levels = c("MILD", "MODERATE", "SEVERE")),
    ACTARM = factor(ACTARM, levels = c(
      "Placebo", "Xanomeline High Dose", "Xanomeline Low Dose"
    ))
  ) %>%
  filter(!is.na(AESEV), !is.na(ACTARM))

# Create stacked bar chart (matches sample output style)
plot1 <- ggplot(adae_sev, aes(x = ACTARM, fill = AESEV)) +
  geom_bar(position = "stack", width = 0.7) +
  scale_fill_manual(
    values = c(
      "MILD"     = "#F8766D",
      "MODERATE" = "#00BA38",
      "SEVERE"   = "#619CFF"
    ),
    name = "Severity/Intensity"
  ) +
  labs(
    title = "AE severity distribution by treatment",
    x = "Treatment Arm",
    y = "Count of AEs"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 14),
    axis.text.x = element_text(angle = 0, hjust = 0.5),
    legend.position = "right",
    panel.grid.major.x = element_blank()
  )

# Save Plot 1
ggsave(
  filename = "question_3_tlg/plot1_ae_severity.png",
  plot = plot1,
  width = 9, height = 6, dpi = 300, bg = "white"
)
cat("Plot 1 saved to plot1_ae_severity.png\n")
print(plot1)

# ==============================================================================
# PLOT 2: Top 10 Most Frequent AEs with 95% Clopper-Pearson CIs
# ==============================================================================
# Uses AETERM variable, calculates incidence per subject with exact binomial CI

cat("\n=== Building Plot 2: Top 10 AEs with 95% CI ===\n")

# Count unique subjects per AETERM (one record per subject per term)
ae_counts <- adae_te %>%
  distinct(USUBJID, AETERM) %>%
  count(AETERM, name = "ae_n") %>%
  arrange(desc(ae_n)) %>%
  head(10)

cat("Top 10 AEs by subject count:\n")
print(ae_counts)

# Calculate incidence proportion and 95% Clopper-Pearson exact CI
# binom.test() provides exact (Clopper-Pearson) confidence intervals
ae_top10 <- ae_counts %>%
  rowwise() %>%
  mutate(
    pct   = (ae_n / n_pop) * 100,
    lower = binom.test(ae_n, n_pop, conf.level = 0.95)$conf.int[1] * 100,
    upper = binom.test(ae_n, n_pop, conf.level = 0.95)$conf.int[2] * 100
  ) %>%
  ungroup() %>%
  # Order AETERMs by incidence for plot display
  mutate(AETERM = reorder(AETERM, pct))

cat("\nTop 10 AEs with 95% Clopper-Pearson CIs:\n")
ae_top10 %>%
  select(AETERM, ae_n, pct, lower, upper) %>%
  mutate(across(c(pct, lower, upper), ~ round(.x, 1))) %>%
  print()

# Create forest-style dot plot with horizontal error bars
plot2 <- ggplot(ae_top10, aes(x = pct, y = AETERM)) +
  geom_errorbar(
    aes(xmin = lower, xmax = upper),
    width = 0.25,
    linewidth = 0.6,
    color = "grey30",
    orientation = "y"
  ) +
  geom_point(size = 3.5, color = "black") +
  labs(
    title = "Top 10 Most Frequent Adverse Events",
    subtitle = paste0("n = ", n_pop, " subjects; 95% Clopper-Pearson CIs"),
    x = "Percentage of Patients (%)",
    y = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title    = element_text(hjust = 0.5, face = "bold", size = 14),
    plot.subtitle = element_text(hjust = 0.5, size = 11, color = "grey40"),
    panel.grid.major.y = element_blank(),
    panel.grid.minor   = element_blank(),
    axis.text.y  = element_text(size = 10)
  ) +
  scale_x_continuous(
    labels = function(x) paste0(x, "%"),
    expand = expansion(mult = c(0.01, 0.05))
  )

# Save Plot 2
ggsave(
  filename = "question_3_tlg/plot2_top10_ae.png",
  plot = plot2,
  width = 9, height = 6, dpi = 300, bg = "white"
)
cat("Plot 2 saved to plot2_top10_ae.png\n")
print(plot2)

cat("\n=== Script 02 completed successfully ===\n")