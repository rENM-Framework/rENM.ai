#' Statistical support statement for the centroid shift
#'
#' Returns the sentence or sentences that close the narrative's centroid
#' paragraph, stating which axes of the centroid's movement the Bayesian
#' regressions support.
#'
#' @details
#' Whether a credible interval excludes zero is a comparison of two numbers,
#' and R makes it here rather than asking a model to. A provider given the
#' latitude and longitude summaries reported a statistically supported
#' northward shift and, in the same paragraph, called the whole displacement
#' indistinguishable from no change. The prompt now carries this text as a
#' block to copy, and \code{render_ai_docx()} checks that it came back
#' verbatim, so the determination in every narrative matches the CSVs.
#'
#' An axis is supported when its credible interval lies wholly above or
#' wholly below zero. The direction named for a supported axis is the sign
#' of the posterior mean slope: positive latitude is northward, positive
#' longitude eastward. An unsupported axis is still named by the direction
#' of its measured component, and the sentence says the regression does not
#' distinguish that component from no change.
#'
#' @param species_dir Character. The species run directory,
#'   \code{<project_dir>/runs/<alpha_code>}.
#' @param code Character. Upper-case alpha code.
#'
#' @return Character scalar, or \code{NA} when either summary file is
#'   missing or unreadable.
#'
#' @keywords internal
#' @noRd
.centroid_support_statement <- function(species_dir, code) {
  read_axis <- function(axis) {
    f <- file.path(species_dir, "Trends", "centroids",
                   sprintf("%s-Centroids-%s-Summary.csv", code, axis))
    if (!file.exists(f)) return(NULL)
    d <- tryCatch(utils::read.csv(f), error = function(e) NULL)
    if (is.null(d) || !nrow(d) || !all(c("mean", "ci_low", "ci_high") %in% names(d))) {
      return(NULL)
    }
    list(mean = d$mean[[1L]],
         supported = d$ci_low[[1L]] > 0 || d$ci_high[[1L]] < 0)
  }
  lat <- read_axis("Latitude")
  lon <- read_axis("Longitude")
  if (is.null(lat) || is.null(lon)) return(NA_character_)

  ns <- if (lat$mean >= 0) "northward" else "southward"
  ew <- if (lon$mean >= 0) "eastward"  else "westward"

  if (lat$supported && lon$supported) {
    sprintf(paste0(
      "The credible intervals for latitude and longitude both exclude zero, ",
      "so the %s and %s components of the shift are statistically supported."),
      ns, ew)
  } else if (lat$supported) {
    sprintf(paste0(
      "The credible interval for latitude excludes zero, so the %s shift is ",
      "statistically supported. The interval for longitude includes zero, so ",
      "the regression does not distinguish the %s component from no change."),
      ns, ew)
  } else if (lon$supported) {
    sprintf(paste0(
      "The credible interval for longitude excludes zero, so the %s shift is ",
      "statistically supported. The interval for latitude includes zero, so ",
      "the regression does not distinguish the %s component from no change."),
      ew, ns)
  } else {
    paste0(
      "The credible intervals for latitude and longitude both include zero, ",
      "so the regression does not distinguish the displacement from no change.")
  }
}

#' Regions a narrative must name
#'
#' Reads the two Regions CSVs written by
#' \code{rENM.analysis::find_trend_percentages()} and returns, for each
#' layer, the regions at the low and the high end of the positive share.
#' A region within \code{tol} points of the extreme counts, so a near tie
#' (northwest 96.1, north 94.7) accepts either name.
#'
#' @param species_dir Character. The species run directory.
#' @param code Character. Upper-case alpha code.
#' @param tol Numeric. Points from the extreme within which a region counts.
#'
#' @return Named list keyed by layer, each a list with \code{low} and
#'   \code{high} character vectors of region names. Layers whose file is
#'   missing are omitted.
#'
#' @keywords internal
#' @noRd
.region_extremes <- function(species_dir, code, tol = 5) {
  out <- list()
  for (layer in c("Suitability-Trend", "Suitability-Change-Trend")) {
    f <- file.path(species_dir, "Trends", "suitability",
                   sprintf("%s-%s-Regions.csv", code, layer))
    if (!file.exists(f)) next
    d <- tryCatch(utils::read.csv(f), error = function(e) NULL)
    if (is.null(d) || !nrow(d)) next
    d <- d[!is.na(d$percent_positive), , drop = FALSE]
    if (!nrow(d)) next
    p <- d$percent_positive
    out[[layer]] <- list(
      low  = d$region[p <= min(p) + tol],
      high = d$region[p >= max(p) - tol]
    )
  }
  out
}
