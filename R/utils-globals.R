#' @importFrom rENM.core rENM_project_dir get_species_info show_species show_variables
NULL

## Null-coalescing infix operator used across submit_to_chatgpt,
## submit_to_claude, and submit_to_claude_diag.
`%||%` <- function(x, y) if (is.null(x)) y else x

#' @noRd
na_s <- function(x) {
  if (is.null(x) || (length(x) == 1L && is.na(x))) "NA" else as.character(x)
}
