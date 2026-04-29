# rENM.ai

**AI-assisted synthesis and reporting for the rENM Framework**

## Overview
`rENM.ai` integrates generative AI into the rENM workflow to produce structured, publication-quality narrative outputs from modeled and analyzed data products.

This package focuses on **AI-driven synthesis, interpretation, and document generation**.

## Role in the rENM Framework
Within the modular rENM ecosystem, `rENM.ai`:
- Assembles **AI-ready data packages** from rENM outputs
- Submits structured inputs to large language models
- Generates **narrative reports (DOCX)** from analytical results
- Standardizes AI prompts and output formats

It is the final interpretive layer, transforming quantitative outputs into scientific narratives.

## Key Functions
- `assemble_ai_package()` — Build AI-ready data bundle
- `submit_ai_package()` — Execute end-to-end AI analysis pipeline
- `render_ai_docx()` — Generate structured DOCX reports

## Installation
```r
devtools::install_local("rENM.ai")
```

## Example
```r
library(rENM.ai)

# assemble package
assemble_ai_package("CASP")

# submit to AI pipeline
submit_ai_package("CASP")
```

## Relationship to Other Packages

`rENM.ai` synthesizes outputs from the full rENM pipeline into GenAI interpretations.

## License
See `LICENSE` for details.

---

**rENM Framework**  
A modular system for reconstructing and analyzing long-term ecological niche dynamics.
