#' Assemble GenAI suitability package for a species
#'
#' Collects suitability-trend rasters, summary tables, and species metadata for
#' a single species, then builds an AI-ready package together with a prompt
#' template and log entry.  The function locates the project root via
#' \code{rENM_project_dir()} and no longer relies on hard-coded paths.
#'
#' @details
#' This function is part of the rENM framework's processing pipeline
#' and operates within the project directory structure defined by
#' rENM_project_dir().
#'
#' \strong{Pipeline context}
#' \itemize{
#'   \item Copies pre-computed suitability rasters and tables into
#'         \code{suitability_package/}.
#'   \item Copies \code{\_species.csv} to a species-specific file and
#'         includes it in the package.
#'   \item Creates a \code{.zip} archive of the package contents.
#'   \item Copies the ChatGPT prompt template resolved via
#'         \code{system.file("chatgpt", "suitability_prompt.txt",
#'         package = "rENM.ai")} into the species \code{chatgpt/} directory.
#'   \item Appends a standardized processing-summary block to
#'         \code{\_log.txt}.
#'   \item Eliminates hard-coded home-directory paths by relying on
#'         \code{rENM_project_dir()}.
#' }
#'
#' \strong{Directory layout}
#' \itemize{
#'   \item \code{<project_root>/runs/<alpha_code>/Trends/suitability/}
#'   \item \code{<project_root>/runs/<alpha_code>/Summaries/chatgpt/}
#'   \item \code{<project_root>/data/_species.csv}
#' }
#'
#' \strong{Expected inputs}
#' \itemize{
#'   \item \code{<project_root>/runs/<alpha_code>/Trends/suitability/}
#'         \code{<alpha_code>-Suitability-Change-Trend.tif}
#'   \item \code{<project_root>/runs/<alpha_code>/Trends/suitability/}
#'         \code{<alpha_code>-Suitability-Trend-GAP-Range-Percentages.csv}
#'   \item \code{<project_root>/runs/<alpha_code>/Trends/suitability/}
#'         \code{<alpha_code>-Suitability-Trend-Percentages.csv}
#'   \item \code{<project_root>/runs/<alpha_code>/Trends/suitability/}
#'         \code{<alpha_code>-Suitability-Trend-State-Analysis-Hotspots-Stats.csv}
#'   \item \code{<project_root>/runs/<alpha_code>/Trends/suitability/}
#'         \code{<alpha_code>-Suitability-Trend-State-Analysis-Summary.csv}
#'   \item \code{<project_root>/runs/<alpha_code>/Trends/suitability/}
#'         \code{<alpha_code>-Suitability-Trend-State-Analysis.csv}
#'   \item \code{<project_root>/runs/<alpha_code>/Trends/suitability/}
#'         \code{<alpha_code>-Suitability-Trend.tif}
#'   \item \code{<project_root>/data/_species.csv}
#' }
#'
#' The shared species table is copied to
#' \code{<project_root>/runs/<alpha_code>/Trends/suitability/}
#' \code{<alpha_code>-Species-Information.csv} and included in the package.
#'
#' \strong{Outputs}
#' \itemize{
#'   \item Packaged files in
#'         \code{<project_root>/runs/<alpha_code>/Summaries/chatgpt/}
#'         \code{suitability_package/}
#'   \item Zip archive
#'         \code{<project_root>/runs/<alpha_code>/Summaries/chatgpt/}
#'         \code{suitability_package.zip}
#'   \item Prompt template copied beside the archive
#'   \item Updated species \code{\_log.txt}
#' }
#'
#' Missing inputs are reported with \code{warning()}.  The zip archive is only
#' created if at least one file is successfully copied.
#'
#' @param alpha_code Character. Four-letter species alpha code (e.g.,
#'   \code{"CASP"}).
#'
#' @return Named List (invisible).
#' \itemize{
#'   \item \code{alpha_code}            – input species code
#'   \item \code{pkg_dir}               – path to \code{suitability_package}
#'   \item \code{alpha_chatgpt_dir}     – path to species \code{chatgpt} folder
#'   \item \code{zip_path}              – path to created archive
#'   \item \code{prompt_path}           – path to copied prompt file
#'   \item \code{species_info_trends}   – trends-level species table
#'   \item \code{species_info_pkg}      – table inside the package
#'   \item \code{log_file}              – updated log file
#' }
#'
#' @importFrom utils zip
#'
#' @examples
#' \dontrun{
#' assemble_suitability_ai_package("CASP")
#' }
#'
#' @export
assemble_suitability_ai_package <- function(alpha_code) {
  # Start a timer for logging total elapsed time.
  start_time <- Sys.time()
  message("[assemble_suitability_ai_package] Starting for alpha code: ", alpha_code)

  # ---------------------------------------------------------------------------
  # Define core path roots (relative to project root)
  # ---------------------------------------------------------------------------
  proj_root      <- rENM_project_dir()
  runs_root      <- file.path(proj_root, "runs")
  resources_root <- file.path(proj_root, "resources")  # retained for backward compatibility
  data_root      <- file.path(proj_root, "data")

  # Species-specific suitability-trends directory:
  #   <project_root>/runs/<alpha_code>/Trends/suitability
  trends_dir <- file.path(runs_root, alpha_code, "Trends", "suitability")

  # Species-specific information table in Trends/suitability.
  species_info_trends <- file.path(
    trends_dir,
    sprintf("%s-Species-Information.csv", alpha_code)
  )

  # List of expected suitability-related files in Trends/suitability.
  # The species-information file is added after we ensure it exists.
  src_files <- c(
    file.path(trends_dir, sprintf("%s-Suitability-Change-Trend.tif",               alpha_code)),
    file.path(trends_dir, sprintf("%s-Suitability-Trend-GAP-Range-Percentages.csv", alpha_code)),
    file.path(trends_dir, sprintf("%s-Suitability-Trend-Percentages.csv",          alpha_code)),
    file.path(trends_dir, sprintf("%s-Suitability-Trend-State-Analysis-Hotspots-Stats.csv", alpha_code)),
    file.path(trends_dir, sprintf("%s-Suitability-Trend-State-Analysis-Summary.csv",        alpha_code)),
    file.path(trends_dir, sprintf("%s-Suitability-Trend-State-Analysis.csv",               alpha_code)),
    file.path(trends_dir, sprintf("%s-Suitability-Trend.tif",                     alpha_code)),
    species_info_trends
  )

  # ---------------------------------------------------------------------------
  # Species-specific ChatGPT directories
  # ---------------------------------------------------------------------------
  # Base ChatGPT summaries directory:
  #   <project_root>/runs/<alpha_code>/Summaries/chatgpt
  alpha_chatgpt_dir <- file.path(runs_root, alpha_code, "Summaries", "chatgpt")
  # Package subdirectory that will hold all AI-facing files:
  #   <project_root>/runs/<alpha_code>/Summaries/chatgpt/suitability_package
  pkg_dir <- file.path(alpha_chatgpt_dir, "suitability_package")

  # Create ChatGPT and package directories if they do not exist.
  if (!dir.exists(alpha_chatgpt_dir)) {
    dir.create(alpha_chatgpt_dir, recursive = TRUE, showWarnings = FALSE)
    message("[assemble_suitability_ai_package] Created directory: ", alpha_chatgpt_dir)
  }
  if (!dir.exists(pkg_dir)) {
    dir.create(pkg_dir, recursive = TRUE, showWarnings = FALSE)
    message("[assemble_suitability_ai_package] Created directory: ", pkg_dir)
  }

  # Path for the zip archive that will be created from pkg_dir contents.
  zip_path <- file.path(alpha_chatgpt_dir, "suitability_package.zip")

  # ---------------------------------------------------------------------------
  # Prompt template paths (now resolved from the installed rENM.ai package)
  # ---------------------------------------------------------------------------
  prompt_src  <- system.file(
    "chatgpt",
    "suitability_prompt.txt",
    package = "rENM.ai"
  )
  prompt_dest <- file.path(alpha_chatgpt_dir, "suitability_prompt.txt")

  # ---------------------------------------------------------------------------
  # Log file path (standard convention)
  # ---------------------------------------------------------------------------
  # Species log file:
  #   <project_root>/runs/<alpha_code>/_log.txt
  log_file <- file.path(runs_root, alpha_code, "_log.txt")

  # ---------------------------------------------------------------------------
  # (0) Ensure species-information file exists in Trends/suitability
  # ---------------------------------------------------------------------------
  message("[assemble_suitability_ai_package] Preparing species information file...")

  # Shared species-info table:
  #   <project_root>/data/_species.csv
  species_info_src <- file.path(data_root, "_species.csv")

  # Copy the shared species-info table into the species' Trends/suitability
  # directory with a species-specific name (overwrites if already present).
  if (!file.exists(species_info_src)) {
    warning("[assemble_suitability_ai_package] Species info source not found: ", species_info_src)
  } else {
    ok_species <- file.copy(
      from      = species_info_src,
      to        = species_info_trends,
      overwrite = TRUE
    )

    if (ok_species) {
      message("  - Species information copied to: ", species_info_trends)
    } else {
      warning(
        "[assemble_suitability_ai_package] Failed to copy species info to: ",
        species_info_trends
      )
    }
  }

  # ---------------------------------------------------------------------------
  # (1) Copy required files into species-specific suitability_package directory
  # ---------------------------------------------------------------------------
  message("[assemble_suitability_ai_package] Copying suitability files into package directory...")

  copied_files <- character(0)  # Track successfully copied files for zipping.

  for (src in src_files) {
    if (!file.exists(src)) {
      warning("[assemble_suitability_ai_package] Missing source file: ", src)
      next
    }

    dest <- file.path(pkg_dir, basename(src))
    ok <- file.copy(from = src, to = dest, overwrite = TRUE)

    if (ok) {
      message("  - Copied: ", basename(src))
      copied_files <- c(copied_files, dest)
    } else {
      warning("[assemble_suitability_ai_package] Failed to copy ", src, " to ", dest)
    }
  }

  if (length(copied_files) == 0) {
    warning("[assemble_suitability_ai_package] No files were copied; zip will not be created.")
  }

  # ---------------------------------------------------------------------------
  # (2) Create a .zip file with the files in suitability_package
  # ---------------------------------------------------------------------------
  if (length(copied_files) > 0) {
    message("[assemble_suitability_ai_package] Creating zip file: ", zip_path)

    old_wd <- getwd()
    on.exit(setwd(old_wd), add = TRUE)

    setwd(pkg_dir)
    utils::zip(
      zipfile = zip_path,
      files   = basename(copied_files)
    )

    if (file.exists(zip_path)) {
      message("[assemble_suitability_ai_package] Zip created successfully.")
    } else {
      warning(
        "[assemble_suitability_ai_package] Zip creation appears to have failed: ",
        zip_path
      )
    }
  }

  # ---------------------------------------------------------------------------
  # (3) Copy the suitability_prompt.txt template to the alpha ChatGPT directory
  # ---------------------------------------------------------------------------
  message("[assemble_suitability_ai_package] Copying suitability_prompt.txt template...")

  if (!nzchar(prompt_src) || !file.exists(prompt_src)) {
    warning("[assemble_suitability_ai_package] Prompt source not found: ", prompt_src)
  } else {
    ok_prompt <- file.copy(
      from      = prompt_src,
      to        = prompt_dest,
      overwrite = TRUE
    )

    if (ok_prompt) {
      message("  - Prompt copied to: ", prompt_dest)
    } else {
      warning("[assemble_suitability_ai_package] Failed to copy prompt to: ", prompt_dest)
    }
  }

  # ---------------------------------------------------------------------------
  # (4) Append standard processing summary block to _log.txt
  # ---------------------------------------------------------------------------
  end_time    <- Sys.time()
  elapsed_sec <- as.numeric(difftime(end_time, start_time, units = "secs"))

  message("[assemble_suitability_ai_package] Updating log file: ", log_file)

  species_info_pkg <- file.path(pkg_dir, basename(species_info_trends))

  outputs_saved <- c(
    pkg_dir,
    if (file.exists(zip_path))            zip_path            else NA_character_,
    if (file.exists(prompt_dest))         prompt_dest         else NA_character_,
    if (file.exists(species_info_trends)) species_info_trends else NA_character_,
    if (file.exists(species_info_pkg))    species_info_pkg    else NA_character_
  )
  outputs_saved <- outputs_saved[!is.na(outputs_saved)]

  log_block <- c(
    paste0(strrep("-", 72)),
    "Processing summary (assemble_suitability_ai_package)",
    sprintf("Timestamp: %s", format(end_time, "%Y-%m-%d %H:%M:%S")),
    sprintf("Alpha code: %s", alpha_code),
    "Raster source: Suitability trends and species information",
    "Total cells: NA",
    "Valid cells: NA",
    "Positive cells: NA",
    "Negative cells: NA",
    "Zero cells: NA",
    sprintf(
      "Outputs saved: %s",
      if (length(outputs_saved) > 0) paste(outputs_saved, collapse = "; ") else "None"
    ),
    sprintf("Total elapsed: %.3f secs", elapsed_sec),
    sprintf(
      "Output file: %s",
      if (file.exists(zip_path)) zip_path else "NA"
    ),
    ""
  )

  cat(paste0(log_block, "\n"), file = log_file, append = TRUE)

  message("[assemble_suitability_ai_package] Done for ", alpha_code, ".")

  invisible(list(
    alpha_code          = alpha_code,
    pkg_dir             = pkg_dir,
    alpha_chatgpt_dir   = alpha_chatgpt_dir,
    zip_path            = zip_path,
    prompt_path         = prompt_dest,
    species_info_trends = species_info_trends,
    species_info_pkg    = species_info_pkg,
    log_file            = log_file
  ))
}
