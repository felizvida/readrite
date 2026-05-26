$ErrorActionPreference = "Stop"

$script:TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ProjectRoot = Split-Path -Parent $script:TestRoot
$script:MainScript = Join-Path $script:ProjectRoot "PDFAccessibilityChecker.ps1"
$script:WrapperScript = Join-Path $script:ProjectRoot "ReadRite.ps1"

. $script:MainScript -LoadOnly

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message = "Expected condition to be true."
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-False {
    param(
        [bool]$Condition,
        [string]$Message = "Expected condition to be false."
    )

    if ($Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        [AllowNull()]$Expected,
        [AllowNull()]$Actual,
        [string]$Message = ""
    )

    if ($Expected -ne $Actual) {
        if ([string]::IsNullOrWhiteSpace($Message)) {
            $Message = "Expected '$Expected' but got '$Actual'."
        }

        throw $Message
    }
}

function Assert-MatchText {
    param(
        [AllowNull()][string]$Text,
        [string]$Pattern,
        [string]$Message = ""
    )

    if ($Text -notmatch $Pattern) {
        if ([string]::IsNullOrWhiteSpace($Message)) {
            $Message = "Expected text to match '$Pattern'."
        }

        throw $Message
    }
}

function Assert-Throws {
    param(
        [scriptblock]$ScriptBlock,
        [string]$Pattern = ""
    )

    $didThrow = $false
    try {
        & $ScriptBlock | Out-Null
    }
    catch {
        $didThrow = $true
        if (-not [string]::IsNullOrWhiteSpace($Pattern)) {
            Assert-MatchText -Text $_.Exception.Message -Pattern $Pattern -Message "Exception message '$($_.Exception.Message)' did not match '$Pattern'."
        }
    }

    if (-not $didThrow) {
        throw "Expected script block to throw."
    }
}

function Assert-DoesNotThrow {
    param([scriptblock]$ScriptBlock)

    try {
        & $ScriptBlock | Out-Null
    }
    catch {
        throw "Expected script block not to throw, but got: $($_.Exception.Message)"
    }
}

function ConvertTo-TestBytes {
    param([AllowEmptyString()][string]$Text)

    return ,[System.Text.Encoding]::UTF8.GetBytes($Text)
}

function Get-TestCheck {
    param(
        [Parameter(Mandatory = $true)]$Scan,
        [Parameter(Mandatory = $true)][string]$CheckName
    )

    $matches = @($Scan.Checks | Where-Object { $_.Check -eq $CheckName })
    Assert-True -Condition ($matches.Count -gt 0) -Message "Expected check '$CheckName' in $($Scan.FileType)."
    return $matches[0]
}

function Assert-CheckStatus {
    param(
        [Parameter(Mandatory = $true)]$Scan,
        [Parameter(Mandatory = $true)][string]$CheckName,
        [Parameter(Mandatory = $true)][string]$ExpectedStatus
    )

    $check = Get-TestCheck -Scan $Scan -CheckName $CheckName
    Assert-Equal -Expected $ExpectedStatus -Actual $check.Status -Message "Expected '$CheckName' to be '$ExpectedStatus' but got '$($check.Status)'."
}

function Assert-ScanInvariant {
    param([Parameter(Mandatory = $true)]$Scan)

    Assert-True -Condition ($null -ne $Scan.FilePath) -Message "Scan result is missing FilePath."
    Assert-True -Condition ($null -ne $Scan.FileName) -Message "Scan result is missing FileName."
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($Scan.FileType)) -Message "Scan result is missing FileType."
    Assert-True -Condition ($Scan.FileSize -ge 0) -Message "Scan result FileSize must be non-negative."
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($Scan.ItemLabel)) -Message "Scan result is missing ItemLabel."
    Assert-True -Condition ($Scan.EstimatedItems -ge 0) -Message "EstimatedItems must be non-negative."
    Assert-Equal -Expected $Scan.EstimatedItems -Actual $Scan.EstimatedPages -Message "EstimatedPages should mirror EstimatedItems for compatibility."
    Assert-True -Condition ($Scan.Score -ge 0 -and $Scan.Score -le 100) -Message "Score must be between 0 and 100."
    Assert-True -Condition ($null -ne $Scan.Counts) -Message "Scan result is missing Counts."
    Assert-True -Condition ($null -ne $Scan.Checks) -Message "Scan result is missing Checks."

    $checks = @($Scan.Checks)
    Assert-True -Condition ($checks.Count -gt 0) -Message "Every scan should produce at least one check."
    $countSum = $Scan.Counts.Pass + $Scan.Counts.Warning + $Scan.Counts.Fail + $Scan.Counts.Info
    Assert-Equal -Expected $checks.Count -Actual $countSum -Message "Status counts must sum to total checks."

    foreach ($check in $checks) {
        Assert-True -Condition (@("Pass", "Warning", "Fail", "Info") -contains $check.Status) -Message "Unexpected status '$($check.Status)'."
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($check.Category)) -Message "Check is missing Category."
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($check.Check)) -Message "Check is missing Check name."
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($check.Reference)) -Message "Check '$($check.Check)' is missing a standards reference."
    }
}

