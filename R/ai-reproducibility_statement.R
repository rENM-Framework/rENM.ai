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
      "Range-wide figures reproduce closely across seeds. Per-state figures ",
      "for states holding few raster cells are less stable, and small ",
      "differences among them should not be read as differences in the ",
      "data. No uncertainty interval is reported."
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
