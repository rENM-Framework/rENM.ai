---

editor_options: 
  markdown: 
    wrap: 72
---

# rENM.ai

![rENM](https://img.shields.io/badge/rENM-framework-blue) ![module](https://img.shields.io/badge/module-ai-informational)

**AI-assisted synthesis and reporting for the rENM Framework**

## Overview

`rENM.ai` integrates generative AI into the rENM workflow to produce structured, publication-quality narrative outputs from modeled and analyzed data products.

This package depends on `rENM.core` for project-directory resolution and species metadata access. All functions accept an optional `project_dir` argument; see `?rENM_project_dir` for configuration options.

## Key functions

| Function | Description |
|------------------------------------|------------------------------------|
| `assemble_ai_package()` | Build and stage AI-ready data bundles for ChatGPT and Claude |
| `submit_to_chatgpt()` | Upload data bundle to OpenAI and retrieve a DOCX report |
| `submit_to_claude()` | Upload data bundle to Anthropic and retrieve a DOCX report |
| `submit_to_claude_diag()` | Diagnose a failed `submit_to_claude()` response |
| `render_ai_docx()` | Convert a generated DOCX report to PDF via LibreOffice |

## System requirements

### LibreOffice

`render_ai_docx()` converts AI-generated DOCX reports to PDF using LibreOffice
in headless mode. LibreOffice must be installed before calling that function.

Download from <https://www.libreoffice.org>. On macOS, `soffice` is **not**
added to `PATH` automatically after installation — run this once in Terminal:

``` bash
sudo ln -s /Applications/LibreOffice.app/Contents/MacOS/soffice /usr/local/bin/soffice
```

On Linux, install via your package manager (`apt install libreoffice` or
equivalent); `soffice` is placed on `PATH` automatically.

If LibreOffice is absent, `render_ai_docx()` stops with a clear error message
listing the install URL and the `sudo ln -s` command above.

### API keys

`submit_to_claude()` and `submit_to_chatgpt()` each require a valid API key
for the respective provider (see **Authentication** below). Keys are billed
per token, independently of any web subscription.

## Installation

``` r
# From GitHub
devtools::install_github("rENM-Framework/rENM.ai")

# From a local source directory
devtools::install_local("rENM.ai")
```

## Getting started

Analytical outputs from `rENM.analysis` and reporting outputs from `rENM.reports` must be present before running the AI pipeline. An API key for the target provider (OpenAI or Anthropic) is required.

``` r
library(rENM.ai)

# Set your API key (or add to ~/.Renviron)
Sys.setenv(ANTHROPIC_API_KEY = "sk-ant-...")
Sys.setenv(OPENAI_API_KEY    = "sk-...")

proj <- "/path/to/your/rENM/project"

# 1. Stage the AI-ready data bundle (runs once per species)
assemble_ai_package("CASP")

# 2. Submit to your preferred provider
result <- submit_to_claude("CASP")   # or submit_to_chatgpt("CASP")
message("Report: ", result$docx_path)

# 3. Convert the DOCX report to PDF
render_ai_docx("CASP")
```

For interactive work, configure the project directory once per session:

``` r
options(rENM.project_dir = "/path/to/your/rENM/project")

assemble_ai_package("CASP")
submit_to_claude("CASP")
```

If no DOCX is produced, use the diagnostic helper:

``` r
# From the return value:
submit_to_claude_diag(result$response)

# Or from the saved debug file:
submit_to_claude_diag(readRDS("runs/CASP/debug_resp.rds"))
```

## AI pipeline

```         
assemble_ai_package()        <- stages data bundle for both providers
        ↓
submit_to_claude()           <- Anthropic API (Files API + code execution)
  or
submit_to_chatgpt()          <- OpenAI Responses API (code interpreter)
        ↓
render_ai_docx()             <- DOCX → PDF via LibreOffice
```

`assemble_ai_package()` writes staged bundles to `<run_dir>/Summaries/claude/` and `<run_dir>/Summaries/chatgpt/`. Generated DOCX reports are written to `<run_dir>/Summaries/pages/`. A debug response snapshot is saved to `<run_dir>/debug_resp.rds` after every `submit_to_claude()` call. All functions append a processing summary to `<run_dir>/_log.txt`.

## Authentication

Both providers require separate API accounts billed per token, independently of any web subscription:

- **Anthropic:** obtain a key at <https://console.anthropic.com> and set `ANTHROPIC_API_KEY`.
- **OpenAI:** obtain a key at <https://platform.openai.com> and set `OPENAI_API_KEY`.

## Role in the rENM Framework

`rENM.ai` is the fifth stage in the pipeline:

```         
rENM.core → rENM.data → rENM.model → rENM.analysis → rENM.ai → rENM.reports
```

It consumes the quantitative outputs produced by `rENM.analysis` and generates AI-authored narrative interpretations that feed into the final reporting layer (`rENM.reports`).

## License

See `LICENSE` for details.

------------------------------------------------------------------------

**rENM Framework** — A modular system for reconstructing and analyzing long-term ecological niche dynamics.
