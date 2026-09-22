#' Paragraph text of a .docx, one string per paragraph
#'
#' Shared by the checks below so both read the document the same way.
#'
#' @keywords internal
#' @noRd
.docx_paragraph_text <- function(docx_path) {
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

  trimws(txt)
}


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
  txt <- .docx_paragraph_text(docx_path)
  if (!length(txt)) return(character(0))

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

#' Check a generated narrative for unsubstituted placeholders
#'
#' @details
#' The model assembles the narrative in Python and writes it with python-docx.
#' A string built with a brace placeholder but without the `f` prefix emits the
#' placeholder literally, and it lands in the document where a number should
#' be. Three of six reports carried one: `{neg_area} km2`, `{fmt(hot_int)}%`,
#' `{ring_phrase}`. Two of those stand in for figures, so the report is missing
#' data rather than merely reading oddly.
#'
#' Nothing in the prompt can prevent this reliably, since the model has no way
#' to see its own rendered output. Checking the document we received does not
#' depend on it noticing.
#'
#' @param docx_path Character. Path to the \code{.docx} to inspect.
#'
#' @return Character vector of the placeholders found, with a little
#'   surrounding text. Empty when the document is clean.
#'
#' @keywords internal
#' @noRd
.check_docx_placeholders <- function(docx_path) {
  txt <- .docx_paragraph_text(docx_path)
  if (!length(txt)) return(character(0))

  # Any braced token, plus the angle-bracket placeholders the prompt itself
  # uses, in case one survives substitution.
  pat <- "\\{[^{}\n]{1,60}\\}|<(alpha_code|model|timestamp)>"
  out <- character(0)
  for (t in txt) {
    m <- regmatches(t, gregexpr(pat, t, perl = TRUE))[[1L]]
    for (hit in m) {
      at <- regexpr(hit, t, fixed = TRUE)
      lo <- max(1L, at - 40L)
      hi <- min(nchar(t), at + attr(at, "match.length") + 30L)
      out <- c(out, sprintf("%s  in: ...%s...", hit, substr(t, lo, hi)))
    }
  }
  unique(out)
}

#' Check a generated narrative for known prose faults
#'
#' @details
#' Not a general judge of writing quality, which no regular expression can
#' be. This looks for the specific constructions the model has actually
#' produced, so a fault we have already seen cannot come back unnoticed:
#'
#' \itemize{
#'   \item a contrastive conjunction joining two statements that agree,
#'     "the interior is majority negative, while the ring is majority
#'     negative";
#'   \item "respectively" applied to a repeated word, "majority positive and
#'     positive, respectively";
#'   \item a signed difference, "a difference of -18.53 percentage points",
#'     which is ambiguous without knowing which way the subtraction ran and
#'     which varied between species.
#' }
#'
#' Warns rather than stops: unlike a missing figure, these leave the report
#' readable and every number correct.
#'
#' @param docx_path Character. Path to the \code{.docx} to inspect.
#'
#' @return Character vector describing each fault found, with context.
#'
#' @keywords internal
#' @noRd
.check_docx_prose <- function(docx_path) {
  txt <- .docx_paragraph_text(docx_path)
  if (!length(txt)) return(character(0))

  rules <- list(
    list(
      what = "contrastive conjunction joining agreeing statements",
      pat  = "majority (positive|negative)[^.]{0,60}?\\b(?:while|whereas)\\b[^.]{0,60}?majority \\1"
    ),
    list(
      what = "\"respectively\" applied to a repeated word",
      pat  = "\\b(\\w+) and \\1, respectively"
    ),
    list(
      what = "signed difference; use an unsigned magnitude and a direction",
      pat  = "difference of\\s*[−-][0-9]"
    )
  )

  out <- character(0)
  for (t in txt) {
    for (r in rules) {
      m <- regexpr(r$pat, t, perl = TRUE, ignore.case = TRUE)
      if (m[1] > 0) {
        lo <- max(1L, m[1] - 25L)
        hi <- min(nchar(t), m[1] + attr(m, "match.length") + 25L)
        out <- c(out, sprintf("%s: ...%s...", r$what, substr(t, lo, hi)))
      }
    }
  }
  unique(out)
}
