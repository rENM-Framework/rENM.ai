#' Submit a GenAI-ready climatic suitability trend package to Claude
#'
#' Interprets analysis outputs from an rENM run for a single
#' species by uploading a zipped data bundle to the Anthropic Files API,
#' referencing it as a \code{file} content block in the Messages API call
#' with the code execution tool enabled, retrieving the generated DOCX
#' report, and logging processing metadata and cost information.
#'
#' @details
#' \strong{What is sent to the API}
#' \enumerate{
#'   \item \code{suitability_package.zip} is uploaded to the Anthropic
#'         Files API, returning a \code{file_id}.
#'   \item \code{suitability_prompt.txt} is read and \code{<alpha_code>}
#'         is interpolated.
#'   \item The Messages API is called with two content blocks: a
#'         \code{text} block containing the prompt, and a
#'         \code{container_upload} block referencing the uploaded zip
#'         by \code{file_id}. The \code{container_upload} block type
#'         is the correct mechanism for delivering binary files to the
#'         code execution sandbox via the Files API.
#'   \item The uploaded zip is deleted from Anthropic storage after the
#'         run to avoid accumulating storage usage.
#' }
#'
#' \strong{Why not base64 embedding?}
#'
#' Embedding the zip as base64 in the prompt body produces a ~74,000
#' character payload that causes the Anthropic API to time out before
#' responding (zero bytes received). Uploading via the Files API and
#' referencing by \code{file_id} keeps the Messages API request small
#' and avoids this problem.
#'
#' \strong{Pipeline context}
#' \itemize{
#'   \item Uploads zip to Files API; records \code{file_id}.
#'   \item Calls Messages API with \code{text} + \code{file} content
#'         blocks and the code execution tool enabled
#'         (beta: \code{code-execution-2025-08-25}).
#'   \item Saves the raw API response to \code{debug_resp.rds}
#'         immediately after the call, regardless of outcome.
#'   \item Scans response blocks for output file IDs and downloads
#'         the DOCX via the Files API (\code{files-api-2025-04-14}).
#'   \item Deletes the uploaded input zip from Anthropic storage.
#'   \item Estimates token usage and approximate API cost.
#'   \item Appends a processing summary to \code{_log.txt}.
#' }
#'
#' \strong{Debugging a failed run}
#'
#' If no DOCX is produced, inspect the saved response:
#' \preformatted{
#' resp <- readRDS("<species_dir>/debug_resp.rds")
#' submit_to_claude_diag(resp)
#' }
#' \code{submit_to_claude_diag()} prints block types, stdout/stderr
#' from the sandbox, return codes, and any text Claude returned.
#'
#' \strong{Authentication}
#' \itemize{
#'   \item Uses \code{api_key}, defaulting to
#'         \code{Sys.getenv("ANTHROPIC_API_KEY")}.
#'   \item Obtain an API key from \url{https://console.anthropic.com}.
#'   \item This requires a separate Anthropic API account billed per
#'         token, independently of any claude.ai subscription.
#' }
#'
#' \strong{Required beta features}
#'
#' Both are enabled automatically via the \code{anthropic-beta} header:
#' \itemize{
#'   \item \code{files-api-2025-04-14} -- file upload and download
#'   \item \code{code-execution-2025-08-25} -- sandboxed Python execution
#' }
#'
#' \strong{Directory layout under \code{rENM_project_dir()}}
#' \preformatted{
#' <project_dir>/runs/<alpha_code>/Summaries/claude/suitability_package.zip
#' <project_dir>/runs/<alpha_code>/Summaries/claude/suitability_prompt.txt
#' <project_dir>/runs/<alpha_code>/Summaries/pages/
#'     <alpha_code>-Suitability-Trend-Analysis.docx
#' <project_dir>/runs/<alpha_code>/debug_resp.rds  <- saved after every run
#' <project_dir>/runs/<alpha_code>/_log.txt
#' }
#'
#' \strong{Cost estimation}
#'
#' Approximate costs using claude-sonnet-4-6 pricing as of May 2026:
#' \itemize{
#'   \item Input tokens:  $3.00 / 1M tokens
#'   \item Output tokens: $15.00 / 1M tokens
#' }
#' These are estimates only; actual billing may differ.
#'
#' @param alpha_code Character. Four-letter species alpha code (e.g.,
#'   \code{"CASP"}).
#' @param model Character. Anthropic model identifier. Defaults to
#'   \code{"claude-sonnet-4-6"}.
#' @param api_key Character. Anthropic API key. Defaults to the value of
#'   the \code{ANTHROPIC_API_KEY} environment variable.
#' @param max_tokens Integer. Maximum output tokens. Defaults to 32000.
#'   The code execution tool consumes tokens across multiple internal
#'   round-trips (code submission, stdout, file output), so this task
#'   requires significantly more headroom than a plain text generation
#'   call. A \code{stop_reason} of \code{"max_tokens"} in the response
#'   indicates this limit was reached before the DOCX was produced;
#'   increase to 64000 if needed.
#' @param timeout_sec Integer. Request timeout in seconds. Defaults to
#'   600 (10 minutes). Increase for very large packages.
#' @param delete_input_file Logical. If \code{TRUE} (default), the
#'   uploaded zip is deleted from Anthropic storage after the run.
#'
#' @return Named list with components:
#' \itemize{
#'   \item \code{docx_path}     -- local path to the downloaded DOCX,
#'                                  or \code{NA} if not found.
#'   \item \code{elapsed_sec}   -- wall-clock seconds for the API call.
#'   \item \code{input_tokens}  -- input token count from usage metadata.
#'   \item \code{output_tokens} -- output token count from usage metadata.
#'   \item \code{total_tokens}  -- total token count.
#'   \item \code{est_cost_usd}  -- estimated cost in USD.
#'   \item \code{response}      -- full parsed response body (list).
#'   \item \code{debug_rds}     -- path to the saved debug_resp.rds file.
#' }
#'
#' @importFrom curl form_file
#' @importFrom httr2 request req_headers req_body_multipart req_body_json
#' @importFrom httr2 req_perform req_retry req_timeout resp_body_json
#' @importFrom httr2 resp_body_raw resp_status req_error req_method
#'
#' @examples
#' \dontrun{
#'   Sys.setenv(ANTHROPIC_API_KEY = "sk-ant-...")
#'
#'   result <- submit_to_claude("CASP")
#'   message("Report: ", result$docx_path)
#'   message(sprintf("Cost: $%.6f | Tokens: %d",
#'                   result$est_cost_usd, result$total_tokens))
#'
#'   # If no DOCX was produced, diagnose:
#'   submit_to_claude_diag(result$response)
#'   # or load from disk:
#'   submit_to_claude_diag(readRDS(result$debug_rds))
#' }
#'
#' @export
submit_to_claude <- function(
    alpha_code,
    model              = "claude-sonnet-4-6",
    api_key            = Sys.getenv("ANTHROPIC_API_KEY"),
    max_tokens         = 32000L,
    timeout_sec        = 600L,
    delete_input_file  = TRUE
) {

  # ---- dependency check ------------------------------------------------------
  for (pkg in c("httr2", "curl")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf(
        "Package '%s' is required. Install with: install.packages('%s')",
        pkg, pkg), call. = FALSE)
    }
  }


  # ---- validate API key ------------------------------------------------------
  api_key <- trimws(api_key)
  if (!nzchar(api_key)) {
    stop(
      "ANTHROPIC_API_KEY is not set.\n",
      "Set it with: Sys.setenv(ANTHROPIC_API_KEY = 'sk-ant-...')\n",
      "Or add ANTHROPIC_API_KEY=sk-ant-... to ~/.Renviron",
      call. = FALSE
    )
  }

  # ---- resolve paths ---------------------------------------------------------
  project_dir <- rENM_project_dir()
  species_dir <- file.path(project_dir, "runs", alpha_code)
  claude_dir  <- file.path(species_dir, "Summaries", "claude")
  out_dir     <- file.path(species_dir, "Summaries", "pages")
  debug_rds   <- file.path(species_dir, "debug_resp.rds")

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  zip_path    <- file.path(claude_dir, "suitability_package.zip")
  prompt_path <- file.path(claude_dir, "suitability_prompt.txt")
  docx_path   <- file.path(out_dir,
                           sprintf("%s-Suitability-Trend-Analysis.docx",
                                   alpha_code))

  for (p in c(zip_path, prompt_path)) {
    if (!file.exists(p))
      stop("Required input not found: ", p, call. = FALSE)
  }

  # ---- shared request builder ------------------------------------------------
  BETA_HEADER    <- "files-api-2025-04-14,code-execution-2025-08-25"
  VERSION_HEADER <- "2023-06-01"

  .claude_req <- function(url) {
    httr2::request(url) |>
      httr2::req_headers(
        "x-api-key"         = api_key,
        "anthropic-version" = VERSION_HEADER,
        "anthropic-beta"    = BETA_HEADER
      ) |>
      httr2::req_timeout(timeout_sec) |>
      httr2::req_error(is_error = function(resp) FALSE)
  }

  .check_resp <- function(resp, context) {
    status <- httr2::resp_status(resp)
    if (status >= 400L) {
      body <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
      msg  <- body$error$message %||% paste("HTTP", status)
      stop(sprintf("%s failed (HTTP %d): %s", context, status, msg),
           call. = FALSE)
    }
    invisible(resp)
  }

  # ---- 1. Read prompt --------------------------------------------------------
  message("[1/4] Reading prompt ...")
  message(sprintf("    Prompt: %s", prompt_path))
  message(sprintf("    Zip:    %s", zip_path))

  prompt <- paste(readLines(prompt_path, warn = FALSE), collapse = "\n")
  prompt <- gsub("<alpha_code>", alpha_code, prompt, fixed = TRUE)

  zip_kb <- round(file.info(zip_path)$size / 1024, 1)
  message(sprintf("    Zip size: %.1f KB  |  Prompt chars: %s",
                  zip_kb,
                  formatC(nchar(prompt), format = "d", big.mark = ",")))

  # ---- 2. Upload zip to Files API --------------------------------------------
  message("[2/4] Uploading zip to Anthropic Files API ...")

  upload_resp <- .claude_req("https://api.anthropic.com/v1/files") |>
    httr2::req_body_multipart(
      file = curl::form_file(zip_path, type = "application/zip")
    ) |>
    httr2::req_perform()

  .check_resp(upload_resp, "File upload")
  upload_json <- httr2::resp_body_json(upload_resp)
  file_id     <- upload_json$id

  message(sprintf("    Uploaded. file_id = %s", file_id))

  # ---- 3. Call Messages API --------------------------------------------------
  # The zip is referenced as a "container_upload" content block, which is
  # the correct mechanism for delivering binary files to the code execution
  # sandbox via the Files API. ("file" and "document" are not valid block
  # types for this purpose in the raw JSON API.)
  message(sprintf("[3/4] Calling Messages API (model: %s, timeout: %ds) ...",
                  model, timeout_sec))

  body <- list(
    model      = model,
    max_tokens = max_tokens,
    messages   = list(
      list(
        role    = "user",
        content = list(
          list(
            type = "text",
            text = prompt
          ),
          list(
            type    = "container_upload",
            file_id = file_id
          )
        )
      )
    ),
    tools = list(
      list(
        type = "code_execution_20250825",
        name = "code_execution"
      )
    )
  )

  # Retry on 429 (rate limit) and 529 (overloaded) with linear backoff.
  # Waits 60s before retry 1, 120s before retry 2, etc. -- covers the
  # per-minute token rate limit window on all API tiers.
  start_time    <- Sys.time()
  messages_resp <- .claude_req("https://api.anthropic.com/v1/messages") |>
    httr2::req_body_json(body) |>
    httr2::req_retry(
      max_tries    = 5,
      is_transient = function(resp) httr2::resp_status(resp) %in% c(429L, 529L),
      backoff      = function(i) {
        wait <- 60L * i
        message(sprintf("    Rate limit hit -- waiting %d sec before retry %d ...", wait, i))
        wait
      }
    ) |>
    httr2::req_perform()
  elapsed_sec   <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  .check_resp(messages_resp, "Messages API call")
  resp_json <- httr2::resp_body_json(messages_resp)
  message(sprintf("    Done. Elapsed: %.1f sec", elapsed_sec))

  # Save raw response immediately -- available for diagnosis regardless of
  # whether a DOCX is found.
  saveRDS(resp_json, debug_rds)
  message(sprintf("    Response saved to: %s", debug_rds))

  # ---- 4. Extract output file ID and download DOCX ---------------------------
  message("[4/4] Scanning response for DOCX output file ...")

  block_types <- sapply(resp_json$content %||% list(),
                        function(b) b$type %||% "unknown")
  message(sprintf("    Response blocks: %s", paste(block_types, collapse = ", ")))

  output_file_id <- NA_character_

  # The output file_id is nested in bash_code_execution_tool_result blocks as:
  #   block$content$content[[n]]$file_id
  # where block$content is the bash_code_execution_result and
  # block$content$content is a list of bash_code_execution_output objects,
  # each potentially carrying a file_id for a file written to $OUTPUT_DIR.
  # Scan ALL bash result blocks to find it.

  for (block in resp_json$content %||% list()) {

    if (identical(block$type, "bash_code_execution_tool_result")) {
      res <- block$content %||% list()

      # Report non-zero return codes for visibility
      rc <- res$return_code %||% NULL
      if (!is.null(rc) && !is.na(rc) && rc != 0L) {
        message(sprintf("    WARNING: sandbox return_code = %d", rc))
        stderr_txt <- res$stderr %||% ""
        if (nzchar(stderr_txt))
          message(sprintf("    STDERR: %s", substr(stderr_txt, 1, 500)))
      }

      # Scan nested content list for file output blocks
      for (fb in res$content %||% list()) {
        fid <- fb$file_id %||% NULL
        if (!is.null(fid) && !is.na(fid) && nzchar(fid)) {
          output_file_id <- fid
          message(sprintf("    Found output file_id: %s", output_file_id))
          break
        }
      }
    }

    if (!is.na(output_file_id)) break
  }

  # Fallback: scan text blocks for a file_id pattern
  if (is.na(output_file_id)) {
    all_text <- paste(
      sapply(resp_json$content %||% list(),
             function(b) if (!is.null(b$text)) b$text else ""),
      collapse = " "
    )
    fid_match <- regmatches(all_text, regexpr("file_[A-Za-z0-9]+", all_text))
    if (length(fid_match) > 0 && nzchar(fid_match[[1]])) {
      output_file_id <- fid_match[[1]]
      message(sprintf("    Found file_id in response text: %s", output_file_id))
    }
  }

  docx_path_final <- NA_character_

  if (!is.na(output_file_id)) {
    message(sprintf("    Downloading DOCX (file_id: %s) ...", output_file_id))

    dl_resp <- .claude_req(
      sprintf("https://api.anthropic.com/v1/files/%s/content", output_file_id)
    ) |>
      httr2::req_perform()

    .check_resp(dl_resp, "File download")

    raw_bytes       <- httr2::resp_body_raw(dl_resp)
    writeBin(raw_bytes, docx_path)
    docx_path_final <- docx_path

    message(sprintf("    Saved: %s (%.1f KB)",
                    basename(docx_path), length(raw_bytes) / 1024))
  } else {
    message("    No DOCX output file found -- skipping download.")
    message(sprintf(
      "    Run submit_to_claude_diag(readRDS('%s')) to inspect the response.",
      debug_rds))
    warning(
      "No output DOCX file_id found in the response. ",
      "Use submit_to_claude_diag(result$response) to diagnose.",
      call. = FALSE
    )
  }

  # ---- delete uploaded input file --------------------------------------------
  if (delete_input_file && !is.na(file_id)) {
    del_resp <- .claude_req(
      sprintf("https://api.anthropic.com/v1/files/%s", file_id)
    ) |>
      httr2::req_method("DELETE") |>
      httr2::req_perform()
    if (httr2::resp_status(del_resp) < 300L)
      message(sprintf("    Input zip deleted from Anthropic storage (%s).", file_id))
  }

  # ---- token usage and cost estimate -----------------------------------------
  usage         <- resp_json$usage %||% list()
  input_tokens  <- usage$input_tokens  %||% NA_integer_
  output_tokens <- usage$output_tokens %||% NA_integer_
  total_tokens  <- if (!is.na(input_tokens) && !is.na(output_tokens))
    input_tokens + output_tokens else NA_integer_

  # claude-sonnet-4-6 pricing as of May 2026:
  #   Input: $3.00 / 1M tokens | Output: $15.00 / 1M tokens
  est_cost_usd <- sum(
    (input_tokens  %||% 0) *  3.00 / 1e6,
    (output_tokens %||% 0) * 15.00 / 1e6,
    na.rm = TRUE
  )

  message(sprintf(
    "    Tokens -- input: %s | output: %s | total: %s | est. cost: $%.6f",
    na_s(input_tokens), na_s(output_tokens),
    na_s(total_tokens), est_cost_usd))

  # ---- log -------------------------------------------------------------------
  .submit_to_claude_log(
    alpha_code      = alpha_code,
    species_dir     = species_dir,
    model           = model,
    zip_path        = zip_path,
    docx_path_final = docx_path_final,
    elapsed_sec     = elapsed_sec,
    input_tokens    = input_tokens,
    output_tokens   = output_tokens,
    total_tokens    = total_tokens,
    est_cost_usd    = est_cost_usd
  )

  invisible(list(
    docx_path     = docx_path_final,
    elapsed_sec   = elapsed_sec,
    input_tokens  = input_tokens,
    output_tokens = output_tokens,
    total_tokens  = total_tokens,
    est_cost_usd  = est_cost_usd,
    response      = resp_json,
    debug_rds     = debug_rds
  ))
}


