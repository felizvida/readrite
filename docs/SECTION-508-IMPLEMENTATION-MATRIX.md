# ReadRite Section 508 Implementation Matrix

Last updated: May 26, 2026

This matrix explains how ReadRite addresses federal accessibility expectations. "Implemented" means the current code directly includes the feature. "Supports" means ReadRite helps reviewers evaluate that requirement in user-supplied documents. "Needs manual verification" means a human tester must still verify conformance with assistive technology or a specialized tool.

## Product Scope

ReadRite is a Windows desktop application written in PowerShell/WPF. It scans PDF, DOCX, PPTX, XLSX, HTML, Markdown, TXT, CSV, and legacy Office files. It exports Markdown accessibility reports.

ReadRite is not a remediation engine and does not claim that a scanned document conforms to Section 508, PDF/UA, or WCAG. It reports likely barriers and recommended remediation actions.

## Software Conformance Approach

| Requirement Area | Federal Reference | Status | How ReadRite Meets or Addresses It |
| --- | --- | --- | --- |
| Comparable access for users with disabilities | Section 508, 29 U.S.C. 794d | Implemented, needs manual verification | ReadRite uses standard Windows controls and avoids custom-rendered widgets, time limits, flashing content, audio-only alerts, or pointer-only workflows. Final validation should include keyboard-only and screen-reader testing. |
| Non-web software applies WCAG with substitutions | Revised 508 E207.2 and E207.2.1 | Implemented, needs manual verification | The app is treated as non-web software. Its core workflows are file selection, run scan, review results, and export report. These workflows use native WPF controls and can be operated without custom gestures. |
| Complete processes | Revised 508 E207.3 | Implemented, needs manual verification | The complete scan process can be completed from the desktop UI or from the command line with `-NoGui -Path`. The CLI provides an alternate text-only workflow for report generation. |
| Native accessibility APIs | Revised 508 Chapter 5 Software | Implemented, needs manual verification | WPF controls expose names, roles, states, values, and keyboard focus through Windows UI Automation. Primary file, run, export, and results controls include accessible names where custom context is needed. |
| Functional Performance Criteria | Revised 508 Chapter 3 | Needs manual verification | ReadRite is designed to support operation without vision through screen-reader-compatible controls and CLI output; without color through text labels and status words; and with limited manipulation through keyboard operation. These must be verified on target Windows builds. |
| Support documentation | Revised 508 E208 and 602 | Implemented | Documentation is written in Markdown with headings, tables, clear labels, and direct links to standards. This documentation lists accessibility features and known limits. |
| Electronic support documentation | Revised 508 602.3 | Implemented | The Markdown documentation is structured so it can be rendered to accessible HTML or another accessible format. Publication owners should verify the rendered output. |

Sources: U.S. Access Board, [Revised 508 Standards and 255 Guidelines](https://www.access-board.gov/ict/) and [Section 508 of the Rehabilitation Act](https://www.access-board.gov/about/law/ra.html#section-508-federal-electronic-and-information-technology).

## Scanner Coverage

| ReadRite Check Family | Main WCAG 2.0 / Section 508 Concern | How ReadRite Supports Review |
| --- | --- | --- |
| Image alternate text | 1.1.1 Non-text Content | Checks for PDF `/Alt` and `/ActualText`, Office shape title/description attributes, HTML `alt`, and Markdown image alt text. Flags missing or suspicious evidence. |
| Semantic structure | 1.3.1 Info and Relationships | Checks for PDF tags, Word heading/list styles, PowerPoint slide titles, Excel table definitions, HTML headings/landmarks/tables/forms, Markdown headings/tables, and CSV header rows. |
| Reading and focus order | 1.3.2 Meaningful Sequence; 2.4.3 Focus Order | Checks for PDF `/Tabs /S`, PowerPoint object-order advisory signals, and document structures that affect reading sequence. Requires manual validation. |
| Use of headings and labels | 2.4.6 Headings and Labels; 3.3.2 Labels or Instructions | Checks headings, slide titles, table headers, form labels/tooltips, and worksheet names. |
| Page or document title | 2.4.2 Page Titled | Checks PDF metadata, Office core properties, and HTML title elements. |
| Link purpose | 2.4.4 Link Purpose | Checks for links and recommends manual review of link labels. HTML and Markdown checks flag empty labels. |
| Language | 3.1.1 Language of Page; 3.1.2 Language of Parts | Checks PDF `/Lang`, Office language hints, and HTML `lang`. Markdown, TXT, and CSV receive publishing-context guidance because those formats usually lack language metadata. |
| Name, role, value | 4.1.2 Name, Role, Value | Checks form labels/tooltips in PDF, Office, and HTML where detectable. The app UI uses native WPF controls to expose roles and values. |
| Assistive technology access | Section 508 software and content requirements | Checks PDF encryption evidence and warns when settings may block text extraction or assistive technology access. |

Source: U.S. Access Board, [Map of WCAG to Section 508 Functional Performance Criteria](https://www.access-board.gov/ict/wcagtofpc.html).

## Known Limitations

- ReadRite uses heuristic inspection of file internals and cannot determine all accessibility failures.
- It does not validate color contrast in Office, PDF, or image content.
- It does not perform OCR on scanned/image-only documents.
- It does not validate PDF tag tree order, table cell associations, artifacting, or PDF/UA conformance.
- It does not execute JavaScript or inspect browser-computed accessibility trees for HTML.
- It does not replace Microsoft Office Accessibility Checker, PAC, Acrobat Preflight, CommonLook, axe, Lighthouse, Trusted Tester, keyboard testing, or screen-reader testing.

## Evidence Generated

ReadRite produces:

- A visible results grid grouped by status, severity, category, check, evidence, recommendation, and reference.
- A Markdown report with the same evidence and WCAG/Section 508-oriented references.
- A command-line report mode for text-only workflows and automated review pipelines.