function New-AccessiblePdfBytes {
    $sample = @"
%PDF-1.7
1 0 obj
<< /Type /Catalog /Lang (en-US) /MarkInfo << /Marked true >> /StructTreeRoot 2 0 R /ViewerPreferences << /DisplayDocTitle true >> /Outlines 3 0 R /Metadata 4 0 R >>
endobj
2 0 obj
<< /Type /StructTreeRoot /K [ << /S /Document >> << /S /H1 >> << /S /P >> << /S /Figure /Alt (Chart showing progress) >> << /S /Table >> << /S /TH >> << /S /Link >> ] /RoleMap << /CustomHeading /H1 >> >>
endobj
5 0 obj
<< /Type /Page /Tabs /S /Resources << /XObject << /Im1 6 0 R >> >> >>
endobj
6 0 obj
<< /Type /XObject /Subtype /Image /Width 10 /Height 10 >>
stream
abc
endstream
endobj
7 0 obj
<< /Title (Accessible sample) >>
endobj
%%EOF
"@

    ConvertTo-TestBytes -Text $sample
}

function New-InaccessiblePdfBytes {
    $sample = @"
%PDF-1.7
1 0 obj
<< /Type /Catalog /AcroForm 7 0 R >>
endobj
2 0 obj
<< /Type /Page /Resources << /XObject << /Im1 6 0 R >> >> >>
endobj
6 0 obj
<< /Type /XObject /Subtype /Image /Width 10 /Height 10 >>
endobj
7 0 obj
<< /Fields [8 0 R] >>
endobj
8 0 obj
<< /FT /Tx >>
endobj
9 0 obj
<< /Encrypt true >>
endobj
%%EOF
"@

    ConvertTo-TestBytes -Text $sample
}

function New-AccessibleDocxBytes {
    New-TestZipBytes -Entries @{
        "[Content_Types].xml" = "<Types></Types>"
        "docProps/core.xml" = "<cp:coreProperties><dc:title>Accessible sample</dc:title></cp:coreProperties>"
        "word/settings.xml" = "<w:settings><w:themeFontLang w:val=""en-US""/></w:settings>"
        "word/document.xml" = "<w:document><w:body><w:p><w:pPr><w:pStyle w:val=""Heading1""/></w:pPr><w:r><w:t>Sample</w:t></w:r></w:p><w:p><w:numPr/></w:p><w:tbl><w:tr><w:trPr><w:tblHeader/></w:trPr></w:tr></w:tbl><w:drawing><wp:docPr id=""1"" name=""Picture 1"" descr=""Progress chart""/><a:blip/></w:drawing><w:hyperlink><w:r><w:t>Learn more</w:t></w:r></w:hyperlink></w:body></w:document>"
    }
}

function New-SparseDocxBytes {
    New-TestZipBytes -Entries @{
        "[Content_Types].xml" = "<Types></Types>"
        "word/document.xml" = "<w:document><w:body><w:p><w:r><w:t>Sparse sample</w:t></w:r></w:p></w:body></w:document>"
    }
}

function New-AccessiblePptxBytes {
    New-TestZipBytes -Entries @{
        "[Content_Types].xml" = "<Types></Types>"
        "docProps/core.xml" = "<cp:coreProperties><dc:title>Accessible sample deck</dc:title></cp:coreProperties>"
        "ppt/slides/slide1.xml" = "<p:sld><p:cSld><p:spTree><p:sp><p:nvSpPr><p:nvPr><p:ph type=""title""/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:rPr lang=""en-US""/><a:t>Sample slide</a:t></a:r></a:p></p:txBody></p:sp><p:pic><p:nvPicPr><p:cNvPr id=""2"" name=""Picture 1"" descr=""Progress chart""/></p:nvPicPr><p:blipFill><a:blip/></p:blipFill></p:pic><a:tbl><a:tblPr firstRow=""1""/></a:tbl></p:spTree></p:cSld></p:sld>"
    }
}

