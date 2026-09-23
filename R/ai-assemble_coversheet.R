#' Build a coversheet in place of the AI narrative page
#'
#' Produces the same \code{<alpha_code>-Suitability-Trend-Analysis.docx} /
#' \code{.pdf} pair that \code{\link{submit_to_chatgpt}} /
#' \code{\link{submit_to_claude}} and \code{\link{render_ai_docx}} produce,
#' but with no call to a language model. The page carries only the title
#' block, the list of figures included elsewhere in the report, the
#' framework citation, and a timestamp.
#'
#' @details
#' Used in the pipeline in two cases: when \code{rENM()} is called with
#' \code{ai = NULL}, and when a call to \code{submit_to_chatgpt()} or
#' \code{submit_to_claude()} fails, so the final report still has a title
#' page even though it carries no generated interpretation.
#'
#' \strong{Matching the AI narrative's appearance}
#'
#' \code{submit_to_chatgpt()} and \code{submit_to_claude()} both instruct the
#' model to build the document with python-docx, which defaults to the
#' "Office" theme (Cambria headings, Calibri body, the 17365D/365F91/4F81BD
#' blues). This function reproduces those colors, fonts, and sizes directly
#' via \code{officer::fp_text()} / \code{officer::fp_par()} rather than named
#' Word styles, so a run without AI assistance produces a cover page that
#' looks the same as one with it.
#'
#' \strong{Directory layout}
#' \preformatted{
#' <project_dir>/runs/<alpha_code>/Summaries/pages/
#'     <alpha_code>-Suitability-Trend-Analysis.docx
#' }
#'
#' The caller is expected to run \code{\link{render_ai_docx}} afterward to
#' produce the matching PDF, exactly as it does for the AI-written version.
#'
#' @param alpha_code Character. Four-letter species alpha code (e.g.,
#'   \code{"CASP"}).
#'
#' @return Character. Invisibly returns the path to the written \code{.docx}.
#'
#' @importFrom officer read_docx fp_text fp_par fp_border fpar ftext body_add_fpar
#'
#' @examples
#' \dontrun{
#' assemble_coversheet("CASP")
#' render_ai_docx("CASP")
#' }
#'
#' @export
assemble_coversheet <- function(alpha_code) {

  if (!requireNamespace("officer", quietly = TRUE)) {
    stop("Package 'officer' is required but not installed.", call. = FALSE)
  }

  alpha_code <- toupper(alpha_code)

  common_name <- get_species_info(alpha_code)$COMMON.NAME[[1L]]

  project_dir <- rENM_project_dir()
  species_dir <- file.path(project_dir, "runs", alpha_code)
  out_dir     <- file.path(species_dir, "Summaries", "pages")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  docx_path <- file.path(
    out_dir, sprintf("%s-Suitability-Trend-Analysis.docx", alpha_code)
  )

  # Colors, fonts, and sizes lifted from the "Office" theme python-docx uses
  # by default, which is what the AI-written narrative renders in.
  title_fmt   <- officer::fp_text(color = "#17365D", font.size = 26,
                                  font.family = "Cambria")
  heading_fmt <- officer::fp_text(color = "#365F91", font.size = 14,
                                  bold = TRUE, font.family = "Cambria")
  body_fmt    <- officer::fp_text(color = "#000000", font.size = 11,
                                  font.family = "Calibri")

  title_par <- officer::fp_par(text.align = "left", padding.bottom = 0)
  # The rule under the title is a bottom border on the last title line,
  # matching how python-docx's built-in "Title" style draws it.
  title_par_ruled <- officer::fp_par(
    text.align = "left", padding.bottom = 15,
    border.bottom = officer::fp_border(color = "#4F81BD", width = 1)
  )
  heading_par <- officer::fp_par(text.align = "left",
                                 padding.top = 18, padding.bottom = 6)
  body_par    <- officer::fp_par(text.align = "left",
                                 padding.bottom = 10, line_spacing = 1.15)

  # Same figure list and citation the narrative prompt requires verbatim, so
  # the two versions of this page read as interchangeable front matter.
  figures <- c(
    "Climatic Suitability Time Series",
    "Range Time Series",
    "Climatic Suitability Trends",
    "State-Level Suitability Trend and HotSpot Summary",
    "Climatic Suitability Trend with Centroid Shift",
    "Variable Contribution Trends",
    "Predictor Variable Trends",
    "rENM Framework MERRA Variables"
  )

  citation <- paste0(
    "Schnase, John L., Mark L. Carroll, Paul M. Montesano, and Virginia A. ",
    "Seamster. \"The rENM Framework: A Modular System for Reconstructing ",
    "and Analyzing Long-Term Ecological Niche Dynamics.\" Preprint, ",
    "bioRxiv, August 7, 2026. https://doi.org/10.64898/2026.08.06.741224."
  )

  # Same substitution submit_to_chatgpt()/submit_to_claude() apply to the
  # <timestamp> placeholder, so the closing line reads identically either way.
  timestamp <- sub("^0", "", format(Sys.time(), "%d %B %Y - %H:%M %Z"))

  doc <- officer::read_docx()

  doc <- officer::body_add_fpar(doc, officer::fpar(
    officer::ftext("Climatic Suitability Trend Analysis", title_fmt),
    fp_p = title_par
  ))
  doc <- officer::body_add_fpar(doc, officer::fpar(
    officer::ftext(sprintf("for %s (%s)", common_name, alpha_code), title_fmt),
    fp_p = title_par
  ))
  doc <- officer::body_add_fpar(doc, officer::fpar(
    officer::ftext("1980\u20132024", title_fmt),
    fp_p = title_par_ruled
  ))

  doc <- officer::body_add_fpar(doc, officer::fpar(
    officer::ftext("INCLUDED FIGURES", heading_fmt), fp_p = heading_par
  ))
  for (fig in figures) {
    doc <- officer::body_add_fpar(doc, officer::fpar(
      officer::ftext(fig, body_fmt), fp_p = body_par
    ))
  }

  doc <- officer::body_add_fpar(doc, officer::fpar(
    officer::ftext(
      "For additional information about the rENM Framework, see:",
      heading_fmt
    ),
    fp_p = heading_par
  ))
  doc <- officer::body_add_fpar(doc, officer::fpar(
    officer::ftext(citation, body_fmt), fp_p = body_par
  ))
  doc <- officer::body_add_fpar(doc, officer::fpar(
    officer::ftext(sprintf("(rENM Framework - %s)", timestamp), body_fmt),
    fp_p = officer::fp_par(text.align = "left")
  ))

  print(doc, target = docx_path)

  log_path <- file.path(species_dir, "_log.txt")
  dir.create(dirname(log_path), recursive = TRUE, showWarnings = FALSE)

  log_lines <- c(
    "", strrep("-", 72L),
    "Processing summary (assemble_coversheet)",
    sprintf("Timestamp       : %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    sprintf("Alpha code      : %s", alpha_code),
    sprintf("DOCX written    : %s", docx_path)
  )
  write(log_lines, file = log_path, append = TRUE)

  invisible(docx_path)
}
