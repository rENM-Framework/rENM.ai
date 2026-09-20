# rENM.ai 0.2.0.9000

* `assemble_ai_package()` — added
  `Suitability-Trend-Boundary-Statistics.csv` to the default file list. The
  boundary statistics were otherwise invisible to the narrative step, which
  would have described a report containing two rows it had never been told
  existed.
* Narrative prompts — corrected the state-analysis description, which still
  called the first column the state's area. It is the portion of the state
  lying inside the modeled extent, the mislabeling fixed in the tables but
  left live in the prompt.
* Narrative prompts — the modeled extent is now described as the bounding
  box of the GAP range buffered outward by 250 km, so a reader is not left
  to assume it is raw GAP range or occurrence-derived.
* Narrative prompts — areas and percentages are now taken from the CSVs
  wherever the CSVs provide them, rather than recomputed from rasters. The
  pipeline computes these with cell-coverage weighting; recomputation by
  whole-cell counting produced figures that disagreed with the tables in
  the same report, and was the method removed from `create_hot_spot_map()`
  for overshooting on small regions. Where computation is still required,
  the projection is EPSG:5070, matching the pipeline, rather than
  EPSG:6933.
* Narrative prompts — added a DATA RELIABILITY section. A statistic over
  many raster cells is stable and one over few is not, so range-wide
  figures may carry interpretation while small-range states may not be
  presented as evidence on their own.
* Narrative prompts — added a Range Boundary Dynamics paragraph covering
  the interior/ring comparison, with an explicit instruction never to sum
  or average the two zones.
* Narrative prompts — rewrote both interpretation paragraphs. They now ask
  for synthesis across findings rather than a summary of each in turn:
  whether centroid direction agrees with where the trends lie, whether the
  boundary comparison supports or contradicts a shifting range, and what
  the concentration of hot spots implies. A ring more positive than the
  interior suggests an advancing edge; less positive suggests the
  surroundings are deteriorating faster than the occupied range. Neither
  direction is assumed.
* Narrative prompts — removed the hardcoded page numbers from the included
  figures list. Those numbers were circular: the narrative is itself a
  section of the assembled report, so its own length determines where the
  later pages fall, and any number written into it is a guess that holds
  only while the generated prose happens to run the assumed length. The
  figure titles remain. A table of contents generated at assembly time,
  when pagination is actually known, would be the proper fix.
* Narrative prompts — the Claude prompt is now generated from the ChatGPT
  one, differing only in the header, the sandbox GeoTIFF instruction, and
  the model attribution. Keeping the scientific content identical is what
  makes running both models a useful cross-check, and two near-identical
  files maintained by hand would drift.

# rENM.ai 0.1.0

* Initial release.
* Added `assemble_ai_package()` to build and stage AI-ready data bundles for
  submission to ChatGPT and Claude.
* Added `submit_to_chatgpt()` to upload a data bundle to the OpenAI Responses
  API (code interpreter) and retrieve a DOCX interpretive report.
* Added `submit_to_claude()` to upload a data bundle to the Anthropic API
  (Files API with code execution) and retrieve a DOCX interpretive report.
* Added `submit_to_claude_diag()` to diagnose failed `submit_to_claude()`
  responses from a saved debug snapshot.
* Added `render_ai_docx()` to convert AI-generated DOCX reports to PDF via
  LibreOffice in headless mode.