function New-InaccessiblePptxBytes {
    New-TestZipBytes -Entries @{
        "[Content_Types].xml" = "<Types></Types>"
        "ppt/slides/slide1.xml" = "<p:sld><p:cSld><p:spTree><p:pic><p:nvPicPr><p:cNvPr id=""2"" name=""Picture 1""/></p:nvPicPr><p:blipFill><a:blip/></p:blipFill></p:pic><a:tbl><a:tblPr/></a:tbl></p:spTree></p:cSld></p:sld>"
    }
}

function New-AccessibleXlsxBytes {
    New-TestZipBytes -Entries @{
        "[Content_Types].xml" = "<Types></Types>"
        "docProps/core.xml" = "<cp:coreProperties><dc:title>Accessible sample workbook</dc:title></cp:coreProperties>"
        "xl/workbook.xml" = "<workbook><sheets><sheet name=""Data"" sheetId=""1"" r:id=""rId1""/></sheets></workbook>"
        "xl/worksheets/sheet1.xml" = "<worksheet><sheetData><row r=""1""><c r=""A1""><v>Header</v></c></row></sheetData></worksheet>"
        "xl/tables/table1.xml" = "<table name=""DataTable"" displayName=""DataTable"" headerRowCount=""1""></table>"
    }
}

function New-InaccessibleXlsxBytes {
    New-TestZipBytes -Entries @{
        "[Content_Types].xml" = "<Types></Types>"
        "xl/workbook.xml" = "<workbook><sheets><sheet name=""Sheet1"" sheetId=""1"" r:id=""rId1""/></sheets></workbook>"
        "xl/worksheets/sheet1.xml" = "<worksheet><sheetData><row r=""1""><c r=""A1""><v>Header</v></c></row></sheetData><mergeCells><mergeCell ref=""A1:B1""/></mergeCells><hyperlinks><hyperlink ref=""A1"" r:id=""rId1""/></hyperlinks></worksheet>"
        "xl/drawings/drawing1.xml" = "<xdr:wsDr><xdr:pic><xdr:nvPicPr><xdr:cNvPr id=""2"" name=""Picture 1""/></xdr:nvPicPr><xdr:blipFill><a:blip/></xdr:blipFill></xdr:pic></xdr:wsDr>"
    }
}