# ---- Diagnostic helper -------------------------------------------------------

#' Diagnose a failed submit_to_claude() response
#'
#' Prints a structured summary of the raw API response from
#' \code{\link{submit_to_claude}} to help identify why no DOCX was
#' produced. Shows block types, sandbox stdout/stderr, return codes,
#' and any text Claude returned.
#'
#' @param resp List. The parsed API response, either from
#'   \code{result$response} or
#'   \code{readRDS("<species_dir>/debug_resp.rds")}.
#'
#' @return \code{NULL} invisibly (called for side effects).
#'
#' @examples
#' \dontrun{
#'   submit_to_claude_diag(result$response)
#'   submit_to_claude_diag(readRDS("runs/CASP/debug_resp.rds"))
#' }
#'
#' @export
submit_to_claude_diag <- function(resp) {

  sep <- paste(rep("-", 60), collapse = "")

  cat(sep, "\n")
  cat("submit_to_claude_diag\n")
  cat(sprintf("Stop reason:  %s\n", resp$stop_reason %||% "unknown"))
  cat(sprintf("Usage:        input=%s  output=%s\n",
              resp$usage$input_tokens  %||% "?",
              resp$usage$output_tokens %||% "?"))
  cat(sprintf("Blocks:       %d total\n", length(resp$content %||% list())))
  cat(sep, "\n")

  for (i in seq_along(resp$content %||% list())) {
    block <- resp$content[[i]]
    btype <- block$type %||% "unknown"
    cat(sprintf("\n[Block %d] type = %s\n", i, btype))

    if (btype == "text") {
      txt <- block$text %||% ""
      cat(sprintf("  text (%d chars):\n", nchar(txt)))
      cat(strwrap(substr(txt, 1, 1000), width = 78, prefix = "  "), sep = "\n")
      if (nchar(txt) > 1000) cat("  ... [truncated]\n")

    } else if (btype == "bash_code_execution_tool_result") {
      res <- block$content %||% list()
      cat(sprintf("  return_code: %s\n",    res$return_code %||% "?"))
      cat(sprintf("  stdout (%d chars):\n", nchar(res$stdout %||% "")))
      cat(strwrap(substr(res$stdout %||% "", 1, 1000),
                  width = 78, prefix = "  "), sep = "\n")
      if (nchar(res$stdout %||% "") > 1000) cat("  ... [truncated]\n")

      stderr_txt <- res$stderr %||% ""
      if (nzchar(stderr_txt)) {
        cat(sprintf("  stderr (%d chars):\n", nchar(stderr_txt)))
        cat(strwrap(substr(stderr_txt, 1, 500),
                    width = 78, prefix = "  !! "), sep = "\n")
      }

      file_blocks <- res$content %||% list()
      if (length(file_blocks) > 0) {
        cat(sprintf("  output files: %d\n", length(file_blocks)))
        for (fb in file_blocks)
          cat(sprintf("    file_id: %s\n", fb$file_id %||% "?"))
      } else {
        cat("  output files: none\n")
      }

    } else if (btype == "server_tool_use") {
      cat(sprintf("  name:  %s\n", block$name %||% "?"))
      inp <- block$input %||% list()
      if (!is.null(inp$code)) {
        cat(sprintf("  code snippet (%d chars):\n", nchar(inp$code)))
        cat(strwrap(substr(inp$code, 1, 500),
                    width = 78, prefix = "  "), sep = "\n")
      }

    } else {
      cat(sprintf("  (no detailed parser for type '%s')\n", btype))
    }
  }

  cat("\n", sep, "\n")
  invisible(NULL)
}


