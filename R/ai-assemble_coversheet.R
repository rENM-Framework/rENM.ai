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
#' @importFrom officer body_set_default_section prop_section page_size page_mar
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

  # Colors, fonts, and sizes taken from the theme in python-docx's default
  # template, which is what the AI-written narrative renders in. That theme
  # sets majorFont (title and headings) to Calibri and minorFont (body) to
  # Cambria -- not the other way round, which is how this was first written,
  # so the coversheet came out serif-headed with sans body while the
  # narrative was sans-headed with serif body. The two pages open the same
  # report and are meant to be interchangeable front matter.
  title_fmt   <- officer::fp_text(color = "#17365D", font.size = 26,
                                  font.family = "Calibri")
  heading_fmt <- officer::fp_text(color = "#365F91", font.size = 14,
                                  bold = TRUE, font.family = "Calibri")
  body_fmt    <- officer::fp_text(color = "#000000", font.size = 11,
                                  font.family = "Cambria")

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
  list_par    <- officer::fp_par(text.align = "left",
                                 padding.bottom = 0, line_spacing = 1.15)

  # Same figure list and citation the narrative prompt requires verbatim, so
  # the two versions of this page read as interchangeable front matter, and
  # so .check_docx_fixed_text() compares a provider's copy against what this
  # page renders rather than against a second transcription of it.
  figures  <- .report_figures()
  citation <- .framework_citation()

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
    officer::ftext(.report_headings()[[1L]], heading_fmt), fp_p = heading_par
  ))
  # Set as a tight bulleted list rather than eight spaced body paragraphs.
  # On the provider path this list shares the narrative's final page with the
  # AI disclosure, the reproducibility block and the citation, and at body
  # spacing the eight gaps alone cost about five lines, enough to push the
  # closing timestamp onto a page of its own. The prompt asks for the same
  # treatment so both pages match.
  for (fig in figures) {
    doc <- officer::body_add_fpar(doc, officer::fpar(
      officer::ftext(paste0("\u2022  ", fig), body_fmt), fp_p = list_par
    ))
  }

  # Placed between the figure list and the citation, which is where the
  # narrative prompt puts it too: the citation and the closing timestamp
  # form a colophon, and substantive text does not belong between them.
  repro <- .reproducibility_statement(.run_seed(species_dir))
  doc <- officer::body_add_fpar(doc, officer::fpar(
    officer::ftext(repro$heading, heading_fmt), fp_p = heading_par
  ))
  for (para in repro$body) {
    doc <- officer::body_add_fpar(doc, officer::fpar(
      officer::ftext(para, body_fmt), fp_p = body_par
    ))
  }

  doc <- officer::body_add_fpar(doc, officer::fpar(
    officer::ftext(.report_headings()[[2L]], heading_fmt),
    fp_p = heading_par
  ))
  doc <- officer::body_add_fpar(doc, officer::fpar(
    officer::ftext(citation, body_fmt), fp_p = body_par
  ))
  doc <- officer::body_add_fpar(doc, officer::fpar(
    officer::ftext(sprintf("(rENM Framework - %s)", timestamp), body_fmt),
    fp_p = officer::fp_par(text.align = "left")
  ))

  # officer's default template is A4 with 1 inch margins; python-docx's is
  # US Letter with 1.25 inch sides, which is what the narrative comes back
  # as. assemble_final_report() normalizes page size with cpdf -scale-to-fit,
  # so the mismatch never produced a ragged report -- it scaled the A4
  # coversheet down by about six percent, which rendered its text a size
  # smaller than the same text on the narrative's pages. Match the narrative
  # instead, so nothing is scaled.
  doc <- officer::body_set_default_section(
    doc,
    officer::prop_section(
      page_size = officer::page_size(width = 8.5, height = 11,
                                     orient = "portrait"),
      page_margins = officer::page_mar(top = 1, bottom = 1,
                                       left = 1.25, right = 1.25)
    )
  )

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