function Invoke-WithTestFile {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $artifactRoot = Join-Path $script:ProjectRoot "test-output"
    if (Test-Path -LiteralPath $artifactRoot) {
        Remove-Item -LiteralPath $artifactRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    [void](New-Item -Path $artifactRoot -ItemType Directory -Force)
    $path = Join-Path $artifactRoot $FileName
    [System.IO.File]::WriteAllBytes($path, $Bytes)

    try {
        & $Action $path
    }
    finally {
        Remove-Item -LiteralPath $artifactRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Project hygiene" {
    It "parses the main and wrapper scripts" {
        foreach ($path in @($script:MainScript, $script:WrapperScript)) {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
            Assert-Equal -Expected 0 -Actual @($errors).Count -Message "$path has parser errors."
        }
    }

    It "loads scanner functions without launching the GUI" {
        foreach ($name in @("Invoke-DocumentAccessibilityScan", "Invoke-CsvAccessibilityScanData", "Invoke-SelfTest", "Start-PdfAccessibilityChecker")) {
            Assert-True -Condition ($null -ne (Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue)) -Message "Function '$name' was not imported."
        }
    }

    It "keeps the GUI wired to picker, results, and save controls" {
        $content = Get-Content -LiteralPath $script:MainScript -Raw
        Assert-MatchText -Text $content -Pattern "OpenFileDialog"
        Assert-MatchText -Text $content -Pattern "SaveFileDialog"
        Assert-MatchText -Text $content -Pattern "DataGrid"
        Assert-MatchText -Text $content -Pattern "Supported files\|\*\.pdf;\*\.docx;\*\.pptx;\*\.xlsx;\*\.html;\*\.htm;\*\.md;\*\.markdown;\*\.txt;\*\.csv;\*\.doc;\*\.ppt;\*\.xls"
    }
}

Describe "Helper behavior" {
    It "handles empty regex input without StrictMode binding errors" {
        Assert-Equal -Expected 0 -Actual (Get-RegexCount -Text $null -Pattern "x")
        Assert-Equal -Expected 0 -Actual (Get-RegexCount -Text "" -Pattern "x")
        Assert-False -Condition (Test-Regex -Text $null -Pattern "x")
        Assert-False -Condition (Test-Regex -Text "" -Pattern "x")
    }

    It "detects heading level skips" {
        Assert-False -Condition (Test-HeadingLevelSkip -Levels @())
        Assert-False -Condition (Test-HeadingLevelSkip -Levels @(1))
        Assert-False -Condition (Test-HeadingLevelSkip -Levels @(1, 2, 3))
        Assert-True -Condition (Test-HeadingLevelSkip -Levels @(1, 3)) -Message "Expected h1 to h3 to be a skipped level."
    }

    It "strips and decodes HTML text" {
        Assert-Equal -Expected "Save & continue" -Actual (Get-StrippedHtmlText -Html "<span>Save &amp; continue</span>")
    }

    It "scores pass, warning, fail, and info checks predictably" {
        $checks = @(
            (New-CheckResult -Category "A" -Check "Pass" -Status "Pass" -Severity "High" -Reference "WCAG 2.0 1.3.1"),
            (New-CheckResult -Category "A" -Check "Warn" -Status "Warning" -Severity "High" -Reference "WCAG 2.0 1.3.1"),
            (New-CheckResult -Category "A" -Check "Fail" -Status "Fail" -Severity "High" -Reference "WCAG 2.0 1.3.1"),
            (New-CheckResult -Category "A" -Check "Info" -Status "Info" -Reference "WCAG 2.0 1.3.1")
        )
        $score = Get-AccessibilityScore -Checks $checks
        Assert-True -Condition ($score -gt 0 -and $score -lt 100) -Message "Mixed results should produce a partial score."
    }
}

Describe "PDF scans" {
    It "passes core checks for a tagged PDF-like fixture" {
        $scan = Invoke-PdfAccessibilityScanData -Bytes (New-AccessiblePdfBytes) -FilePath "accessible.pdf"
        Assert-ScanInvariant -Scan $scan
        Assert-Equal -Expected "PDF" -Actual $scan.FileType
        Assert-CheckStatus -Scan $scan -CheckName "Tagged PDF structure" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Document language" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Document title" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Image alternate text" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Table header tags" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Assistive technology access" -ExpectedStatus "Pass"
    }

    It "flags missing tags, metadata, image alt text, form names, and encryption" {
        $scan = Invoke-PdfAccessibilityScanData -Bytes (New-InaccessiblePdfBytes) -FilePath "inaccessible.pdf"
        Assert-ScanInvariant -Scan $scan
        Assert-CheckStatus -Scan $scan -CheckName "Tagged PDF structure" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Semantic tags" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Document language" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Document title" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Image alternate text" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Form field labels/tooltips" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Assistive technology access" -ExpectedStatus "Warning"
    }

    It "rejects non-PDF files through the PDF-only entry point" {
        Invoke-WithTestFile -FileName "not-a-pdf.txt" -Bytes (ConvertTo-TestBytes -Text "Hello") -Action {
            param($path)
            Assert-Throws -ScriptBlock { Invoke-PdfAccessibilityScan -FilePath $path } -Pattern "Select a PDF file"
        }
    }
}

Describe "Word scans" {
    It "passes expected checks for an accessible DOCX-like package" {
        $scan = Invoke-WordAccessibilityScanData -Bytes (New-AccessibleDocxBytes) -FilePath "accessible.docx"
        Assert-ScanInvariant -Scan $scan
        Assert-Equal -Expected "Word document" -Actual $scan.FileType
        Assert-CheckStatus -Scan $scan -CheckName "Document title" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Language" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Heading styles" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "List structure" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Image alternate text" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Header rows" -ExpectedStatus "Pass"
    }

    It "handles sparse DOCX packages without empty-string binding errors" {
        $scan = Invoke-WordAccessibilityScanData -Bytes (New-SparseDocxBytes) -FilePath "sparse.docx"
        Assert-ScanInvariant -Scan $scan
        Assert-CheckStatus -Scan $scan -CheckName "Document title" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Language" -ExpectedStatus "Warning"
        Assert-CheckStatus -Scan $scan -CheckName "Heading styles" -ExpectedStatus "Warning"
    }

    It "returns a failed package check for invalid DOCX bytes" {
        $scan = Invoke-WordAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text "not a zip") -FilePath "broken.docx"
        Assert-ScanInvariant -Scan $scan
        Assert-CheckStatus -Scan $scan -CheckName "Open DOCX package" -ExpectedStatus "Fail"
    }
}

Describe "PowerPoint scans" {
    It "passes expected checks for an accessible PPTX-like package" {
        $scan = Invoke-PowerPointAccessibilityScanData -Bytes (New-AccessiblePptxBytes) -FilePath "accessible.pptx"
        Assert-ScanInvariant -Scan $scan
        Assert-Equal -Expected "PowerPoint presentation" -Actual $scan.FileType
        Assert-CheckStatus -Scan $scan -CheckName "Presentation title" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Language" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Slide titles" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Selectable text" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Image alternate text" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Table headers" -ExpectedStatus "Pass"
    }

    It "flags missing PPTX title, slide title, selectable text, and image alt text" {
        $scan = Invoke-PowerPointAccessibilityScanData -Bytes (New-InaccessiblePptxBytes) -FilePath "broken.pptx"
        Assert-ScanInvariant -Scan $scan
        Assert-CheckStatus -Scan $scan -CheckName "Presentation title" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Slide titles" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Selectable text" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Image alternate text" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Table headers" -ExpectedStatus "Warning"
    }

    It "returns a failed package check for invalid PPTX bytes" {
        $scan = Invoke-PowerPointAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text "not a zip") -FilePath "broken.pptx"
        Assert-ScanInvariant -Scan $scan
        Assert-CheckStatus -Scan $scan -CheckName "Open PPTX package" -ExpectedStatus "Fail"
    }
}

