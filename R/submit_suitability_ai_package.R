#' Submit GenAI-ready climatic suitability trend package for a species
#'
#' Runs an end-to-end climatic suitability trend analysis for a single
#' species by sending a zipped data bundle and custom prompt to the OpenAI
#' Responses API, retrieving DOCX and PDF reports, and logging processing
#' metadata and cost information.
#'
#' @details
#' This function is part of the rENM framework's processing pipeline
#' and operates within the project directory structure defined by
#' \code{rENM_project_dir()}.
#'
#' \strong{Pipeline context}
#' \itemize{
#'   \item Reads a species-specific prompt file.
#'   \item Uploads a zipped bundle of GeoTIFF and CSV inputs.
#'   \item Calls the Responses API with the code-interpreter tool enabled.
#'   \item Downloads a Word report and a PDF report created inside the
#'         container.
#'   \item Computes token usage and approximate OpenAI cost.
#'   \item Appends an eBird-style summary line to \code{_log.txt}.
#' }
#'
#' \strong{Expected inputs}
#' \itemize{
#'   \item Prompt file containing the placeholder string \code{<alpha_code>}.
#'   \item Zipped bundle of raster and tabular data required by the prompt.
#' }
#'
#' \strong{Directory layout under \code{rENM_project_dir()}}
#' \preformatted{
#' <project_dir>/runs/CASP/Summaries/chatgpt/suitability_package.zip
#' <project_dir>/runs/CASP/Summaries/chatgpt/suitability_prompt.txt
#' <project_dir>/runs/<alpha_code>/Summaries/pages/
#'     <alpha_code>-Suitability-Trend-Analysis.docx
#' <project_dir>/runs/<alpha_code>/Summaries/pages/
#'     <alpha_code>-Suitability-Trend-Analysis.pdf
#' <project_dir>/runs/<alpha_code>/_log.txt
#' }
#'
#' \strong{Original layout reference}
#' \preformatted{
#' ~/rENM/runs/CASP/Summaries/chatgpt/suitability_package.zip
#' ~/rENM/runs/CASP/Summaries/chatgpt/suitability_prompt.txt
#' ~/rENM/runs/<alpha_code>/Summaries/pages/
#'     <alpha_code>-Suitability-Trend-Analysis.docx
#' ~/rENM/runs/<alpha_code>/Summaries/pages/
#'     <alpha_code>-Suitability-Trend-Analysis.pdf
#' ~/rENM/runs/<alpha_code>/_log.txt
#' }
#'
#' \strong{Outputs}
#' \itemize{
#'   \item DOCX and PDF reports saved to the \code{pages} directory.
#'   \item Updated \code{_log.txt} containing a processing summary.
#' }
#'
#' \strong{Cost model}
#' \itemize{
#'   \item Input tokens: USD 1.25 per 1M tokens.
#'   \item Output tokens: USD 10.00 per 1M tokens.
#'   \item Code-interpreter session: USD 0.03 flat.
#' }
#'
#' @param alpha_code Character. Four-letter species alpha code
#'   (e.g., \code{"CASP"}).
#' @param model Character. OpenAI model identifier that supports the
#'   Responses API and code-interpreter tool. Default is \code{"gpt-5.1"}.
#' @param api_key Character. OpenAI API key. Defaults to
#'   \code{Sys.getenv("OPENAI_API_KEY")}.
#'
#' @return List (invisible) with components
#' \itemize{
#'   \item \code{response} – parsed JSON response from the API.
#'   \item \code{docx_path} – file path of the DOCX report, or
#'         \code{NA} if not found.
#'   \item \code{pdf_path} – file path of the PDF report, or
#'         \code{NA} if not found.
#'   \item \code{elapsed_sec} – total elapsed time in seconds.
#'   \item \code{input_tokens}, \code{output_tokens},
#'         \code{total_tokens} – approximate token counts.
#'   \item \code{est_total_cost} – approximate cost in USD.
#' }
#'
#' @importFrom curl form_file
#' @importFrom httr2 request req_auth_bearer_token req_body_multipart
#' @importFrom httr2 req_body_json req_perform resp_status
#' @importFrom httr2 resp_body_string resp_body_json resp_body_raw
#'
#' @examples
#' \dontrun{
#' res <- submit_suitability_ai_package("CASP")
#' res$docx_path
#' res$pdf_path
#' }
#'
#' @export
submit_suitability_ai_package <- function(
    alpha_code,
    model   = "gpt-5.1",
    api_key = Sys.getenv("OPENAI_API_KEY")
) {
  # ---- Dependencies ---------------------------------------------------------
  # Stand-alone function for package use: do not call library(), only
  # require that the packages are installed and listed in DESCRIPTION.
  for (pkg in c("httr2", "curl")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("Package '%s' is required but not installed.", pkg),
           call. = FALSE)
    }
  }

  # Safe "x %||% y" helper (local to this function)
  `%||%` <- function(x, y) if (is.null(x)) y else x

  if (identical(api_key, "") || is.na(api_key)) {
    stop("OPENAI_API_KEY is not set.")
  }

  message("=== submit_suitability_ai_package(): Starting for alpha_code = ",
          alpha_code, " ===")

  # ---- 0. Construct paths ---------------------------------------------------
  project_dir <- rENM_project_dir()
  base_dir    <- file.path(project_dir, "runs")
  species_dir <- file.path(base_dir, alpha_code)

  chatgpt_dir <- file.path(species_dir, "Summaries", "chatgpt")

  zip_path    <- path.expand(file.path(chatgpt_dir,
                                       "suitability_package.zip"))
  prompt_path <- path.expand(file.path(chatgpt_dir,
                                       "suitability_prompt.txt"))

  if (!file.exists(zip_path)) {
    stop("Zip file not found: ", zip_path)
  }
  if (!file.exists(prompt_path)) {
    stop("Prompt file not found: ", prompt_path)
  }

  out_base_dir <- path.expand(file.path(species_dir, "Summaries", "pages"))
  dir.create(out_base_dir, recursive = TRUE, showWarnings = FALSE)

  docx_name <- sprintf("%s-Suitability-Trend-Analysis.docx", alpha_code)
  pdf_name  <- sprintf("%s-Suitability-Trend-Analysis.pdf",  alpha_code)

  docx_path <- file.path(out_base_dir, docx_name)
  pdf_path  <- file.path(out_base_dir, pdf_name)

  message("Input ZIP : ", zip_path)
  message("Prompt    : ", prompt_path)
  message("DOCX out  : ", docx_path)
  message("PDF out   : ", pdf_path)

  # ---- 1. Read prompt and substitute <alpha_code> ---------------------------
  message("Reading and preparing prompt text...")
  prompt_raw <- paste(readLines(prompt_path, warn = FALSE), collapse = "\n")

  # Simple literal substitution; avoids any templating/parsing side-effects
  prompt <- gsub("<alpha_code>", alpha_code, prompt_raw, fixed = TRUE)

  # ---- 2. Upload ZIP bundle to /v1/files -----------------------------------
  message("Uploading ZIP bundle to OpenAI Files API...")

  req_upload <- httr2::request("https://api.openai.com/v1/files") |>
    httr2::req_auth_bearer_token(api_key) |>
    httr2::req_body_multipart(
      purpose = "user_data",
      file    = curl::form_file(zip_path)
    )

  resp_upload <- httr2::req_perform(req_upload)

  if (httr2::resp_status(resp_upload) >= 300) {
    stop("File upload failed: ",
         httr2::resp_status(resp_upload), "\n",
         httr2::resp_body_string(resp_upload))
  }

  file_info      <- httr2::resp_body_json(resp_upload)
  bundle_file_id <- file_info$id
  message("Uploaded bundle file_id: ", bundle_file_id)

  # ---- 3. Call /v1/responses with code_interpreter --------------------------
  message("Calling Responses API with code_interpreter tool...")

  body <- list(
    model = model,
    input = list(
      list(
        role = "user",
        content = list(
          list(
            type = "input_text",
            text = prompt
          )
        )
      )
    ),
    tools = list(
      list(
        type = "code_interpreter",
        container = list(
          type     = "auto",
          file_ids = list(bundle_file_id)
        )
      )
    ),
    tool_choice = list(
      type = "code_interpreter"
    )
  )

  start_time <- Sys.time()

  req_resp <- httr2::request("https://api.openai.com/v1/responses") |>
    httr2::req_auth_bearer_token(api_key) |>
    httr2::req_body_json(body)

  resp <- httr2::req_perform(req_resp)

  end_time    <- Sys.time()
  elapsed_sec <- as.numeric(difftime(end_time, start_time, units = "secs"))

  if (httr2::resp_status(resp) >= 300) {
    stop("Responses API call failed: ",
         httr2::resp_status(resp), "\n",
         httr2::resp_body_string(resp))
  }

  resp_json <- httr2::resp_body_json(resp)
  message("Responses API call completed in ",
          round(elapsed_sec, 2), " seconds.")

  # ---- 4. Token usage and cost estimation ----------------------------------
  message("Parsing token usage and estimating cost...")

  usage <- resp_json$usage %||% list()
  input_tokens  <- usage$input_tokens  %||% NA_real_
  output_tokens <- usage$output_tokens %||% NA_real_
  total_tokens  <- usage$total_tokens  %||% NA_real_

  price_in_per_1M  <- 1.25   # USD per 1M input tokens
  price_out_per_1M <- 10.00  # USD per 1M output tokens
  cost_tool        <- 0.03   # USD per code interpreter session (flat)

  cost_input  <- if (!is.na(input_tokens))
    input_tokens * price_in_per_1M / 1e6 else NA_real_
  cost_output <- if (!is.na(output_tokens))
    output_tokens * price_out_per_1M / 1e6 else NA_real_
  est_total_cost <- sum(cost_input, cost_output, cost_tool, na.rm = TRUE)

  message("Token usage (approx):")
  message("  Input tokens : ", input_tokens)
  message("  Output tokens: ", output_tokens)
  message("  Total tokens : ", total_tokens)
  message("Estimated cost (USD):")
  message("  Input  : $", round(cost_input,  4))
  message("  Output : $", round(cost_output, 4))
  message("  Tool   : $", round(cost_tool,   4),
          " (code interpreter session)")
  message("  Total  : $", round(est_total_cost, 4))

  # ---- 5. Extract container_id(s) from response ----------------------------
  message("Looking for code_interpreter container IDs...")

  container_ids <- character()
  if (!is.null(resp_json$output)) {
    for (out in resp_json$output) {
      if (!is.null(out$type) && identical(out$type, "code_interpreter_call")) {
        if (!is.null(out$container_id)) {
          container_ids <- c(container_ids, out$container_id)
        }
      }
    }
  }

  container_ids <- unique(container_ids)
  if (!length(container_ids)) {
    warning("No code_interpreter_call outputs with container_id found in ",
            "response.")

    docx_path_final <- NA_character_
    pdf_path_final  <- NA_character_

    .submit_suitability_ai_package_log(
      alpha_code      = alpha_code,
      species_dir     = species_dir,
      raster_source   = basename(zip_path),
      docx_path_final = docx_path_final,
      pdf_path_final  = pdf_path_final,
      elapsed_sec     = elapsed_sec,
      input_tokens    = input_tokens,
      output_tokens   = output_tokens,
      total_tokens    = total_tokens,
      est_total_cost  = est_total_cost
    )

    return(invisible(list(
      response       = resp_json,
      docx_path      = docx_path_final,
      pdf_path       = pdf_path_final,
      elapsed_sec    = elapsed_sec,
      input_tokens   = input_tokens,
      output_tokens  = output_tokens,
      total_tokens   = total_tokens,
      est_total_cost = est_total_cost
    )))
  }

  message("Found container_ids: ", paste(container_ids, collapse = ", "))

  # ---- 6. Retrieve DOCX and PDF from container(s) --------------------------
  message("Scanning containers for DOCX and PDF report...")

  docx_saved <- FALSE
  pdf_saved  <- FALSE

  for (cid in container_ids) {
    req_list <- httr2::request(
      paste0("https://api.openai.com/v1/containers/", cid, "/files")
    ) |>
      httr2::req_auth_bearer_token(api_key)

    resp_list <- httr2::req_perform(req_list)
    if (httr2::resp_status(resp_list) >= 300) {
      warning("Listing files failed for container ", cid, ": ",
              httr2::resp_status(resp_list), "\n",
              httr2::resp_body_string(resp_list))
      next
    }

    files_json <- httr2::resp_body_json(resp_list)
    files_data <- files_json$data

    if (length(files_data) == 0) {
      next
    }

    for (f in files_data) {
      path <- f$path %||% ""

      # DOCX --------------------------------------------------------------
      if (grepl("\\.docx$", path, ignore.case = TRUE) && !docx_saved) {
        file_id <- f$id
        message("Found DOCX in container ", cid, ": ",
                path, " (file_id: ", file_id, ")")

        req_file <- httr2::request(
          paste0("https://api.openai.com/v1/containers/", cid,
                 "/files/", file_id, "/content")
        ) |>
          httr2::req_auth_bearer_token(api_key)

        resp_file <- httr2::req_perform(req_file)
        if (httr2::resp_status(resp_file) >= 300) {
          warning("Downloading DOCX failed for container ", cid,
                  ", file ", file_id, ": ",
                  httr2::resp_status(resp_file), "\n",
                  httr2::resp_body_string(resp_file))
        } else {
          raw <- httr2::resp_body_raw(resp_file)
          writeBin(raw, docx_path)
          message("Saved DOCX report to: ", docx_path)
          docx_saved <- TRUE
        }
      }

      # PDF ---------------------------------------------------------------
      if (grepl("\\.pdf$", path, ignore.case = TRUE) && !pdf_saved) {
        file_id <- f$id
        message("Found PDF in container ", cid, ": ",
                path, " (file_id: ", file_id, ")")

        req_file <- httr2::request(
          paste0("https://api.openai.com/v1/containers/", cid,
                 "/files/", file_id, "/content")
        ) |>
          httr2::req_auth_bearer_token(api_key)

        resp_file <- httr2::req_perform(req_file)
        if (httr2::resp_status(resp_file) >= 300) {
          warning("Downloading PDF failed for container ", cid,
                  ", file ", file_id, ": ",
                  httr2::resp_status(resp_file), "\n",
                  httr2::resp_body_string(resp_file))
        } else {
          raw <- httr2::resp_body_raw(resp_file)
          writeBin(raw, pdf_path)
          message("Saved PDF report to: ", pdf_path)
          pdf_saved <- TRUE
        }
      }
    }

    if (docx_saved && pdf_saved) {
      break
    }
  }

  if (!docx_saved) {
    warning("No .docx files were found on any containers.")
    docx_path_final <- NA_character_
  } else {
    docx_path_final <- docx_path
  }

  if (!pdf_saved) {
    warning("No .pdf files were found on any containers.")
    pdf_path_final <- NA_character_
  } else {
    pdf_path_final <- pdf_path
  }

  # ---- 7. Append processing summary to _log.txt ----------------------------
  .submit_suitability_ai_package_log(
    alpha_code      = alpha_code,
    species_dir     = species_dir,
    raster_source   = basename(zip_path),
    docx_path_final = docx_path_final,
    pdf_path_final  = pdf_path_final,
    elapsed_sec     = elapsed_sec,
    input_tokens    = input_tokens,
    output_tokens   = output_tokens,
    total_tokens    = total_tokens,
    est_total_cost  = est_total_cost
  )

  message("=== submit_suitability_ai_package(): Finished for ",
          alpha_code, " ===")

  invisible(list(
    response       = resp_json,
    docx_path      = docx_path_final,
    pdf_path       = pdf_path_final,
    elapsed_sec    = elapsed_sec,
    input_tokens   = input_tokens,
    output_tokens  = output_tokens,
    total_tokens   = total_tokens,
    est_total_cost = est_total_cost
  ))
}

