# ReadRite Accessibility Test Plan

Last updated: May 26, 2026

This plan describes how to validate ReadRite against the federal accessibility standards relevant to Windows desktop software, electronic content, and support documentation.

## Standards and Guidance

- Section 508 of the Rehabilitation Act, 29 U.S.C. 794d
- Revised 508 Standards, 36 CFR Part 1194
- WCAG 2.0 Level A and AA as incorporated by the Revised 508 Standards
- Revised 508 Chapter 3 Functional Performance Criteria
- Revised 508 Chapter 5 Software
- Revised 508 Chapter 6 Support Documentation and Services
- OMB M-24-08 digital accessibility management expectations

Sources:

- U.S. Access Board, [Section 508 of the Rehabilitation Act](https://www.access-board.gov/about/law/ra.html#section-508-federal-electronic-and-information-technology)
- U.S. Access Board, [Revised 508 Standards and 255 Guidelines](https://www.access-board.gov/ict/)
- Section508.gov, [Tools for Testing Information and Communications Technology](https://www.section508.gov/tools/tools-for-testing-ict/)
- ICT Testing Baseline Alignment Framework, [Purpose and objectives](https://baselinealignment.section508.gov/)

## Test Environments

| Environment | Minimum Coverage |
| --- | --- |
| Windows | Windows 10 and Windows 11 where available |
| Display modes | 100%, 150%, and 200% scaling |
| Contrast modes | Default theme and Windows high contrast theme |
| Keyboard | Full workflow using keyboard only |
| Screen readers | Narrator at minimum; NVDA if available |
| CLI | PowerShell `-NoGui -Path` report workflow |

## Core Test Files

Use representative pass and fail samples for:

- PDF with and without tags, language, title, images, links, tables, forms, and encryption
- DOCX with and without heading styles, title, language, image alt text, tables, and links
- PPTX with and without slide titles, selectable text, image alt text, tables, and links
- XLSX with and without meaningful sheet names, table headers, images, merged cells, and links
- HTML with and without `lang`, `title`, headings, alt text, labels, landmarks, and link names
- Markdown with and without heading hierarchy, image alt text, link labels, and tables
- TXT and CSV with readable and malformed content

## Test Cases

| ID | Area | Procedure | Expected Result |
| --- | --- | --- | --- |
| RR-A11Y-001 | Keyboard access | Launch ReadRite and complete open file, run scan, review findings, and export report using only keyboard. | All interactive controls are reachable and operable. Focus order follows the visual workflow. No keyboard trap occurs. |
| RR-A11Y-002 | Screen reader names | Run the core workflow with Narrator or NVDA. | Buttons, file path field, results grid, recommendation field, and reference field have understandable names and roles. |
| RR-A11Y-003 | Status without color | Review pass, warning, fail, and info results in default and high contrast modes. | Status is conveyed by text, not color alone. |
| RR-A11Y-004 | Scaling and resize | Use 150% and 200% display scaling and resize the app window. | Text remains readable, controls remain usable, and essential content is not clipped. |
| RR-A11Y-005 | CLI workflow | Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ReadRite.ps1 -NoGui -Path .\README.md`. | A plain-text Markdown report is emitted without requiring the graphical UI. |
| RR-A11Y-006 | Report accessibility | Open an exported Markdown report in the target publishing/rendering system. | Report headings, tables, and links are accessible in the rendered output. |
| RR-A11Y-007 | Document scan coverage | Run all core test files. | Expected issues are flagged with status, severity, evidence, recommendation, and reference. False positives and false negatives are logged. |
| RR-A11Y-008 | Assistive technology compatibility | Inspect the UI with Windows Accessibility Insights or another UI Automation inspection tool if available. | Native controls expose names, roles, states, and values. |

## Acceptance Criteria

ReadRite can be accepted for internal use when:

- The complete scan and export workflow passes keyboard-only testing.
- Primary controls and report results are understandable with a screen reader.
- CLI mode works for users who need a text-only workflow.
- Documentation and exported reports are available in accessible electronic form.
- Known limitations are documented and visible to users.
- Any blocking defects are logged with remediation owners and target dates.

## Evidence to Retain

Keep the following with release records:

- Completed test case log
- Screenshots or notes from keyboard and screen-reader testing
- Sample exported Markdown reports
- List of test files used
- Known limitations and remediation backlog
- Version number or commit identifier for the tested build