Describe "Excel scans" {
    It "passes expected checks for an accessible XLSX-like package" {
        $scan = Invoke-ExcelAccessibilityScanData -Bytes (New-AccessibleXlsxBytes) -FilePath "accessible.xlsx"
        Assert-ScanInvariant -Scan $scan
        Assert-Equal -Expected "Excel workbook" -Actual $scan.FileType
        Assert-CheckStatus -Scan $scan -CheckName "Workbook title" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Worksheet names" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Excel tables" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Image alternate text" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Merged cells" -ExpectedStatus "Pass"
    }

    It "flags generic sheet names, missing tables, image alt text, merged cells, and links" {
        $scan = Invoke-ExcelAccessibilityScanData -Bytes (New-InaccessibleXlsxBytes) -FilePath "broken.xlsx"
        Assert-ScanInvariant -Scan $scan
        Assert-CheckStatus -Scan $scan -CheckName "Workbook title" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Worksheet names" -ExpectedStatus "Warning"
        Assert-CheckStatus -Scan $scan -CheckName "Excel tables" -ExpectedStatus "Warning"
        Assert-CheckStatus -Scan $scan -CheckName "Image alternate text" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Merged cells" -ExpectedStatus "Warning"
        Assert-CheckStatus -Scan $scan -CheckName "Hyperlinks" -ExpectedStatus "Warning"
    }

    It "returns a failed package check for invalid XLSX bytes" {
        $scan = Invoke-ExcelAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text "not a zip") -FilePath "broken.xlsx"
        Assert-ScanInvariant -Scan $scan
        Assert-CheckStatus -Scan $scan -CheckName "Open XLSX package" -ExpectedStatus "Fail"
    }
}

