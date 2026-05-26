# ReadRite Automated Testing

ReadRite includes an automated Pester test suite so routine validation does not depend on hand-opening every supported file type.

## Run Locally

From the project root:

```powershell
.\Run-Tests.ps1
```

For CI-style behavior with a non-zero process exit on failure:

```powershell
.\Run-Tests.ps1 -EnableExit
```

The runner uses the newest installed Pester module. If Pester is missing, install it with:

```powershell
Install-Module Pester -Scope CurrentUser -Force
```

## Coverage

The suite covers:

- Script parsing and load-only import behavior
- Core helper functions that previously failed on empty or scalar values
- Scan result invariants: score range, status counts, standards references, estimated item compatibility
- PDF pass and fail fixtures
- DOCX pass, sparse, and invalid-package fixtures
- PPTX pass, fail, and invalid-package fixtures
- XLSX pass, fail, and invalid-package fixtures
- HTML pass and fail fixtures
- Markdown pass and fail fixtures
- Plain text readable, empty, and long-line cases
- CSV comma, semicolon, tab, duplicate header, numeric header, inconsistent row, and empty-file cases
- Legacy DOC/PPT/XLS advisory scans
- Markdown report generation and cell escaping
- Extension routing for every supported file type
- Wrapper self-test and no-GUI CLI report generation

## Continuous Integration

`.github/workflows/test.yml` runs the same suite on Windows for every push and pull request. The workflow installs Pester on the runner, then executes:

```powershell
.\Run-Tests.ps1 -EnableExit
```

## Manual Tests Still Needed

The automated suite reduces repetitive scanner checks, but final release evidence should still include the accessibility validation in `docs/ACCESSIBILITY-TEST-PLAN.md`: keyboard-only operation, screen-reader checks, display scaling, high contrast, and review with the target assistive technology and document tools.
