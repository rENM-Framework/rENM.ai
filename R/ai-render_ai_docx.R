#' Render GenAI DOCX report to PDF
#'
#' Converts a species-specific DOCX report into PDF and appends a processing
#' summary to the run log.
#'
#' @details
#' \strong{Inputs}
#' \itemize{
#'   \item One DOCX file per species located at
#'     \code{<rENM_project_dir()>/runs/<alpha_code>/Summaries/pages/}
#'     \code{<alpha_code>-Suitability-Trend-Analysis.docx}
#' }
#'
#' \strong{Outputs}
#' \itemize{
#'   \item A PDF written to the same directory:
#'     \code{<alpha_code>-Suitability-Trend-Analysis.pdf}
#'   \item A multi-line processing summary appended to
#'     \code{<rENM_project_dir()>/runs/<alpha_code>/_log.txt}
#' }
#'
#' \strong{Methods}
#' \itemize{
#'   \item Conversion uses LibreOffice \code{soffice} in headless mode.
#'   \item File sizes and time stamps are recorded for auditing.
#' }
#'
#' @param alpha_code Character. Species alpha code, for example \code{"CASP"}.
#' @param verbose Logical. If \code{TRUE} (default), prints diagnostic messages.
#'
#' @return Character. Invisibly returns the path to the generated PDF.\cr
#' Side effects:
#' \itemize{
#'   \item Writes a PDF file alongside the source DOCX.
#'   \item Appends a formatted record to the species-level \code{_log.txt}.
#' }
#'
#' @examples
#' \dontrun{
#' # Convert the Cassin's Sparrow report and view the resulting PDF path
#' pdf_path <- render_ai_docx("CASP")
#' }
#'
#' @export
render_ai_docx <- function(alpha_code, verbose = TRUE) {

  # -------------------------------------------------------------
  # 1. Normalize
  # -------------------------------------------------------------
  code <- toupper(alpha_code)

  project_dir <- rENM_project_dir()
  species_dir <- file.path(project_dir, "runs", code)
  pages_dir   <- file.path(species_dir, "Summaries", "pages")

  docx_path <- file.path(
    pages_dir,
    sprintf("%s-Suitability-Trend-Analysis.docx", code)
  )
  pdf_path <- file.path(
    pages_dir,
    sprintf("%s-Suitability-Trend-Analysis.pdf", code)
  )

  # -------------------------------------------------------------
  # 2. Sanity checks
  # -------------------------------------------------------------
  if (!dir.exists(species_dir)) {
    stop(sprintf("Species directory not found:\n  %s", species_dir))
  }
  if (!file.exists(docx_path)) {
    stop(sprintf("DOCX file not found:\n  %s", docx_path))
  }

  # The model can satisfy the prompt's word cap by slicing a paragraph at the
  # limit rather than rewriting it, which leaves a sentence cut off at a word
  # count that passes every check the model runs on itself. Checking the
  # document we actually received does not depend on it reporting honestly.
  # A brace placeholder reaches the document when the model builds a string
  # in Python without the `f` prefix. Two of the four seen stood in for
  # figures, so the report was missing data rather than merely reading oddly.
  # The model cannot see its own rendered output, so only this check can
  # catch it.
  # This stops rather than warns. Where a placeholder stands in for a number
  # the report is missing data, and in an unattended batch a warning scrolls
  # past: that is how three of six reports shipped with one. Truncation below
  # only warns, because the report is still readable and complete.
  placeholders <- .check_docx_placeholders(docx_path)
  if (length(placeholders)) {
    stop(
      "Narrative for ", code, " contains ", length(placeholders),
      " unsubstituted placeholder(s). Where these stand in for a number the",
      " report is missing data:\n",
      paste0("  ", placeholders, collapse = "\n"),
      "\nThe .docx is on disk but no PDF was produced. Re-run",
      " submit_to_chatgpt(\"", code, "\") to regenerate the narrative.",
      call. = FALSE
    )
  }

  # The headings, figure list, reproducibility block and citation are
  # supplied to the model as text to copy, not to write. Compared by
  # equality rather than containment: a model returned all twelve with a
  # trailing period added, which a containment test accepts. Stops, like the
  # placeholder check and for the same reason -- a report asserting the
  # wrong thing about its own reproducibility, or reading "see:.", is worse
  # than a report without an opening page. The coversheet path builds these
  # from the same helpers and cannot fail this.
  fixed_faults <- .check_docx_fixed_text(docx_path, .run_seed(species_dir))
  if (length(fixed_faults)) {
    stop(
      "Narrative for ", code, " did not reproduce ", length(fixed_faults),
      " supplied block(s) verbatim:\n",
      paste0("  ", fixed_faults, collapse = "\n"),
      "\nThe .docx is on disk but no PDF was produced. Re-run",
      " submit_to_chatgpt(\"", code, "\") to regenerate the narrative.",
      call. = FALSE
    )
  }

  # Known prose faults, not a general quality judgement. Warns: the report
  # stays readable and every figure is right.
  prose <- .check_docx_prose(docx_path)
  if (length(prose)) {
    warning(
      "Narrative for ", code, " has ", length(prose),
      " prose fault(s):\n",
      paste0("  ", prose, collapse = "\n"),
      "\nRe-run submit_to_chatgpt() if the wording matters.",
      call. = FALSE
    )
  }

  truncated <- .check_docx_paragraphs(docx_path)
  if (length(truncated)) {
    warning(
      "Narrative for ", code, " has ", length(truncated),
      " paragraph(s) ending without terminal punctuation, which usually",
      " means the text was truncated to hit a word limit:\n",
      paste0("  ", truncated, collapse = "\n"),
      "\nThe PDF is still rendered. Re-run submit_to_chatgpt() to regenerate.",
      call. = FALSE
    )
  }

  # -------------------------------------------------------------
  # 3. Check LibreOffice
  # -------------------------------------------------------------
  soffice <- Sys.which("soffice")
  if (!nzchar(soffice)) {
    # Sys.which() only searches PATH. On macOS, LibreOffice installs to
    # /Applications and soffice is not on PATH unless the user added it.
    # Check common fixed locations before giving up.
    candidates <- c(
      "/Applications/LibreOffice.app/Contents/MacOS/soffice",  # macOS standard
      "/usr/bin/soffice",                                        # Linux distro package
      "/usr/local/bin/soffice",                                  # Linux local install
      "/opt/libreoffice/program/soffice",                        # Linux flatpak / custom
      "/snap/bin/libreoffice"                                    # Linux snap
    )
    hit <- Filter(file.exists, candidates)
    if (length(hit)) soffice <- hit[[1L]]
  }
  if (!nzchar(soffice)) {
    stop(
      "LibreOffice 'soffice' not found on PATH or in common install locations.\n",
      "Install LibreOffice from https://www.libreoffice.org, then either:\n",
      "  (a) add it to your PATH, or\n",
      "  (b) on macOS run once in Terminal:\n",
      "      sudo ln -s /Applications/LibreOffice.app/Contents/MacOS/soffice",
      " /usr/local/bin/soffice"
    )
  }

  # -------------------------------------------------------------
  # 4. Convert DOCX to PDF
  # -------------------------------------------------------------
  if (verbose) {
    message("[render_ai_docx] Converting DOCX to PDF:")
    message("  Input:  ", docx_path)
    message("  Output: ", pdf_path)
  }

  cmd <- sprintf(
    "%s --headless --convert-to pdf %s --outdir %s",
    shQuote(soffice),
    shQuote(docx_path),
    shQuote(pages_dir)
  )

  status <- system(cmd, ignore.stdout = !verbose, ignore.stderr = !verbose)

  if (status != 0 || !file.exists(pdf_path)) {
    stop(
      "[render_ai_docx] LibreOffice failed to convert DOCX to PDF.\n",
      "  Command was:\n  ", cmd
    )
  }

  if (verbose) {
    message("[render_ai_docx] Conversion complete: ", pdf_path)
  }

  # -------------------------------------------------------------
  # 5. Prepare log entry
  # -------------------------------------------------------------
  log_path <- file.path(species_dir, "_log.txt")

  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")

  size_docx <- file.info(docx_path)$size
  size_pdf  <- file.info(pdf_path)$size

  size_docx_fmt <- if (!is.na(size_docx)) format(size_docx, big.mark = ",") else "NA"
  size_pdf_fmt  <- if (!is.na(size_pdf )) format(size_pdf, big.mark = ",") else "NA"

  log_text <- c(
    "",
    "------------------------------------------------------------------------",
    " Processing summary (render_ai_docx)",
    sprintf(" Timestamp:        %s", timestamp),
    sprintf(" Alpha code:       %s", code),
    sprintf(" DOCX input:       %s", docx_path),
    sprintf(" DOCX size:        %s bytes", size_docx_fmt),
    sprintf(" PDF output:       %s", pdf_path),
    sprintf(" PDF size:         %s bytes", size_pdf_fmt),
    " Status:           Complete"
  )

  # -------------------------------------------------------------
  # 6. Write to _log.txt
  # -------------------------------------------------------------
  write(log_text, file = log_path, append = TRUE)

  if (verbose) {
    message("[render_ai_docx] Log entry appended to: ", log_path)
  }

  invisible(pdf_path)
}