# ---- Internal helpers --------------------------------------------------------


#' @noRd
.submit_to_claude_log <- function(alpha_code,
                                  species_dir,
                                  model,
                                  zip_path,
                                  docx_path_final,
                                  elapsed_sec,
                                  input_tokens,
                                  output_tokens,
                                  total_tokens,
                                  est_cost_usd) {

  log_path <- file.path(species_dir, "_log.txt")
  dir.create(dirname(log_path), recursive = TRUE, showWarnings = FALSE)

  sep <- paste(rep("-", 72), collapse = "")
  fmt <- function(key, val) sprintf("%-20s: %s", key, val)

  lines <- c(
    "",
    sep,
    "Processing summary (submit_to_claude)",
    fmt("Timestamp",       format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    fmt("Alpha code",      alpha_code),
    fmt("Model",           model),
    fmt("Zip source",      basename(zip_path)),
    fmt("Output saved",    if (!is.na(docx_path_final))
      basename(docx_path_final) else "None"),
    fmt("Output path",     if (!is.na(docx_path_final))
      docx_path_final else "None"),
    fmt("Elapsed (sec)",   sprintf("%.2f", elapsed_sec)),
    fmt("Input tokens",    na_s(input_tokens)),
    fmt("Output tokens",   na_s(output_tokens)),
    fmt("Total tokens",    na_s(total_tokens)),
    fmt("Est. cost (USD)", sprintf("$%.6f", est_cost_usd))
  )

  write(lines, file = log_path, append = TRUE)
}