Describe "HTML scans" {
    It "passes expected checks for accessible HTML" {
        $html = @"
<!doctype html>
<html lang="en">
<head><title>Accessible sample</title></head>
<body>
<header><nav><a href="/home">Home</a></nav></header>
<main>
<h1>Sample</h1>
<h2>Section</h2>
<img src="chart.png" alt="Progress chart">
<table><caption>Data</caption><tr><th>Year</th><th>Value</th></tr></table>
<label for="q">Search</label><input id="q">
</main>
</body>
</html>
"@
        $scan = Invoke-HtmlAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text $html) -FilePath "accessible.html"
        Assert-ScanInvariant -Scan $scan
        Assert-CheckStatus -Scan $scan -CheckName "Page title" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Page language" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Headings" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Image alt attributes" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Table headers/captions" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Form labels" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Landmarks" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Link names" -ExpectedStatus "Pass"
    }

    It "flags common HTML accessibility failures" {
        $html = "<html><head></head><body><h3>Skipped</h3><img src=""x.png""><table><tr><td>A</td></tr></table><input id=""q""><a href=""/""></a></body></html>"
        $scan = Invoke-HtmlAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text $html) -FilePath "broken.html"
        Assert-ScanInvariant -Scan $scan
        Assert-CheckStatus -Scan $scan -CheckName "Page title" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Page language" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Headings" -ExpectedStatus "Warning"
        Assert-CheckStatus -Scan $scan -CheckName "Image alt attributes" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Table headers/captions" -ExpectedStatus "Warning"
        Assert-CheckStatus -Scan $scan -CheckName "Form labels" -ExpectedStatus "Warning"
        Assert-CheckStatus -Scan $scan -CheckName "Landmarks" -ExpectedStatus "Warning"
        Assert-CheckStatus -Scan $scan -CheckName "Link names" -ExpectedStatus "Warning"
    }
}

Describe "Markdown scans" {
    It "passes headings, image alt text, and link text for accessible Markdown" {
        $markdown = @"
# Sample

## Section

![Progress chart](chart.png)

[Read more](https://example.test)

| Name | Score |
| --- | --- |
| Alpha | 1 |
"@
        $scan = Invoke-MarkdownAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text $markdown) -FilePath "accessible.md"
        Assert-ScanInvariant -Scan $scan
        Assert-CheckStatus -Scan $scan -CheckName "Headings" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Image alt text" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Link text" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Markdown tables" -ExpectedStatus "Warning"
    }

    It "flags missing Markdown h1, image alt text, and link labels" {
        $markdown = @"
### Skipped

![](chart.png)

[](https://example.test)
"@
        $scan = Invoke-MarkdownAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text $markdown) -FilePath "broken.md"
        Assert-ScanInvariant -Scan $scan
        Assert-CheckStatus -Scan $scan -CheckName "Headings" -ExpectedStatus "Warning"
        Assert-CheckStatus -Scan $scan -CheckName "Image alt text" -ExpectedStatus "Fail"
        Assert-CheckStatus -Scan $scan -CheckName "Link text" -ExpectedStatus "Warning"
    }
}

Describe "Plain text scans" {
    It "reports readable text and long line warnings" {
        $text = "Short line`r`n$(""x"" * 121)"
        $scan = Invoke-PlainTextAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text $text) -FilePath "sample.txt"
        Assert-ScanInvariant -Scan $scan
        Assert-CheckStatus -Scan $scan -CheckName "Readable text" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Semantic structure" -ExpectedStatus "Warning"
        Assert-CheckStatus -Scan $scan -CheckName "Line length" -ExpectedStatus "Warning"
    }

    It "fails empty text content" {
        $scan = Invoke-PlainTextAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text "   `r`n") -FilePath "empty.txt"
        Assert-ScanInvariant -Scan $scan
        Assert-CheckStatus -Scan $scan -CheckName "Readable text" -ExpectedStatus "Fail"
    }
}

