#' Submit a GenAI-ready climatic suitability trend package to ChatGPT
#'
#' Interprets analysis outputs from an rENM run for a single
#' species by sending a zipped data bundle and custom prompt to the OpenAI
#' Responses API, retrieving a DOCX report, and logging processing
#' metadata and cost information.
#'
#' @details
#' \strong{Pipeline context}
#' \itemize{
#'   \item Reads a species-specific prompt file.
#'   \item Uploads a zipped bundle of GeoTIFF and CSV inputs.
#'   \item Calls the Responses API with the code-interpreter tool enabled.
#'   \item Downloads a Word report created inside the container.
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
#' \strong{Authentication}
#' \itemize{
#'   \item Uses \code{api_key}, defaulting to
#'         \code{Sys.getenv("OPENAI_API_KEY")}.
#' }
#'
#' \strong{Directory layout under \code{rENM_project_dir()}}
#' \preformatted{
#' <project_dir>/runs/CASP/Summaries/chatgpt/suitability_package.zip
#' <project_dir>/runs/CASP/Summaries/chatgpt/suitability_prompt.txt
#' <project_dir>/runs/<alpha_code>/Summaries/pages/
#'     <alpha_code>-Suitability-Trend-Analysis.docx
#' <project_dir>/runs/<alpha_code>/_log.txt
#' }
#'
#' \strong{Outputs}
#' \itemize{
#'   \item DOCX report saved to the \code{pages} directory.
#'   \item Updated \code{_log.txt} containing a processing summary.
#' }
#'
#' @param alpha_code Character. Four-letter species alpha code.
#' @param model Character. OpenAI model identifier.
#' @param api_key Character. OpenAI API key.
#'
#' @return List (invisible) with components
#' \itemize{
#'   \item \code{response}
#'   \item \code{docx_path}
#'   \item \code{elapsed_sec}
#'   \item \code{input_tokens}, \code{output_tokens}, \code{total_tokens}
#'   \item \code{est_total_cost}
#' }
#'
#' @importFrom curl form_file
#' @importFrom httr2 request req_auth_bearer_token req_body_multipart
#' @importFrom httr2 req_body_json req_perform resp_status req_headers
#' @importFrom httr2 resp_body_string resp_body_json resp_body_raw req_error
#' @importFrom httr2 req_url_query
#'
#' @export
submit_to_chatgpt <- function(
    alpha_code,
    model   = "gpt-5.1",
    api_key = Sys.getenv("OPENAI_API_KEY")
) {

  for (pkg in c("httr2", "curl")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("Package '%s' is required but not installed.", pkg),
           call. = FALSE)
    }
  }


  api_key <- trimws(api_key)
  if (!nzchar(api_key)) stop("OPENAI_API_KEY is not set.", call. = FALSE)

  project_dir <- rENM_project_dir()
  species_dir <- file.path(project_dir, "runs", alpha_code)

  chatgpt_dir <- file.path(species_dir, "Summaries", "chatgpt")

  zip_path    <- file.path(chatgpt_dir, "suitability_package.zip")
  prompt_path <- file.path(chatgpt_dir, "suitability_prompt.txt")

  out_dir <- file.path(species_dir, "Summaries", "pages")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  docx_path <- file.path(
    out_dir,
    sprintf("%s-Suitability-Trend-Analysis.docx", alpha_code)
  )

  # ---- Read prompt ----------------------------------------------------------
  prompt <- paste(readLines(prompt_path, warn = FALSE), collapse = "\n")
  prompt <- gsub("<alpha_code>", alpha_code, prompt, fixed = TRUE)

  # The model cannot look up the current time, and asking it to produce the
  # footer stamp itself yielded a plausible date with the time zone silently
  # dropped. Substitute it here so the stamp is correct by construction.
  prompt <- gsub(
    "<timestamp>",
    sub("^0", "", format(Sys.time(), "%d %B %Y - %H:%M %Z")),
    prompt, fixed = TRUE
  )

  # The disclosure paragraph names the model that wrote the narrative. Taking
  # it from the argument keeps that claim true when the model is overridden.
  prompt <- gsub("<model>", model, prompt, fixed = TRUE)

  # ---- Upload bundle --------------------------------------------------------
  req_upload <- httr2::request("https://api.openai.com/v1/files") |>
    httr2::req_auth_bearer_token(api_key) |>
    httr2::req_body_multipart(
      purpose = "user_data",
      file    = curl::form_file(zip_path)
    )

  file_id <- httr2::resp_body_json(httr2::req_perform(req_upload))$id

  # ---- Call Responses API ---------------------------------------------------
  body <- list(
    model = model,
    input = list(list(role = "user",
                      content = list(list(type = "input_text",
                                          text = prompt)))),
    tools = list(list(type = "code_interpreter",
                      container = list(type = "auto",
                                       file_ids = list(file_id))))
  )

  start_time <- Sys.time()

  resp <- httr2::request("https://api.openai.com/v1/responses") |>
    httr2::req_auth_bearer_token(api_key) |>
    httr2::req_body_json(body) |>
    httr2::req_perform()

  elapsed_sec <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  resp_json <- httr2::resp_body_json(resp)

  usage <- resp_json$usage %||% list()

  input_tokens  <- usage$input_tokens  %||% NA
  output_tokens <- usage$output_tokens %||% NA
  total_tokens  <- usage$total_tokens  %||% NA

  est_total_cost <- sum(
    input_tokens  * 1.25 / 1e6,
    output_tokens * 10   / 1e6,
    0.03,
    na.rm = TRUE
  )

  # ---- Retrieve DOCX only ---------------------------------------------------
  container_ids <- unique(
    unlist(lapply(resp_json$output, function(x) x$container_id))
  )

  docx_path_final <- NA_character_
  seen_paths      <- character(0)

  # The container holds the uploaded bundle, every file the model unpacked
  # from it, each intermediate written across the tool calls, and finally the
  # document. That listing is paginated, and the document is written last, so
  # a run that happens to create more files pushes it past the first page. A
  # single unpaginated request retrieved it only sometimes, which is what made
  # this step look like the model failing at random. It was not.
  .list_container_files <- function(cid) {
    acc   <- list()
    after <- NULL
    repeat {
      req <- httr2::request(
        paste0("https://api.openai.com/v1/containers/", cid, "/files")
      ) |>
        httr2::req_auth_bearer_token(api_key) |>
        httr2::req_url_query(limit = 100)
      if (!is.null(after)) req <- httr2::req_url_query(req, after = after)

      body <- httr2::resp_body_json(httr2::req_perform(req))
      dat  <- body$data %||% list()
      acc  <- c(acc, dat)

      if (!isTRUE(body$has_more) || !length(dat)) break
      after <- dat[[length(dat)]]$id
    }
    acc
  }

  want <- basename(docx_path)

  for (cid in container_ids) {

    files <- .list_container_files(cid)
    paths <- vapply(files, function(f) f$path %||% "", character(1))
    seen_paths <- c(seen_paths, paths)

    # Prefer the exact filename the prompt demands; fall back to any .docx so
    # a renamed output is still recovered rather than silently lost.
    idx <- which(basename(paths) == want)
    if (!length(idx)) idx <- which(grepl("\\.docx$", paths, ignore.case = TRUE))
    if (!length(idx)) next

    f <- files[[idx[[length(idx)]]]]

    raw <- httr2::request(
      paste0("https://api.openai.com/v1/containers/", cid,
             "/files/", f$id, "/content")
    ) |>
      httr2::req_auth_bearer_token(api_key) |>
      httr2::req_perform() |>
      httr2::resp_body_raw()

    writeBin(raw, docx_path)
    docx_path_final <- docx_path
    break
  }

  # A call that produces no document has still cost money and several minutes,
  # and the response is the only evidence of why. Returning quietly threw it
  # away and surfaced the problem two functions later as a missing file, with
  # nothing left to diagnose. Keep the response and say so here instead.
  if (is.na(docx_path_final)) {
    diag_path <- file.path(
      chatgpt_dir, sprintf("%s-response.json", alpha_code)
    )
    try(
      writeLines(httr2::resp_body_string(resp), diag_path),
      silent = TRUE
    )
    item_types <- unique(unlist(lapply(resp_json$output, function(x) x$type)))
    warning(
      "No .docx was returned for ", alpha_code, ".\n",
      "  status          : ", resp_json$status %||% "unknown", "\n",
      "  incomplete      : ", resp_json$incomplete_details$reason %||% "none", "\n",
      "  output items    : ",
      if (length(item_types)) paste(item_types, collapse = ", ") else "none", "\n",
      "  containers seen : ", length(container_ids), "\n",
      "  files in them   : ",
      if (length(seen_paths)) paste(basename(seen_paths), collapse = ", ") else "none", "\n",
      "  raw response    : ", diag_path,
      call. = FALSE
    )
  }

  # ---- Log ------------------------------------------------------------------
  .submit_to_chatgpt_log(
    alpha_code      = alpha_code,
    species_dir     = species_dir,
    raster_source   = basename(zip_path),
    docx_path_final = docx_path_final,
    pdf_path_final  = NA_character_,
    elapsed_sec     = elapsed_sec,
    input_tokens    = input_tokens,
    output_tokens   = output_tokens,
    total_tokens    = total_tokens,
    est_total_cost  = est_total_cost
  )

  invisible(list(
    response       = resp_json,
    docx_path      = docx_path_final,
    elapsed_sec    = elapsed_sec,
    input_tokens   = input_tokens,
    output_tokens  = output_tokens,
    total_tokens   = total_tokens,
    est_total_cost = est_total_cost
  ))
}

# Internal helper: append eBird-style processing summary to _log.txt
#' @noRd
.submit_to_chatgpt_log <- function(alpha_code,
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
  dir.create(dirname(log_path), recursive = TRUE, showWarnings = FALSE)

  sep_line <- paste(rep("-", 72), collapse = "")
  fmt <- function(key, value) sprintf("%-16s: %s", key, value)

  outputs_saved <- if (!is.na(docx_path_final)) basename(docx_path_final) else "None"

  log_lines <- c(
    sep_line,
    "Processing summary (submit_to_chatgpt)",
    fmt("Timestamp",       format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    fmt("Alpha code",      alpha_code),
    fmt("Raster source",   raster_source),
    fmt("Outputs saved",   outputs_saved),
    fmt("Total elapsed",   sprintf("%.2f sec", elapsed_sec)),
    fmt("Output file",     if (!is.na(docx_path_final)) docx_path_final else "None"),
    fmt("Input tokens",    input_tokens),
    fmt("Output tokens",   output_tokens),
    fmt("Total tokens",    total_tokens),
    fmt("Est. cost (USD)", sprintf("$%.6f", est_total_cost)),
    ""
  )

  write(log_lines, file = log_path, append = TRUE)
}
