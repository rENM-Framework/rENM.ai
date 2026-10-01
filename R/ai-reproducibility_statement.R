#' Reproducibility statement for the report's opening page
#'
#' Returns the heading and body paragraphs of the REPRODUCIBILITY section
#' carried by every report, whether the opening page was written by a
#' provider or by \code{assemble_coversheet()}.
#'
#' @details
#' This text is generated here and reproduced verbatim everywhere it appears.
#' It is never composed by a language model. It makes claims about the
#' software's behavior -- how the seed is applied, what determinism depends
#' on, which figures are stable between realizations -- that a model cannot
#' check against anything it is given. A paraphrase would not read as a
#' stylistic variation but as a false statement about the pipeline, so
#' \code{submit_to_chatgpt()} and \code{submit_to_claude()} substitute this
#' text into the prompt as a block to be copied, and \code{render_ai_docx()}
#' verifies that what came back still contains it.
#'
#' The wording changes with the kind of analysis the report describes. A
#' single seeded run reports no uncertainty interval and says so. When the
#' multi-run tier lands, the same function returns the aggregate wording
#' instead, so both the coversheet and the provider prompt follow without
#' either being edited.
#'
#' @param seed Integer or \code{NA}. The seed the run was computed with. When
#'   \code{NA} the sentence names a fixed seed without giving its value,
#'   rather than asserting one that was not verified.
#'
#' @return A list with \code{heading} (character scalar) and \code{body}
#'   (character vector, one element per paragraph).
#'
#' @keywords internal
#' @noRd
.reproducibility_statement <- function(seed = NA_integer_) {

  seed_clause <- if (is.na(seed)) {
    "computed with a fixed random seed"
  } else {
    sprintf("computed with seed %s", format(seed, scientific = FALSE))
  }

  # Length is constrained, not merely a style choice. On the provider path
  # this block shares the narrative's final page with the AI disclosure, the
  # figure list and the citation, and that page is fixed boilerplate in every
  # run: overrunning it by one line pushes the closing timestamp onto a page
  # of its own. Measured against a rendered report, not estimated. Lengthen
  # this text only after re-checking that the last page still closes.
  # Last measured 2026-10-01 on the CASP, EAME and GRRO pilot pages through
  # LibreOffice: the provider page closes 29 pt above the bottom margin,
  # about two lines, with either provider's model name in the disclosure;
  # the coversheet closes with more to spare.
  #
  # The stability claims in the second paragraph rest on five seeded CASP
  # runs, land cells only: hot spot share of land 12.1 to 13.5 percent per
  # run, but only 0.8 percent of land a hot spot in all five (mean pairwise
  # Jaccard 0.21); mean between-run cell correlation 0.80 for the suitability
  # trend and 0.46 for the change trend; same-interval variable sets
  # overlapping at a mean Jaccard of 0.45. One species, so the wording stays
  # qualitative.
  body <- c(
    paste0(
      "This report presents one realization of a stochastic pipeline, ",
      seed_clause, ". Repeating the analysis with that seed, on the same ",
      "machine and the same R and package versions, reproduces these ",
      "figures exactly. A fixed seed makes a run repeatable; it does not ",
      "make any figure more certain, because it selects one draw from a ",
      "distribution the pipeline would otherwise sample."
    ),
    paste0(
      "Range-wide figures, including total hot spot area, reproduce closely ",
      "across seeds. Finer detail does not. Per-state figures for states ",
      "holding few raster cells are less stable, and small differences among ",
      "them should not be read as differences in the data. Hot spot ",
      "locations vary substantially between seeds, and the change trend is ",
      "less stable cell by cell than the suitability trend. Seeds can also ",
      "select different but correlated variables, so those named here are ",
      "one of several sets that fit about equally well. No uncertainty ",
      "interval is reported."
    )
  )

  list(heading = "REPRODUCIBILITY", body = body)
}

#' Recover the seed a run was computed with
#'
#' Reads the \code{Seed used} lines that \code{screen_by_convergence2()}
#' writes to the run log, one per temporal bin. Returns the value only when
#' every line agrees, so a log holding runs at different seeds yields
#' \code{NA} and the statement omits the number rather than picking one.
#'
#' @param species_dir Character. The run directory, \code{runs/<alpha_code>}.
#'
#' @return Integer scalar, or \code{NA_integer_} if no unambiguous value.
#'
#' @keywords internal
#' @noRd
.run_seed <- function(species_dir) {
  log_path <- file.path(species_dir, "_log.txt")
  if (!file.exists(log_path)) return(NA_integer_)

  lines <- tryCatch(readLines(log_path, warn = FALSE),
                    error = function(e) character(0))
  hits <- grep("^Seed used\\s*:", lines, value = TRUE)
  if (!length(hits)) return(NA_integer_)

  vals <- suppressWarnings(as.integer(trimws(sub("^Seed used\\s*:", "", hits))))
  vals <- vals[!is.na(vals)]
  if (!length(vals) || length(unique(vals)) != 1L) return(NA_integer_)

  vals[[1L]]
}

#' The figure list carried on every report's opening page
#'
#' @details
#' One source for the eight entries, used by \code{assemble_coversheet()} to
#' render them and by \code{.check_docx_fixed_text()} to verify a provider
#' reproduced them. The prompt carries the same list as literal text; that
#' copy is what the check exists to police.
#'
#' @return Character vector of eight figure names.
#'
#' @keywords internal
#' @noRd
.report_figures <- function() {
  c(
    "Climatic Suitability Time Series",
    "Range Time Series",
    "Climatic Suitability Trends",
    "State-Level Suitability Trend and HotSpot Summary",
    "Climatic Suitability Trend with Centroid Shift",
    "Variable Contribution Trends",
    "Predictor Variable Trends",
    "rENM Framework MERRA Variables"
  )
}

#' The framework citation carried on every report's opening page
#'
#' @return Character scalar.
#'
#' @keywords internal
#' @noRd
.framework_citation <- function() {
  paste0(
    "Schnase, John L., Mark L. Carroll, Paul M. Montesano, and Virginia A. ",
    "Seamster. \"The rENM Framework: A Modular System for Reconstructing ",
    "and Analyzing Long-Term Ecological Niche Dynamics.\" Preprint, ",
    "bioRxiv, August 7, 2026. https://doi.org/10.64898/2026.08.06.741224."
  )
}

#' Headings that must appear exactly on the opening page
#'
#' @details
#' \code{"AI-ASSISTED INTERPRETATION"} is provider-only; the coversheet has
#' no such section. It is therefore checked only when the document already
#' contains a paragraph beginning with it, which keeps one check correct for
#' both paths without needing to be told which one produced the file.
#'
#' @return Character vector.
#'
#' @keywords internal
#' @noRd
.report_headings <- function() {
  c("INCLUDED FIGURES",
    "For additional information about the rENM Framework, see:")
}