Describe "CSV scans" {
    It "handles a two-column comma CSV without scalar Count failures" {
        $csv = "Name,Score`r`nAlpha,1`r`nBeta,2"
        $scan = Invoke-CsvAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text $csv) -FilePath "sample.csv"
        Assert-ScanInvariant -Scan $scan
        Assert-Equal -Expected "CSV data" -Actual $scan.FileType
        Assert-Equal -Expected 3 -Actual $scan.EstimatedItems
        Assert-CheckStatus -Scan $scan -CheckName "Rows and columns" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Header row" -ExpectedStatus "Pass"
        Assert-CheckStatus -Scan $scan -CheckName "Consistent columns" -ExpectedStatus "Pass"
        Assert-MatchText -Text (Get-TestCheck -Scan $scan -CheckName "Rows and columns").Evidence -Pattern "3 rows and 2 columns"
    }

    It "detects semicolon and tab delimiters" {
        $semicolonScan = Invoke-CsvAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text "Name;Score;Level`nAlpha;1;A") -FilePath "semicolon.csv"
        Assert-ScanInvariant -Scan $semicolonScan
        Assert-MatchText -Text (Get-TestCheck -Scan $semicolonScan -CheckName "Rows and columns").Evidence -Pattern "delimiter ';'"

        $tabScan = Invoke-CsvAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text "Name`tScore`tLevel`nAlpha`t1`tA") -FilePath "tab.csv"
        Assert-ScanInvariant -Scan $tabScan
        Assert-MatchText -Text (Get-TestCheck -Scan $tabScan -CheckName "Rows and columns").Evidence -Pattern "delimiter 'tab'"
    }

    It "warns for duplicate, numeric, inconsistent, and empty CSV data" {
        $duplicate = Invoke-CsvAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text "Name,Name`nAlpha,1") -FilePath "duplicate.csv"
        Assert-ScanInvariant -Scan $duplicate
        Assert-CheckStatus -Scan $duplicate -CheckName "Header row" -ExpectedStatus "Warning"

        $numeric = Invoke-CsvAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text "2024,2025`n1,2") -FilePath "numeric.csv"
        Assert-ScanInvariant -Scan $numeric
        Assert-CheckStatus -Scan $numeric -CheckName "Header row" -ExpectedStatus "Warning"

        $inconsistent = Invoke-CsvAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text "Name,Score`nAlpha,1`nBeta") -FilePath "inconsistent.csv"
        Assert-ScanInvariant -Scan $inconsistent
        Assert-CheckStatus -Scan $inconsistent -CheckName "Consistent columns" -ExpectedStatus "Warning"

        $empty = Invoke-CsvAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text "") -FilePath "empty.csv"
        Assert-ScanInvariant -Scan $empty
        Assert-CheckStatus -Scan $empty -CheckName "Rows and columns" -ExpectedStatus "Fail"
    }

    It "routes a zero-byte CSV file to a useful scan result" {
        $emptyBytes = New-Object byte[] 0
        Invoke-WithTestFile -FileName "empty.csv" -Bytes $emptyBytes -Action {
            param($path)
            $scan = Invoke-DocumentAccessibilityScan -FilePath $path
            Assert-ScanInvariant -Scan $scan
            Assert-Equal -Expected "CSV data" -Actual $scan.FileType
            Assert-CheckStatus -Scan $scan -CheckName "Rows and columns" -ExpectedStatus "Fail"
        }
    }
}

Describe "Legacy Office scans" {
    It "returns advisory checks for legacy binary Office files" {
        foreach ($case in @(
            @{ Type = "Legacy Word document"; Extension = "doc" },
            @{ Type = "Legacy PowerPoint presentation"; Extension = "ppt" },
            @{ Type = "Legacy Excel workbook"; Extension = "xls" }
        )) {
            $scan = Invoke-LegacyOfficeAccessibilityScanData -Bytes (ConvertTo-TestBytes -Text "legacy") -FilePath "sample.$($case.Extension)" -FileType $case.Type
            Assert-ScanInvariant -Scan $scan
            Assert-Equal -Expected $case.Type -Actual $scan.FileType
            Assert-CheckStatus -Scan $scan -CheckName "Legacy binary Office format" -ExpectedStatus "Warning"
        }
    }
}

Describe "Report generation" {
    It "creates a Markdown report with escaped table cells and compatibility alias" {
        $scan = New-AccessibilityScanResult -FilePath "sample.csv" -FileType "CSV data" -FileSize 100 -ItemLabel "Estimated rows" -EstimatedItems 2 -Checks @(
            (New-CheckResult -Category "Tables" -Check "Header row" -Status "Pass" -Severity "High" -Evidence "A | B" -Recommendation "Line1`nLine2" -Reference "WCAG 2.0 1.3.1")
        )

        $report = New-AccessibilityReportMarkdown -Scan $scan
        Assert-MatchText -Text $report -Pattern "# ReadRite Accessibility Report"
        Assert-MatchText -Text $report -Pattern "Summary: 1 pass, 0 warning, 0 fail, 0 info"
        Assert-True -Condition ($report.Contains("A \| B")) -Message "Report should escape pipe characters inside table cells."
        Assert-True -Condition ($report.Contains("Line1 Line2")) -Message "Report should flatten newlines inside table cells."

        $aliasReport = New-PdfAccessibilityReportMarkdown -Scan $scan
        Assert-Equal -Expected $report -Actual $aliasReport
    }
}

