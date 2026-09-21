#' Check a generated narrative for truncated paragraphs
#'
#' Reads the paragraph text out of a \code{.docx} and reports any body
#' paragraph that does not end in terminal punctuation.
#'
#' @details
#' The narrative prompt caps paragraph length and instructs the model to
#' rewrite an over-long paragraph until it fits. A model can satisfy that
#' instruction by slicing the paragraph at the limit instead, which leaves a
#' sentence cut off mid-phrase at a word count that passes every check the
#' model itself performs. Three paragraphs shipped that way before anyone
#' noticed, each exactly at the limit.
#'
#' The check is deterministic and runs after the document is in hand, so it
#' does not depend on the model reporting its own compliance.
#'
#' Headings, title lines, and the figure list legitimately end without
#' punctuation, so only paragraphs of at least \code{min_words} are examined.
#' Real body paragraphs in this report run from roughly 50 to 150 words.
#'
#' @param docx_path Character. Path to the \code{.docx} to inspect.
#' @param min_words Integer. Paragraphs shorter than this are treated as
#'   headings or list items and skipped.
#'
#' @return Character vector of offending paragraphs, truncated for display.
#'   Empty when every body paragraph is well formed.
#'
#' @keywords internal
#' @noRd
.check_docx_paragraphs <- function(docx_path, min_words = 25L) {
  if (!file.exists(docx_path)) return(character(0))

  tmp <- tempfile("docxchk")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  ok <- tryCatch({
    utils::unzip(docx_path, files = "word/document.xml", exdir = tmp)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)

  xml_file <- file.path(tmp, "word", "document.xml")
  if (!ok || !file.exists(xml_file)) return(character(0))

  x <- paste(
    readLines(xml_file, warn = FALSE, encoding = "UTF-8"),
    collapse = ""
  )

  paras <- regmatches(
    x, gregexpr("<w:p[ >].*?</w:p>", x, perl = TRUE)
  )[[1L]]
  if (!length(paras)) return(character(0))

  unescape <- function(s) {
    s <- gsub("&lt;",   "<", s, fixed = TRUE)
    s <- gsub("&gt;",   ">", s, fixed = TRUE)
    s <- gsub("&quot;", '"', s, fixed = TRUE)
    s <- gsub("&apos;", "'", s, fixed = TRUE)
    gsub("&amp;", "&", s, fixed = TRUE)
  }

  txt <- vapply(paras, function(p) {
    runs <- regmatches(p, gregexpr("<w:t[^>]*>.*?</w:t>", p, perl = TRUE))[[1L]]
    if (!length(runs)) return("")
    unescape(paste0(gsub("^<w:t[^>]*>|</w:t>$", "", runs), collapse = ""))
  }, character(1), USE.NAMES = FALSE)

  txt <- trimws(txt)
  n_words <- lengths(strsplit(txt, "\\s+"))

  # Allow one closing quote after the stop, e.g. ... data."
  # perl = TRUE matters: under R's default TRE engine a backslash is not an
  # escape inside a bracket expression, so a "]" written there silently
  # changes what the class matches and every well-formed paragraph fails.
  well_formed <- grepl("[.!?][\"')”]?$", txt, perl = TRUE) |
    # A paragraph ending in a bare URL is complete, not truncated.
    grepl("https?://\\S+$", txt, perl = TRUE)

  bad <- which(n_words >= min_words & !well_formed)
  if (!length(bad)) return(character(0))

  vapply(bad, function(i) {
    sprintf("(%d words) ...%s", n_words[i],
            substr(txt[i], max(1L, nchar(txt[i]) - 60L), nchar(txt[i])))
  }, character(1))
}
