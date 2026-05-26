# ReadRite Accessibility Statement

Last reviewed: May 26, 2026

ReadRite is designed to help reviewers find likely accessibility issues in electronic documents. It is also designed to be usable as accessible Windows desktop software.

## Standards Applied

ReadRite is developed with reference to:

- Section 508 of the Rehabilitation Act, 29 U.S.C. 794d
- Revised 508 Standards, 36 CFR Part 1194
- WCAG 2.0 Level A and AA as incorporated by the Revised 508 Standards
- Revised 508 Chapter 5 Software
- Revised 508 Chapter 6 Support Documentation and Services

Sources:

- U.S. Access Board, [Section 508 of the Rehabilitation Act](https://www.access-board.gov/about/law/ra.html#section-508-federal-electronic-and-information-technology)
- U.S. Access Board, [Revised 508 Standards and 255 Guidelines](https://www.access-board.gov/ict/)
- Section508.gov, [Developing a Website Accessibility Statement](https://www.section508.gov/manage/laws-and-policies/website-accessibility-statement/)

## Accessibility Features

- Uses native Windows WPF controls that integrate with Windows UI Automation.
- Supports keyboard operation for core file selection, scanning, review, and export workflows.
- Provides a command-line report mode for text-only use.
- Uses text labels for status rather than color alone.
- Exports Markdown reports with headings, tables, evidence, recommendations, and references.
- Documents known limitations instead of presenting heuristic results as certification.

## Known Limitations

- ReadRite performs heuristic scanning and cannot certify a document as Section 508 conformant.
- PDF/UA validation, assistive technology testing, and manual reading-order review are still required for final PDF decisions.
- Microsoft Office Accessibility Checker remains necessary for full Word, PowerPoint, and Excel review.
- Browser-based accessibility testing remains necessary for rendered HTML.
- Color contrast, OCR, complex PDF table relationships, JavaScript-generated HTML, and some binary legacy Office internals are outside the current no-dependency scanner scope.

## Feedback and Support

For a federal deployment, replace this section with agency-specific contacts:

- Section 508 Program Manager: `[name and government email]`
- Product owner: `[name and email]`
- Accessibility feedback mechanism: `[URL or email]`
- Formal Section 508 complaint instructions: `[URL]`
- Reasonable accommodation procedures for federal employees and applicants: `[URL]`
- Telecommunications relay service information: `[URL or 711 instructions]`

This structure follows the information categories recommended by Section508.gov for federal digital accessibility statements under OMB M-24-08.
