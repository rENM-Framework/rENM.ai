#' Assemble GenAI suitability package for a species
#'
#' Collects selected suitability-trend rasters, summary tables, and species
#' metadata for a single species, then builds an AI-ready package together
#' with a prompt template and log entry.  The function locates the project root via
#' \code{rENM_project_dir()} and no longer relies on hard-coded paths.
#'
#' @details
#' This function is part of the rENM framework's processing pipeline
#' and operates within the project directory structure defined by
#' rENM_project_dir().
#'
#' \strong{Key update}
#' \itemize{
#'   \item Adds flexible file selection via \code{files}.
#'   \item All files are drawn from subdirectories under \code{Trends/}.
#'   \item Users must explicitly specify subdirectories (e.g.,
#'         \code{"suitability/Suitability-Trend.tif"} or
#'         \code{"centroids/Bioclimatic-Velocity.csv"}).
#' }
#'
#' \strong{Pipeline context}
#' \itemize{
#'   \item Copies selected suitability rasters and tables into
#'         \code{suitability_package/}.
#'   \item Copies \code{\_species.csv} to a species-specific file and
#'         includes it in the package.
#'   \item Creates a \code{.zip} archive of the package contents.
#'   \item Copies the ChatGPT prompt template resolved via
#'         \code{system.file("chatgpt", "suitability_prompt.txt",
#'         package = "rENM.ai")} into the species \code{chatgpt/} directory.
#'   \item Appends a standardized processing-summary block to
#'         \code{\_log.txt}.
#' }
#'
#' @param alpha_code Character. Four-letter species alpha code (e.g.,
#'   \code{"CASP"}).
#' @param files Character vector. File paths (without alpha_code prefix)
#'   identifying which outputs to include in the AI package. All entries
#'   must include a subdirectory relative to \code{Trends/}, for example:
#'   \code{"suitability/Suitability-Trend.tif"} or
#'   \code{"centroids/Bioclimatic-Velocity.csv"}.
#'
#'   Each file will be resolved as:
#'   \code{<project_root>/runs/<alpha_code>/Trends/<subdir>/<alpha_code>-<filename>}
#'
#'   Defaults to a minimal core set.
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
#' assemble_ai_package("CASP")
#' }
#'
#' @export
assemble_ai_package <- function(
    alpha_code,
    files = c(
      "centroids/Bioclimatic-Velocity.csv",
      "centroids/Centroids-Latitude-Summary.csv",
      "centroids/Centroids-Longitude-Summary.csv",
      "suitability/Suitability-Change-Trend.tif",
      "suitability/Suitability-Trend-State-Analysis-Summary.csv",
      "suitability/Suitability-Trend.tif",
      "suitability/Species-Information.csv",
      "variables/Variable-Contributions-BR-Stats.csv"
    )
) {
  # Start a timer for logging total elapsed time.
  start_time <- Sys.time()
  message("[assemble_ai_package] Starting for alpha code: ", alpha_code)

  # ---------------------------------------------------------------------------
  # Define core path roots (relative to project root)
  # ---------------------------------------------------------------------------
  proj_root      <- rENM_project_dir()
  runs_root      <- file.path(proj_root, "runs")
  resources_root <- file.path(proj_root, "resources")  # retained for backward compatibility
  data_root      <- file.path(proj_root, "data")

  # Species-specific suitability-trends directory
  trends_dir <- file.path(runs_root, alpha_code, "Trends", "suitability")

  # Species-specific information table
  species_info_trends <- file.path(
    trends_dir,
    sprintf("%s-Species-Information.csv", alpha_code)
  )

  # ---------------------------------------------------------------------------
  # Build source file list using required subpaths under Trends/
  # ---------------------------------------------------------------------------
  files <- as.character(files)

  if (any(!grepl("/", files, fixed = TRUE))) {
    stop("[assemble_ai_package] All entries in 'files' must include a subdirectory (e.g., 'suitability/file.tif').")
  }

  src_files <- vapply(files, function(f) {
    file.path(
      runs_root,
      alpha_code,
      "Trends",
      dirname(f),
      sprintf("%s-%s", alpha_code, basename(f))
    )
  }, character(1), USE.NAMES = FALSE)

  # Ensure species info path is included
  if (!species_info_trends %in% src_files) {
    src_files <- c(src_files, species_info_trends)
  }

  message("[assemble_ai_package] Files requested:")
  message(paste("  -", basename(src_files), collapse = "\n"))

  # ---------------------------------------------------------------------------
  # ChatGPT directories
  # ---------------------------------------------------------------------------
  alpha_chatgpt_dir <- file.path(runs_root, alpha_code, "Summaries", "chatgpt")
  pkg_dir <- file.path(alpha_chatgpt_dir, "suitability_package")

  if (!dir.exists(alpha_chatgpt_dir)) {
    dir.create(alpha_chatgpt_dir, recursive = TRUE, showWarnings = FALSE)
    message("[assemble_ai_package] Created directory: ", alpha_chatgpt_dir)
  }
  if (!dir.exists(pkg_dir)) {
    dir.create(pkg_dir, recursive = TRUE, showWarnings = FALSE)
    message("[assemble_ai_package] Created directory: ", pkg_dir)
  }

  zip_path <- file.path(alpha_chatgpt_dir, "suitability_package.zip")

  # ---------------------------------------------------------------------------
  # Prompt template paths
  # ---------------------------------------------------------------------------
  prompt_src  <- system.file(
    "chatgpt",
    "suitability_prompt.txt",
    package = "rENM.dev"   # this need to point to correct package
  )
  prompt_dest <- file.path(alpha_chatgpt_dir, "suitability_prompt.txt")

  # ---------------------------------------------------------------------------
  # Log file path
  # ---------------------------------------------------------------------------
  log_file <- file.path(runs_root, alpha_code, "_log.txt")

  # ---------------------------------------------------------------------------
  # Ensure species-information file exists
  # ---------------------------------------------------------------------------
  message("[assemble_ai_package] Preparing species information file...")

  species_info_src <- file.path(data_root, "_species.csv")

  if (!file.exists(species_info_src)) {
    warning("[assemble_ai_package] Species info source not found: ", species_info_src)
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
        "[assemble_ai_package] Failed to copy species info to: ",
        species_info_trends
      )
    }
  }

  # ---------------------------------------------------------------------------
  # Copy files into package directory
  # ---------------------------------------------------------------------------
  message("[assemble_ai_package] Copying selected files into package directory...")

  copied_files <- character(0)

  for (src in src_files) {
    if (!file.exists(src)) {
      warning("[assemble_ai_package] Missing source file: ", src)
      next
    }

    dest <- file.path(pkg_dir, basename(src))
    ok <- file.copy(from = src, to = dest, overwrite = TRUE)

    if (ok) {
      message("  - Copied: ", basename(src))
      copied_files <- c(copied_files, dest)
    } else {
      warning("[assemble_ai_package] Failed to copy ", src, " to ", dest)
    }
  }

  if (length(copied_files) == 0) {
    warning("[assemble_ai_package] No files were copied; zip will not be created.")
  }

  # ---------------------------------------------------------------------------
  # Create zip archive
  # ---------------------------------------------------------------------------
  if (length(copied_files) > 0) {
    message("[assemble_ai_package] Creating zip file: ", zip_path)

    old_wd <- getwd()
    on.exit(setwd(old_wd), add = TRUE)

    setwd(pkg_dir)
    utils::zip(zipfile = zip_path, files = basename(copied_files))
  }

  # ---------------------------------------------------------------------------
  # Copy prompt template
  # ---------------------------------------------------------------------------
  message("[assemble_ai_package] Copying suitability_prompt.txt template...")

  if (!nzchar(prompt_src) || !file.exists(prompt_src)) {
    warning("[assemble_ai_package] Prompt source not found: ", prompt_src)
  } else {
    file.copy(from = prompt_src, to = prompt_dest, overwrite = TRUE)
  }

  # ---------------------------------------------------------------------------
  # Append processing summary to log
  # ---------------------------------------------------------------------------
  end_time    <- Sys.time()
  elapsed_sec <- as.numeric(difftime(end_time, start_time, units = "secs"))

  message("[assemble_ai_package] Updating log file: ", log_file)

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
    "Processing summary (assemble_ai_package)",
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

  message("[assemble_ai_package] Done for ", alpha_code, ".")

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
