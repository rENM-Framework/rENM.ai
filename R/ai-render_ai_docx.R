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

  # -------------------------------------------------------------
  # 3. Check LibreOffice
  # -------------------------------------------------------------
  soffice <- Sys.which("soffice")
  if (!nzchar(soffice)) {
    stop(
      "LibreOffice 'soffice' not found on PATH.\n",
      "Install LibreOffice or ensure 'soffice' is available."
    )
  }

  # -------------------------------------------------------------
  # 4. Convert DOCX → PDF
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
