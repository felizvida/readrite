# ReadRite

A Windows-first desktop app for quick accessibility triage across common document formats. It uses Windows PowerShell and WPF, so it does not require the .NET SDK, Node, Python, NuGet packages, or internet access.

## Run

Double-click `Start-ReadRite.cmd`.

The original launchers are still included for compatibility:

```powershell
.\Start-DocumentAccessibilityChecker.cmd
.\Start-PDFAccessibilityChecker.cmd
```

You can also scan from the command line and print a Markdown report:

```powershell
.\Start-ReadRite.cmd -NoGui -Path "C:\path\document.docx"
```

## Supported Formats

- PDF: `.pdf`
- Word: `.docx`
- PowerPoint: `.pptx`
- Excel: `.xlsx`
- Web: `.html`, `.htm`
- Markdown: `.md`, `.markdown`
- Text/data: `.txt`, `.csv`
- Legacy Office advisory mode: `.doc`, `.ppt`, `.xls`

## What It Checks

- PDF: tagged structure, document language, title metadata, outlines, tab order, alt text signals, table tags, link annotations, form tooltips, metadata, encryption signals
- Word: title, language, heading styles, list structures, image alt text, table header rows, hyperlinks
- PowerPoint: title, language, slide titles, selectable text, image alt text, table hints, reading order advisory, hyperlinks
- Excel: title, worksheet names, Excel table definitions, image alt text, merged cells, hyperlinks, comments/notes
- HTML: page title, language, headings, image alt attributes, table headers/captions, form labels, landmarks, link names
- Markdown: headings, image alt text, link labels, table syntax, publishing-language advisory
- TXT/CSV: readable content, line length, header-row and consistent-column checks for CSV

## Important Limitations

This app performs heuristic scans of document internals. It is useful for finding likely issues quickly, but it is not a certification tool and cannot replace manual review with assistive technology.

For final validation, use this alongside Microsoft Office Accessibility Checker, PAC, Adobe Acrobat Preflight, CommonLook, axe, Lighthouse, source-document review, keyboard testing, and screen-reader testing.

## Federal Accessibility Documentation

- `docs/FEDERAL-STANDARDS.md`: applicable federal standards and citations
- `docs/SECTION-508-IMPLEMENTATION-MATRIX.md`: how ReadRite addresses relevant standards
- `docs/ACCESSIBILITY-TEST-PLAN.md`: validation plan and evidence expectations
- `docs/ACCESSIBILITY-STATEMENT.md`: deployment-ready accessibility statement template
- `docs/TESTING.md`: automated test suite and CI instructions

## Testing

Run the automated Pester suite from the project root:

```powershell
.\Run-Tests.ps1
```

For CI-style failure codes:

```powershell
.\Run-Tests.ps1 -EnableExit
```

The suite generates fixtures for every supported file family and checks scanner behavior, report generation, extension routing, CLI mode, and recent regression cases.

The runner uses Pester 3.x or 4.x. If needed, install the tested version with `Install-Module Pester -RequiredVersion 3.4.0 -Scope CurrentUser -Force`.

## Files

- `ReadRite.ps1`: preferred PowerShell entry point
- `PDFAccessibilityChecker.ps1`: WPF desktop app and scanner logic
- `Run-Tests.ps1`: Pester test runner
- `tests/ReadRite.Tests.ps1`: automated test suite
- `Start-ReadRite.cmd`: preferred Windows launcher
- `Start-DocumentAccessibilityChecker.cmd`: compatibility launcher
- `Start-PDFAccessibilityChecker.cmd`: compatibility launcher
- `README.md`: usage notes
