# rENM.ai 0.2.0.9000
* Narrative prompts — the page break before AI-ASSISTED INTERPRETATION is now
  set with `page_break_before` on the heading itself, rather than by adding an
  empty paragraph that holds a break. An empty paragraph falls onto a page of
  its own whenever the preceding text happens to fill its page, and its break
  then pushes the section to the page after, leaving a blank page in the
  assembled report. Whether it happened depended on how the prose fell, so it
  appeared once the paragraph limits changed.
* `render_ai_docx()` — now checks the retrieved narrative for paragraphs that
  end without terminal punctuation and warns, naming each one. A paragraph
  sliced at the word cap passes every check the model performs on itself, so
  the only reliable place to catch it is the document once it is in hand.
  Headings, title lines and the figure list end without punctuation
  legitimately, so only paragraphs of 25 words or more are examined, and a
  paragraph ending in a bare URL is treated as complete. Implemented in
  `.check_docx_paragraphs()`, which reads the paragraph text straight out of
  the `.docx` with no new dependency. The PDF still renders; the warning
  reports rather than blocks.
* Narrative prompts — raised the cap on paragraphs 1 and 2 of CLIMATIC
  SUITABILITY from 125 to 150 words, matching the interpretation paragraphs.
  Each now carries six figures read from its CSV, roughly forty words of
  formatted numerals, and the old cap left no room to report them in whole
  sentences. This is the cause of the truncation; forbidding the truncation
  alone would have left the model writing against a budget it could not meet.
* Narrative prompts — removed the trend classification thresholds and the
  raster area-computation instructions from AREA COMPUTATION RULES. The
  thresholds defined a plus or minus 0.0001 "stable" band that exists
  nowhere in the pipeline: `find_trend_percentages()` and
  `find_boundary_trend_statistics()` classify on strict sign, and
  `find_hot_spots()` on `(A < 0) & (B > 0)`. Since the model still reads the
  rasters to describe where patterns lie, it could have drawn the map from a
  classification the reported figures never used. Replaced with the sign
  convention the pipeline actually applies. The computation instructions
  were both dead, every figure now coming from a CSV, and wrong, describing
  the whole-cell counting removed from `create_hot_spot_map()` for
  overshooting.
* Narrative prompts — paragraph control now forbids truncation explicitly.
  The instruction read "If > limit -> rewrite until valid", which the model
  satisfied by slicing the paragraph at the limit rather than rewriting it.
  Three paragraphs in the first report built on the new CSVs ended
  mid-sentence, each exactly 125 words, the standard limit. The figures the
  CSVs supply pushed those paragraphs over a cap they had previously
  cleared, so the behavior only surfaced once the numbers were correct. The
  prompt now states that slicing is not rewriting, that a paragraph ending
  mid-sentence fails even at a correct word count, and that whole sentences
  should be removed or combined to fit without dropping a required figure.
  Validation checks the last character of every paragraph.
* `submit_to_chatgpt()` — the container file listing is now paginated. The
  retrieval made a single unpaginated request and scanned only the first
  page. The container holds the uploaded bundle, everything the model
  unpacks from it, every intermediate written across the tool calls, and
  the document last, so a run that creates more files pushed the document
  off that page and it was never found. The response saved from one such
  failure shows `status: completed`, twenty `code_interpreter_call` items,
  and the model's own closing message linking the saved file. Nothing was
  wrong with the call. This is what made the step appear to fail at random,
  and the earlier note about designing around a nondeterministic service
  was wrong about the cause. Retrieval now pages to the end, prefers the
  exact filename the prompt requires, falls back to any `.docx`, and the
  failure warning lists the files actually seen in the container.
* `assemble_ai_package()` — added `Suitability-Trend-Percentages.csv` and
  `Suitability-Change-Trend-Percentages.csv` to the default file list, and
  the narrative prompts now take every area and percentage in the first two
  paragraphs from them. Those two paragraphs were the only ones with no CSV
  to read, so the model computed them from the GeoTIFFs, and it did so
  unreliably: two runs on the same raster a day apart reported positive
  trend at 37.54% and then 46.35%, and the second reported every area as
  0.00 km² beside non-zero percentages. Everything drawn from a CSV was
  identical across both runs. The prompts now state that rasters describe
  where a pattern lies and never how much, require each percentage to name
  its denominator, and treat a zero area beside a non-zero percentage as a
  validation failure.
* Narrative prompts — tightened the top-three-states rule, which failed in
  both test runs. The hot-spot sentence listed four states, the fourth
  holding no hot spots at all. Naming a state with zero hot-spot area adds
  nothing.
* Narrative prompts — removed the REFERENCES section. The prompt asked for
  real citations and forbade fabrication in three places, and the first
  report produced under it cited Warren, Glor and Turelli (2008) to the
  wrong journal, volume and pages, alongside an entry that does not appear
  to exist. A model cannot verify a citation from inside the container, so
  the instruction was asking it to certify what it has no way to check. No
  claim in the narrative referred to any listed work, so the section
  supported nothing. The literature that does bear on the report, the
  derivation of the 250 km buffer, is cited in the methods appendix at the
  point the claim is made. Validation now checks that no bibliography
  appears anywhere in the document.
* Narrative prompts — added a statistical support rule governing every
  mention of centroid movement, including the interpretation paragraphs.
  Where the Bayesian credible interval includes zero, the displacement,
  bearing and velocity are still reported, but directional language is
  forbidden and a fixed qualifying construction is required. The first
  report stated both centroid regressions were not significant, then
  described a "directionally coherent shift... tracking northward
  displacement" two paragraphs later. Hedging keyed to a value in the data
  is checkable; hedging left to the model's judgment is not.
* `submit_to_chatgpt()`, `submit_to_claude()` — the model named in the
  AI-assisted interpretation disclosure is now substituted from the `model`
  argument through a `<model>` placeholder, rather than written into the
  prompt by hand. The two agreed at the time of writing, but `model` is an
  argument and the name was in a different file, so overriding the model
  would have left the report disclosing the wrong one. The disclosure now
  carries the model identifier exactly as requested, for example
  `gpt-5.1` rather than `GPT 5.1`.
* `submit_to_chatgpt()`, `submit_to_claude()` — the footer date and time are
  now substituted into the prompt by R, through a `<timestamp>` placeholder,
  rather than asked of the model. The prompt required a time zone and the
  model silently omitted it, and it was being asked to look up a time it
  has no access to.
* `submit_to_chatgpt()` — now warns when the call returns no document, and
  writes the raw response to `Summaries/chatgpt/<CODE>-response.json`. It
  previously returned normally in that case, so a call that consumed five
  minutes and real money looked like a success and surfaced two functions
  later as a missing file, with the response already discarded. The warning
  reports the response status, any incompleteness reason, the output item
  types and how many code-interpreter containers were found, which is
  enough to distinguish a truncated response from one where the model wrote
  prose without ever calling the tool that produces the file.
* Narrative prompts — dropped the framework version from the title-page
  footer, which now reads `(rENM Framework - day month year - hour:minutes
  time zone)`. It was written as a literal `0.2.0` and would have been
  wrong in every report produced after the next release.
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
