#' Assemble a GenAI suitability package for a species
#'
#' Collects selected suitability-trend rasters, summary tables, and species
#' metadata for a single species, then builds an AI-ready package together
#' with prompt templates and a log entry. The function locates the project
#' root via \code{rENM_project_dir()} and does not rely on hard-coded paths.
#'
#' @details
#' \strong{Pipeline context}
#' \itemize{
#'   \item Copies selected suitability rasters and tables into a shared
#'         \code{suitability_package/} staging directory.
#'   \item Creates a \code{.zip} archive of the package contents.
#'   \item Copies the contents of \code{suitability_package/} and the
#'         corresponding prompt template into \emph{two} provider
#'         subdirectories under \code{Summaries/}:
#'         \code{chatgpt/} (prompt from \code{inst/chatgpt/}) and
#'         \code{claude/} (prompt from \code{inst/claude/}).
#'   \item Copies \code{\_species.csv} to a species-specific file and
#'         includes it in the package.
#'   \item Appends a standardized processing-summary block to
#'         \code{\_log.txt}.
#' }
#'
#' \strong{File selection}
#' \itemize{
#'   \item Adds flexible file selection via \code{files}.
#'   \item All files are drawn from subdirectories under \code{Trends/}.
#'   \item Users must explicitly specify subdirectories (e.g.,
#'         \code{"suitability/Suitability-Trend.tif"} or
#'         \code{"centroids/Bioclimatic-Velocity.csv"}).
#' }
#'
#' \strong{Directory layout produced}
#' \preformatted{
#' runs/<alpha_code>/Summaries/
#'   chatgpt/
#'     suitability_package/   <- staged files
#'     suitability_package.zip
#'     suitability_prompt.txt <- from inst/chatgpt/
#'   claude/
#'     suitability_package/   <- same staged files
#'     suitability_package.zip
#'     suitability_prompt.txt <- from inst/claude/
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
#'   \preformatted{
#'   <project_root>/runs/<alpha_code>/Trends/<subdir>/<alpha_code>-<filename>
#'   }
#'
#'   Defaults to a minimal core set.
#'
#' @return Named list (invisible) with components:
#' \itemize{
#'   \item \code{alpha_code}            -- input species code
#'   \item \code{pkg_dir}               -- path to staging \code{suitability_package/}
#'   \item \code{chatgpt_dir}           -- path to species \code{chatgpt/} folder
#'   \item \code{claude_dir}            -- path to species \code{claude/} folder
#'   \item \code{chatgpt_zip_path}      -- path to ChatGPT zip archive
#'   \item \code{claude_zip_path}       -- path to Claude zip archive
#'   \item \code{chatgpt_prompt_path}   -- path to copied ChatGPT prompt file
#'   \item \code{claude_prompt_path}    -- path to copied Claude prompt file
#'   \item \code{species_info_trends}   -- trends-level species table
#'   \item \code{species_info_pkg}      -- species table inside the staging package
#'   \item \code{log_file}              -- updated log file path
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
  start_time <- Sys.time()
  message("[assemble_ai_package] Starting for alpha code: ", alpha_code)

  # ---------------------------------------------------------------------------
  # Core path roots
  # ---------------------------------------------------------------------------
  proj_root  <- rENM_project_dir()
  runs_root  <- file.path(proj_root, "runs")
  data_root  <- file.path(proj_root, "data")

  # Species-specific suitability-trends directory and species info file
  trends_dir          <- file.path(runs_root, alpha_code, "Trends", "suitability")
  species_info_trends <- file.path(trends_dir,
                                   sprintf("%s-Species-Information.csv", alpha_code))

  # ---------------------------------------------------------------------------
  # Build source file list from files argument
  # ---------------------------------------------------------------------------
  files <- as.character(files)

  if (any(!grepl("/", files, fixed = TRUE))) {
    stop(
      "[assemble_ai_package] All entries in 'files' must include a ",
      "subdirectory (e.g., 'suitability/file.tif').",
      call. = FALSE
    )
  }

  src_files <- vapply(files, function(f) {
    file.path(
      runs_root, alpha_code, "Trends",
      dirname(f),
      sprintf("%s-%s", alpha_code, basename(f))
    )
  }, character(1L), USE.NAMES = FALSE)

  # Ensure species info is always included
  if (!species_info_trends %in% src_files) {
    src_files <- c(src_files, species_info_trends)
  }

  message("[assemble_ai_package] Files requested:")
  message(paste("  -", basename(src_files), collapse = "\n"))

  # ---------------------------------------------------------------------------
  # Provider directories: chatgpt and claude
  # ---------------------------------------------------------------------------
  summaries_dir <- file.path(runs_root, alpha_code, "Summaries")
  chatgpt_dir   <- file.path(summaries_dir, "chatgpt")
  claude_dir    <- file.path(summaries_dir, "claude")

  # Each provider gets its own staging package subdirectory and zip
  chatgpt_pkg_dir  <- file.path(chatgpt_dir, "suitability_package")
  claude_pkg_dir   <- file.path(claude_dir,  "suitability_package")
  chatgpt_zip_path <- file.path(chatgpt_dir, "suitability_package.zip")
  claude_zip_path  <- file.path(claude_dir,  "suitability_package.zip")

  for (d in c(chatgpt_pkg_dir, claude_pkg_dir)) {
    if (!dir.exists(d)) {
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
      message("[assemble_ai_package] Created directory: ", d)
    }
  }

  # ---------------------------------------------------------------------------
  # Prompt template paths (one per provider, from inst/<provider>/)
  # ---------------------------------------------------------------------------
  chatgpt_prompt_src  <- system.file("chatgpt", "suitability_prompt.txt",
                                     package = "rENM.ai")
  claude_prompt_src   <- system.file("claude",  "suitability_prompt.txt",
                                     package = "rENM.ai")
  chatgpt_prompt_dest <- file.path(chatgpt_dir, "suitability_prompt.txt")
  claude_prompt_dest  <- file.path(claude_dir,  "suitability_prompt.txt")

  # ---------------------------------------------------------------------------
  # Log file path
  # ---------------------------------------------------------------------------
  log_file <- file.path(runs_root, alpha_code, "_log.txt")

  # ---------------------------------------------------------------------------
  # Prepare species-information file in the trends directory
  # ---------------------------------------------------------------------------
  message("[assemble_ai_package] Preparing species information file...")

  species_info_src <- file.path(data_root, "_species.csv")

  if (!file.exists(species_info_src)) {
    warning("[assemble_ai_package] Species info source not found: ",
            species_info_src, call. = FALSE)
  } else {
    ok_species <- file.copy(species_info_src, species_info_trends,
                            overwrite = TRUE)
    if (ok_species) {
      message("  - Species information copied to: ", species_info_trends)
    } else {
      warning("[assemble_ai_package] Failed to copy species info to: ",
              species_info_trends, call. = FALSE)
    }
  }

  # ---------------------------------------------------------------------------
  # Copy source files into both provider staging directories
  # ---------------------------------------------------------------------------
  .copy_files_to <- function(pkg_dir, label) {
    copied <- character(0)
    for (src in src_files) {
      if (!file.exists(src)) {
        warning("[assemble_ai_package] Missing source file: ", src,
                call. = FALSE)
        next
      }
      dest <- file.path(pkg_dir, basename(src))
      ok   <- file.copy(src, dest, overwrite = TRUE)
      if (ok) {
        copied <- c(copied, dest)
      } else {
        warning("[assemble_ai_package] Failed to copy ", basename(src),
                " to ", label, call. = FALSE)
      }
    }
    copied
  }

  message("[assemble_ai_package] Copying files into chatgpt/ package directory...")
  chatgpt_copied <- .copy_files_to(chatgpt_pkg_dir, "chatgpt")
  message(paste("  -", basename(chatgpt_copied), collapse = "\n"))

  message("[assemble_ai_package] Copying files into claude/ package directory...")
  claude_copied <- .copy_files_to(claude_pkg_dir, "claude")
  message(paste("  -", basename(claude_copied), collapse = "\n"))

  # ---------------------------------------------------------------------------
  # Create zip archives (one per provider)
  # ---------------------------------------------------------------------------
  .make_zip <- function(zip_path, pkg_dir, copied_files, label) {
    if (length(copied_files) == 0) {
      warning("[assemble_ai_package] No files copied for ", label,
              "; zip not created.", call. = FALSE)
      return(invisible(NULL))
    }
    message("[assemble_ai_package] Creating ", label, " zip: ", zip_path)
    old_wd <- getwd()
    on.exit(setwd(old_wd), add = TRUE)
    setwd(pkg_dir)
    utils::zip(zipfile = zip_path, files = basename(copied_files))
  }

  .make_zip(chatgpt_zip_path, chatgpt_pkg_dir, chatgpt_copied, "chatgpt")
  .make_zip(claude_zip_path,  claude_pkg_dir,  claude_copied,  "claude")

  # ---------------------------------------------------------------------------
  # Copy prompt templates
  # ---------------------------------------------------------------------------
  .copy_prompt <- function(src, dest, label) {
    message("[assemble_ai_package] Copying ", label, " prompt template...")
    if (!nzchar(src) || !file.exists(src)) {
      warning("[assemble_ai_package] ", label, " prompt not found: ", src,
              call. = FALSE)
    } else {
      file.copy(src, dest, overwrite = TRUE)
    }
  }

  .copy_prompt(chatgpt_prompt_src, chatgpt_prompt_dest, "chatgpt")
  .copy_prompt(claude_prompt_src,  claude_prompt_dest,  "claude")

  # ---------------------------------------------------------------------------
  # Append processing summary to log
  # ---------------------------------------------------------------------------
  end_time    <- Sys.time()
  elapsed_sec <- as.numeric(difftime(end_time, start_time, units = "secs"))

  message("[assemble_ai_package] Updating log file: ", log_file)

  species_info_pkg <- file.path(chatgpt_pkg_dir, basename(species_info_trends))

  outputs_saved <- c(
    chatgpt_pkg_dir,
    claude_pkg_dir,
    if (file.exists(chatgpt_zip_path))    chatgpt_zip_path    else NA_character_,
    if (file.exists(claude_zip_path))     claude_zip_path     else NA_character_,
    if (file.exists(chatgpt_prompt_dest)) chatgpt_prompt_dest else NA_character_,
    if (file.exists(claude_prompt_dest))  claude_prompt_dest  else NA_character_,
    if (file.exists(species_info_trends)) species_info_trends else NA_character_,
    if (file.exists(species_info_pkg))    species_info_pkg    else NA_character_
  )
  outputs_saved <- outputs_saved[!is.na(outputs_saved)]

  # origiinal code ---
  # log_block <- c(
  #   paste0(strrep("-", 72)),
  #   "Processing summary (assemble_ai_package)",
  #   sprintf("Timestamp:     %s", format(end_time, "%Y-%m-%d %H:%M:%S")),
  #   sprintf("Alpha code:    %s", alpha_code),
  #   "Raster source: Suitability trends and species information",
  #   sprintf(
  #     "Outputs saved: %s",
  #     if (length(outputs_saved) > 0)
  #       paste(outputs_saved, collapse = "; ")
  #     else
  #       "None"
  #   ),
  #   sprintf("Total elapsed: %.3f secs", elapsed_sec),
  #   ""
  # )

  log_block <- c(
    paste0(strrep("-", 72)),
    "Processing summary (assemble_ai_package)",
    sprintf("Timestamp:     %s", format(end_time, "%Y-%m-%d %H:%M:%S")),
    sprintf("Alpha code:    %s", alpha_code),
    "Raster source: Suitability trends and species information",
    if (length(outputs_saved) > 0)
      c("Outputs saved:", paste0("  ", outputs_saved))
    else
      "Outputs saved: None",
    sprintf("Total elapsed: %.3f secs", elapsed_sec),
    ""
  )

  cat(paste0(log_block, "\n"), file = log_file, append = TRUE)

  message("[assemble_ai_package] Done for ", alpha_code, ".")

  invisible(list(
    alpha_code          = alpha_code,
    pkg_dir             = chatgpt_pkg_dir,
    chatgpt_dir         = chatgpt_dir,
    claude_dir          = claude_dir,
    chatgpt_zip_path    = chatgpt_zip_path,
    claude_zip_path     = claude_zip_path,
    chatgpt_prompt_path = chatgpt_prompt_dest,
    claude_prompt_path  = claude_prompt_dest,
    species_info_trends = species_info_trends,
    species_info_pkg    = species_info_pkg,
    log_file            = log_file
  ))
}
