# ReadRite Federal Accessibility Standards

Last updated: May 26, 2026

ReadRite is a Windows-first document accessibility triage tool. It is intended to help reviewers identify likely accessibility barriers in common document formats, not to certify conformance by itself.

## Applicable Federal Standards

### Section 508 of the Rehabilitation Act

Section 508, codified at 29 U.S.C. 794d, requires federal agencies that develop, procure, maintain, or use information and communication technology (ICT) to provide comparable access to information and data for employees and members of the public with disabilities, unless an undue burden applies.

ReadRite is ICT because it is software that receives, inspects, displays, and exports electronic information. It also evaluates electronic content such as PDF, Office, HTML, Markdown, text, and CSV files.

Source: U.S. Access Board, [Section 508 of the Rehabilitation Act](https://www.access-board.gov/about/law/ra.html#section-508-federal-electronic-and-information-technology).

### Revised 508 Standards, 36 CFR Part 1194

The Revised 508 Standards are organized by ICT function. The most relevant parts for ReadRite are:

| Standard | Applies To ReadRite Because | How ReadRite Addresses It |
| --- | --- | --- |
| E205 Electronic Content | ReadRite inspects electronic documents and produces Markdown reports. | The scanner maps document findings to WCAG 2.0 A/AA-oriented checks such as non-text content, document title, language, headings, links, tables, labels, focus order, and programmatic structure. Exported reports use plain Markdown headings and tables. |
| E207 Software | ReadRite is non-web desktop software. | The UI uses native Windows WPF controls rather than custom-drawn controls, supports mouse and keyboard operation, exposes basic control names through Windows UI Automation, and avoids flashing, audio, timing limits, or pointer-only workflows. |
| Chapter 5 Software | The app must expose roles, states, names, and values and remain usable with assistive technology. | Native controls such as Button, TextBox, DataGrid, and Window provide Windows accessibility APIs. ReadRite adds accessible names to primary controls and keeps content selectable where practical. |
| 504 Authoring Tools | ReadRite creates Markdown reports, but is not a general document authoring tool. | Report output is text-based, structured, and avoids inaccessible generated media. ReadRite does not provide authoring templates beyond report generation. |
| E208 and Chapter 6 Support Documentation | ReadRite includes user and conformance documentation. | Project documentation is Markdown with headings, tables, concise language, and explicit accessibility feature notes. |

Source: U.S. Access Board, [Revised 508 Standards and 255 Guidelines](https://www.access-board.gov/ict/).

### WCAG 2.0 Level A and AA

The Revised 508 Standards incorporate WCAG 2.0 Level A and Level AA Success Criteria and Conformance Requirements for covered web and non-web content and software. For non-web documents and non-web software, the standards provide word substitutions and exceptions. Non-web documents and non-web software are not required to conform to WCAG 2.0 Success Criteria 2.4.1, 2.4.5, 3.2.3, and 3.2.4.

ReadRite uses WCAG-oriented checks as the review vocabulary for:

- Non-text content and image alternatives
- Information and relationships
- Meaningful sequence and reading order
- Use of headings and labels
- Link purpose
- Document/page title
- Language
- Form labels and names
- Keyboard/focus order indicators where detectable
- Name, role, and value implications for software and form controls

Sources: U.S. Access Board, [Revised 508 Standards and 255 Guidelines](https://www.access-board.gov/ict/) and [Map of WCAG to Section 508 Functional Performance Criteria](https://www.access-board.gov/ict/wcagtofpc.html).

### OMB M-24-08

OMB M-24-08 strengthens federal management of Section 508 and digital accessibility. It directs agencies to manage accessibility as an ongoing program concern, including accessible digital experiences, accessible content, testing, feedback, and remediation.

ReadRite supports that operating model by producing repeatable heuristic findings, exportable reports, and documentation that can be attached to review or remediation workflows.

Sources: Section508.gov, [Developing a Website Accessibility Statement](https://www.section508.gov/manage/laws-and-policies/website-accessibility-statement/) and [IT Accessibility Laws and Policies](https://www.section508.gov/manage/laws-and-policies/).

## Important Boundary

ReadRite does not replace an agency Section 508 determination, Accessibility Conformance Report, PAC/Acrobat/CommonLook PDF validation, browser accessibility testing, Microsoft Office Accessibility Checker results, or assistive technology testing. It is a first-pass review tool that helps reviewers find issues earlier and document next steps.