Describe "File dispatch and CLI integration" {
    It "routes every supported extension to the expected scanner" {
        $cases = @(
            @{ Name = "sample.pdf"; Bytes = (New-AccessiblePdfBytes); Type = "PDF" },
            @{ Name = "sample.docx"; Bytes = (New-AccessibleDocxBytes); Type = "Word document" },
            @{ Name = "sample.pptx"; Bytes = (New-AccessiblePptxBytes); Type = "PowerPoint presentation" },
            @{ Name = "sample.xlsx"; Bytes = (New-AccessibleXlsxBytes); Type = "Excel workbook" },
            @{ Name = "sample.html"; Bytes = (ConvertTo-TestBytes -Text "<html lang=""en""><head><title>T</title></head><body><main><h1>T</h1></main></body></html>"); Type = "HTML document" },
            @{ Name = "sample.htm"; Bytes = (ConvertTo-TestBytes -Text "<html lang=""en""><head><title>T</title></head><body><main><h1>T</h1></main></body></html>"); Type = "HTML document" },
            @{ Name = "sample.md"; Bytes = (ConvertTo-TestBytes -Text "# Title"); Type = "Markdown document" },
            @{ Name = "sample.markdown"; Bytes = (ConvertTo-TestBytes -Text "# Title"); Type = "Markdown document" },
            @{ Name = "sample.txt"; Bytes = (ConvertTo-TestBytes -Text "Plain text"); Type = "Plain text" },
            @{ Name = "sample report.CSV"; Bytes = (ConvertTo-TestBytes -Text "Name,Score`nAlpha,1"); Type = "CSV data" },
            @{ Name = "sample.doc"; Bytes = (ConvertTo-TestBytes -Text "legacy"); Type = "Legacy Word document" },
            @{ Name = "sample.ppt"; Bytes = (ConvertTo-TestBytes -Text "legacy"); Type = "Legacy PowerPoint presentation" },
            @{ Name = "sample.xls"; Bytes = (ConvertTo-TestBytes -Text "legacy"); Type = "Legacy Excel workbook" }
        )

        foreach ($case in $cases) {
            Invoke-WithTestFile -FileName $case.Name -Bytes $case.Bytes -Action {
                param($path)
                $scan = Invoke-DocumentAccessibilityScan -FilePath $path
                Assert-ScanInvariant -Scan $scan
                Assert-Equal -Expected $case.Type -Actual $scan.FileType -Message "$($case.Name) routed to the wrong scanner."
            }
        }
    }

    It "throws clear errors for missing and unsupported files" {
        Assert-Throws -ScriptBlock { Invoke-DocumentAccessibilityScan -FilePath (Join-Path $script:ProjectRoot "missing.pdf") } -Pattern "File not found"
        Invoke-WithTestFile -FileName "sample.json" -Bytes (ConvertTo-TestBytes -Text "{}") -Action {
            param($path)
            Assert-Throws -ScriptBlock { Invoke-DocumentAccessibilityScan -FilePath $path } -Pattern "Unsupported file type"
        }
    }

    It "runs the built-in self-test through the wrapper" {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:WrapperScript -SelfTest 2>&1
        $joined = $output | Out-String
        Assert-Equal -Expected 0 -Actual $LASTEXITCODE -Message "Wrapper self-test exited with code $LASTEXITCODE. Output: $joined"
        Assert-MatchText -Text $joined -Pattern "Self-test passed"
        Assert-MatchText -Text $joined -Pattern "CSV score"
    }

    It "runs a no-GUI CSV scan through the wrapper" {
        Invoke-WithTestFile -FileName "cli.csv" -Bytes (ConvertTo-TestBytes -Text "Name,Score`nAlpha,1") -Action {
            param($path)
            $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:WrapperScript -NoGui -Path $path 2>&1
            $joined = $output | Out-String
            Assert-Equal -Expected 0 -Actual $LASTEXITCODE -Message "No-GUI scan exited with code $LASTEXITCODE. Output: $joined"
            Assert-MatchText -Text $joined -Pattern "# ReadRite Accessibility Report"
            Assert-MatchText -Text $joined -Pattern "Type: CSV data"
        }
    }
}
