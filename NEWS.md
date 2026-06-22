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