# Internal helper: append eBird-style processing summary to _log.txt
.submit_suitability_ai_package_log <- function(alpha_code,
                                               species_dir,
                                               raster_source,
                                               docx_path_final,
                                               pdf_path_final,
                                               elapsed_sec,
                                               input_tokens,
                                               output_tokens,
                                               total_tokens,
                                               est_total_cost) {
  log_path <- file.path(species_dir, "_log.txt")
  log_dir  <- dirname(log_path)
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

  sep_line <- paste(rep("-", 72), collapse = "")

  fmt <- function(key, value) sprintf("%-16s: %s", key, value)

  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")

  total_cells    <- "NA"
  valid_cells    <- "NA"
  positive_cells <- "NA"
  negative_cells <- "NA"
  zero_cells     <- "NA"

  outputs_saved <- paste(
    c(
      if (!is.na(docx_path_final)) basename(docx_path_final) else NULL,
      if (!is.na(pdf_path_final))  basename(pdf_path_final)  else NULL
    ),
    collapse = "; "
  )
  if (identical(outputs_saved, "")) outputs_saved <- "None"

  output_file <- if (!is.na(docx_path_final))
    docx_path_final else "None"

  input_tokens_str  <- if (is.na(input_tokens))
    "NA" else as.character(input_tokens)
  output_tokens_str <- if (is.na(output_tokens))
    "NA" else as.character(output_tokens)
  total_tokens_str  <- if (is.na(total_tokens))
    "NA" else as.character(total_tokens)
  cost_str          <- if (is.na(est_total_cost))
    "NA" else sprintf("$%.6f", est_total_cost)

  log_lines <- c(
    sep_line,
    "Processing summary (submit_suitability_ai_package)",
    fmt("Timestamp",       timestamp),
    fmt("Alpha code",      alpha_code),
    fmt("Raster source",   raster_source),
    fmt("Total cells",     total_cells),
    fmt("Valid cells",     valid_cells),
    fmt("Positive cells",  positive_cells),
    fmt("Negative cells",  negative_cells),
    fmt("Zero cells",      zero_cells),
    fmt("Outputs saved",   outputs_saved),
    fmt("Total elapsed",   sprintf("%.2f sec", elapsed_sec)),
    fmt("Output file",     output_file),
    fmt("Input tokens",    input_tokens_str),
    fmt("Output tokens",   output_tokens_str),
    fmt("Total tokens",    total_tokens_str),
    fmt("Est. cost (USD)", cost_str),
    ""
  )

  write(log_lines, file = log_path, append = TRUE)
  message("Appended processing summary to log: ", log_path)
}
