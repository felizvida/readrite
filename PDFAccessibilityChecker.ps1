param(
    [string]$Path,
    [switch]$NoGui,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-PlainPdfText {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $encoding = [System.Text.Encoding]::GetEncoding(28591)
    $rawText = $encoding.GetString($Bytes)
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine($rawText)

    $streamRegex = [regex]::new("(?s)(?<dict><<.*?>>)\s*stream\r?\n(?<data>.*?)\r?\nendstream")
    foreach ($match in $streamRegex.Matches($rawText)) {
        $dict = $match.Groups["dict"].Value
        if ($dict -notmatch "/FlateDecode") {
            continue
        }

        $start = $match.Groups["data"].Index
        $length = $match.Groups["data"].Length
        if ($start -lt 0 -or $length -le 0 -or ($start + $length) -gt $Bytes.Length) {
            continue
        }

        $streamBytes = New-Object byte[] $length
        [Array]::Copy($Bytes, $start, $streamBytes, 0, $length)
        $expanded = Expand-FlatePdfStream -Bytes $streamBytes
        if ($expanded) {
            [void]$builder.AppendLine()
            [void]$builder.AppendLine($expanded)
        }
    }

    $builder.ToString()
}

function Expand-FlatePdfStream {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $candidates = New-Object System.Collections.Generic.List[byte[]]
    $candidates.Add($Bytes)

    if ($Bytes.Length -gt 6) {
        $withoutZlibHeader = New-Object byte[] ($Bytes.Length - 6)
        [Array]::Copy($Bytes, 2, $withoutZlibHeader, 0, $withoutZlibHeader.Length)
        $candidates.Add($withoutZlibHeader)
    }

    if ($Bytes.Length -gt 2) {
        $withoutHeaderOnly = New-Object byte[] ($Bytes.Length - 2)
        [Array]::Copy($Bytes, 2, $withoutHeaderOnly, 0, $withoutHeaderOnly.Length)
        $candidates.Add($withoutHeaderOnly)
    }

    foreach ($candidate in $candidates) {
        try {
            $input = New-Object System.IO.MemoryStream(,$candidate)
            $deflate = New-Object System.IO.Compression.DeflateStream(
                $input,
                [System.IO.Compression.CompressionMode]::Decompress
            )
            $output = New-Object System.IO.MemoryStream
            $deflate.CopyTo($output)
            $deflate.Dispose()
            $input.Dispose()

            $expandedBytes = $output.ToArray()
            $output.Dispose()
            if ($expandedBytes.Length -gt 0) {
                return [System.Text.Encoding]::GetEncoding(28591).GetString($expandedBytes)
            }
        }
        catch {
            continue
        }
    }

    return $null
}

function Get-RegexCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    return ([regex]::Matches($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
}

function Test-Regex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    return [regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function New-CheckResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Check,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Pass", "Warning", "Fail", "Info")]
        [string]$Status,

        [ValidateSet("Critical", "High", "Medium", "Low", "None")]
        [string]$Severity = "None",

        [string]$Evidence = "",

        [string]$Recommendation = "",

        [string]$Reference = ""
    )

    [pscustomobject]@{
        Status = $Status
        Severity = $Severity
        Category = $Category
        Check = $Check
        Evidence = $Evidence
        Recommendation = $Recommendation
        Reference = $Reference
    }
}

function Get-CheckWeight {
    param([Parameter(Mandatory = $true)]$Check)

    switch ($Check.Severity) {
        "Critical" { return 18 }
        "High" { return 12 }
        "Medium" { return 8 }
        "Low" { return 4 }
        default { return 0 }
    }
}

function Get-AccessibilityScore {
    param([Parameter(Mandatory = $true)][object[]]$Checks)

    $scored = @($Checks | Where-Object { $_.Status -ne "Info" -and (Get-CheckWeight $_) -gt 0 })
    if ($scored.Count -eq 0) {
        return 0
    }

    $max = 0
    $earned = 0
    foreach ($check in $scored) {
        $weight = Get-CheckWeight $check
        $max += $weight
        switch ($check.Status) {
            "Pass" { $earned += $weight }
            "Warning" { $earned += [Math]::Round($weight * 0.45, 2) }
            default { }
        }
    }

    return [Math]::Round(($earned / $max) * 100)
}

function New-AccessibilityScanResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$FileType,

        [Parameter(Mandatory = $true)]
        [long]$FileSize,

        [Parameter(Mandatory = $true)]
        [string]$ItemLabel,

        [Parameter(Mandatory = $true)]
        [int]$EstimatedItems,

        [Parameter(Mandatory = $true)]
        [object[]]$Checks,

        [string]$Notes = "Heuristic scan. Use source-document review, automated accessibility tools, and manual assistive technology testing for certification."
    )

    $checkArray = @($Checks)
    $score = Get-AccessibilityScore -Checks $checkArray
    $statusCounts = @{
        Pass = @($checkArray | Where-Object { $_.Status -eq "Pass" }).Count
        Warning = @($checkArray | Where-Object { $_.Status -eq "Warning" }).Count
        Fail = @($checkArray | Where-Object { $_.Status -eq "Fail" }).Count
        Info = @($checkArray | Where-Object { $_.Status -eq "Info" }).Count
    }

    [pscustomobject]@{
        FilePath = $FilePath
        FileName = [System.IO.Path]::GetFileName($FilePath)
        FileType = $FileType
        FileSize = $FileSize
        ItemLabel = $ItemLabel
        EstimatedItems = $EstimatedItems
        EstimatedPages = $EstimatedItems
        Score = $score
        Counts = $statusCounts
        Checks = $checkArray
        GeneratedAt = [DateTime]::Now
        Notes = $Notes
    }
}

function Get-TextFromBytes {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $utf8 = [System.Text.Encoding]::UTF8.GetString($Bytes)
    if ($utf8 -notmatch [char]0xFFFD) {
        return $utf8
    }

    return [System.Text.Encoding]::Default.GetString($Bytes)
}

function Import-ZipAssemblies {
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
}

function Get-ZipTextEntries {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    Import-ZipAssemblies
    $entries = New-Object System.Collections.Generic.List[object]
    $memory = [System.IO.MemoryStream]::new($Bytes)

    try {
        $archive = [System.IO.Compression.ZipArchive]::new(
            $memory,
            [System.IO.Compression.ZipArchiveMode]::Read,
            $true
        )

        try {
            foreach ($entry in $archive.Entries) {
                if ($entry.FullName -notmatch "\.(xml|rels)$" -and $entry.FullName -ne "[Content_Types].xml") {
                    continue
                }

                $stream = $entry.Open()
                try {
                    $reader = [System.IO.StreamReader]::new($stream)
                    try {
                        $entries.Add([pscustomobject]@{
                            Name = $entry.FullName
                            Text = $reader.ReadToEnd()
                        })
                    }
                    finally {
                        $reader.Dispose()
                    }
                }
                finally {
                    $stream.Dispose()
                }
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $memory.Dispose()
    }

    return @($entries.ToArray())
}

function Get-ZipEntryText {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Entries,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $match = $Entries | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($null -eq $match) {
        return ""
    }

    return [string]$match.Text
}

function Get-OfficeAltTextCount {
    param([Parameter(Mandatory = $true)][string]$Text)

    $count = 0
    $shapeRegex = [regex]::new("<[^>]*(?:docPr|cNvPr)\b[^>]*>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($match in $shapeRegex.Matches($Text)) {
        $tag = $match.Value
        if ($tag -match "\bdescr\s*=\s*`"[^`"]+`"" -or $tag -match "\btitle\s*=\s*`"[^`"]+`"") {
            $count++
        }
    }

    return $count
}

function Get-MarkdownHeadingLevels {
    param([Parameter(Mandatory = $true)][string]$Text)

    $levels = New-Object System.Collections.Generic.List[int]
    foreach ($match in [regex]::Matches($Text, "(?m)^\s{0,3}(#{1,6})\s+\S")) {
        $levels.Add($match.Groups[1].Value.Length)
    }

    return @($levels.ToArray())
}

function Get-HtmlHeadingLevels {
    param([Parameter(Mandatory = $true)][string]$Text)

    $levels = New-Object System.Collections.Generic.List[int]
    foreach ($match in [regex]::Matches($Text, "<h([1-6])\b", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $levels.Add([int]$match.Groups[1].Value)
    }

    return @($levels.ToArray())
}

function Test-HeadingLevelSkip {
    param([int[]]$Levels)

    if ($null -eq $Levels -or $Levels.Count -lt 2) {
        return $false
    }

    for ($i = 1; $i -lt $Levels.Count; $i++) {
        if (($Levels[$i] - $Levels[$i - 1]) -gt 1) {
            return $true
        }
    }

    return $false
}

function Get-StrippedHtmlText {
    param([AllowNull()][string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return ""
    }

    $withoutTags = [regex]::Replace($Html, "<[^>]+>", " ")
    return [System.Net.WebUtility]::HtmlDecode($withoutTags).Trim()
}

function Invoke-DocumentAccessibilityScan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "File not found: $FilePath"
    }

    $extension = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)

    switch ($extension) {
        ".pdf" { return Invoke-PdfAccessibilityScanData -Bytes $bytes -FilePath $FilePath }
        ".docx" { return Invoke-WordAccessibilityScanData -Bytes $bytes -FilePath $FilePath }
        ".pptx" { return Invoke-PowerPointAccessibilityScanData -Bytes $bytes -FilePath $FilePath }
        ".xlsx" { return Invoke-ExcelAccessibilityScanData -Bytes $bytes -FilePath $FilePath }
        ".html" { return Invoke-HtmlAccessibilityScanData -Bytes $bytes -FilePath $FilePath }
        ".htm" { return Invoke-HtmlAccessibilityScanData -Bytes $bytes -FilePath $FilePath }
        ".md" { return Invoke-MarkdownAccessibilityScanData -Bytes $bytes -FilePath $FilePath }
        ".markdown" { return Invoke-MarkdownAccessibilityScanData -Bytes $bytes -FilePath $FilePath }
        ".txt" { return Invoke-PlainTextAccessibilityScanData -Bytes $bytes -FilePath $FilePath }
        ".csv" { return Invoke-CsvAccessibilityScanData -Bytes $bytes -FilePath $FilePath }
        ".doc" { return Invoke-LegacyOfficeAccessibilityScanData -Bytes $bytes -FilePath $FilePath -FileType "Legacy Word document" }
        ".ppt" { return Invoke-LegacyOfficeAccessibilityScanData -Bytes $bytes -FilePath $FilePath -FileType "Legacy PowerPoint presentation" }
        ".xls" { return Invoke-LegacyOfficeAccessibilityScanData -Bytes $bytes -FilePath $FilePath -FileType "Legacy Excel workbook" }
        default {
            throw "Unsupported file type '$extension'. Supported formats: PDF, DOCX, PPTX, XLSX, HTML, Markdown, TXT, CSV, DOC, PPT, XLS."
        }
    }
}

function Invoke-PdfAccessibilityScan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "File not found: $FilePath"
    }

    $extension = [System.IO.Path]::GetExtension($FilePath)
    if ($extension -and $extension.ToLowerInvariant() -ne ".pdf") {
        throw "Select a PDF file. '$extension' is not supported."
    }

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    Invoke-PdfAccessibilityScanData -Bytes $bytes -FilePath $FilePath
}

function Invoke-PdfAccessibilityScanData {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [string]$FilePath = "In-memory PDF"
    )

    $text = ConvertTo-PlainPdfText -Bytes $Bytes
    $checks = New-Object System.Collections.Generic.List[object]

    $pages = Get-RegexCount -Text $text -Pattern "/Type\s*/Page\b(?!s)"
    if ($pages -eq 0) {
        $pages = Get-RegexCount -Text $text -Pattern "/Count\s+\d+"
    }

    $hasMarkedTrue = Test-Regex -Text $text -Pattern "/Marked\s+true\b"
    $hasStructTree = Test-Regex -Text $text -Pattern "/StructTreeRoot\b"
    $hasRoleMap = Test-Regex -Text $text -Pattern "/RoleMap\b"
    $hasLang = Test-Regex -Text $text -Pattern "/Lang\s*(\(|<|/[A-Za-z]{2})"
    $hasTitle = (Test-Regex -Text $text -Pattern "/Title\s*(\(|<)") -or (Test-Regex -Text $text -Pattern "<dc:title|<title")
    $displayDocTitle = Test-Regex -Text $text -Pattern "/DisplayDocTitle\s+true\b"
    $hasOutlines = Test-Regex -Text $text -Pattern "/Outlines\b"
    $hasTabsStructure = Test-Regex -Text $text -Pattern "/Tabs\s*/S\b"
    $hasXmp = (Test-Regex -Text $text -Pattern "/Metadata\b") -or (Test-Regex -Text $text -Pattern "<x:xmpmeta")

    $semanticTagPattern = "/(Document|Part|Art|Sect|Div|P|H[1-6]?|L|LI|Lbl|LBody|Table|TR|TH|TD|Figure|Caption|BlockQuote|Note)\b"
    $semanticTags = Get-RegexCount -Text $text -Pattern $semanticTagPattern
    $headingTags = Get-RegexCount -Text $text -Pattern "/H[1-6]?\b"
    $tableTags = Get-RegexCount -Text $text -Pattern "/Table\b"
    $tableHeaderTags = Get-RegexCount -Text $text -Pattern "/TH\b"
    $images = Get-RegexCount -Text $text -Pattern "/Subtype\s*/Image\b"
    $figures = Get-RegexCount -Text $text -Pattern "/Figure\b"
    $altEntries = (Get-RegexCount -Text $text -Pattern "/Alt\s*(\(|<)") + (Get-RegexCount -Text $text -Pattern "/ActualText\s*(\(|<)")
    $links = Get-RegexCount -Text $text -Pattern "/Subtype\s*/Link\b"
    $linkStructure = Get-RegexCount -Text $text -Pattern "/Link\b"
    $acroForm = Test-Regex -Text $text -Pattern "/AcroForm\b"
    $formFields = Get-RegexCount -Text $text -Pattern "/FT\s*/(Tx|Btn|Ch|Sig)\b"
    $fieldTooltips = Get-RegexCount -Text $text -Pattern "/TU\s*(\(|<)"
    $encrypted = Test-Regex -Text $text -Pattern "/Encrypt\b"

    if ($hasMarkedTrue -and $hasStructTree) {
        $checks.Add((New-CheckResult `
            -Category "Structure" `
            -Check "Tagged PDF structure" `
            -Status "Pass" `
            -Severity "Critical" `
            -Evidence "Found /Marked true and /StructTreeRoot." `
            -Recommendation "Keep validating tag order, nesting, and semantics in a full PDF/UA tool." `
            -Reference "PDF/UA-1 7.1; WCAG 2.0 1.3.1"))
    }
    elseif ($hasMarkedTrue -or $hasStructTree) {
        $checks.Add((New-CheckResult `
            -Category "Structure" `
            -Check "Tagged PDF structure" `
            -Status "Warning" `
            -Severity "Critical" `
            -Evidence "Found only one of /Marked true or /StructTreeRoot." `
            -Recommendation "Repair the PDF so the catalog declares it as marked and includes a complete structure tree." `
            -Reference "PDF/UA-1 7.1; WCAG 2.0 1.3.1"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Structure" `
            -Check "Tagged PDF structure" `
            -Status "Fail" `
            -Severity "Critical" `
            -Evidence "No /Marked true declaration or /StructTreeRoot was found." `
            -Recommendation "Create a tagged PDF from the source document or remediate the PDF in an accessibility authoring tool." `
            -Reference "PDF/UA-1 7.1; WCAG 2.0 1.3.1"))
    }

    if ($semanticTags -gt 0) {
        $checks.Add((New-CheckResult `
            -Category "Structure" `
            -Check "Semantic tags" `
            -Status "Pass" `
            -Severity "High" `
            -Evidence "Found $semanticTags semantic structure tag references." `
            -Recommendation "Review the tag tree for correct reading order and nesting." `
            -Reference "PDF/UA-1 7.4; WCAG 2.0 1.3.1"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Structure" `
            -Check "Semantic tags" `
            -Status "Fail" `
            -Severity "High" `
            -Evidence "No common semantic tag references were found." `
            -Recommendation "Add a logical tag tree with paragraphs, headings, lists, tables, and figures as appropriate." `
            -Reference "PDF/UA-1 7.4; WCAG 2.0 1.3.1"))
    }

    if ($headingTags -gt 0) {
        $checks.Add((New-CheckResult `
            -Category "Structure" `
            -Check "Heading tags" `
            -Status "Pass" `
            -Severity "Medium" `
            -Evidence "Found $headingTags heading tag references." `
            -Recommendation "Confirm the heading levels form a meaningful outline." `
            -Reference "WCAG 2.0 1.3.1; 2.4.6"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Structure" `
            -Check "Heading tags" `
            -Status "Warning" `
            -Severity "Medium" `
            -Evidence "No /H, /H1, /H2, etc. tag references were found." `
            -Recommendation "If the document has sections, tag headings with proper levels." `
            -Reference "WCAG 2.0 1.3.1; 2.4.6"))
    }

    if ($hasRoleMap) {
        $checks.Add((New-CheckResult `
            -Category "Structure" `
            -Check "Custom tag role map" `
            -Status "Pass" `
            -Severity "Low" `
            -Evidence "Found /RoleMap." `
            -Recommendation "Confirm custom roles map to standard PDF structure types." `
            -Reference "PDF/UA-1 7.1"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Structure" `
            -Check "Custom tag role map" `
            -Status "Info" `
            -Evidence "No /RoleMap was found. This is acceptable when only standard tags are used." `
            -Recommendation "If the PDF uses custom tags, add a role map to standard structure types." `
            -Reference "PDF/UA-1 7.1"))
    }

    if ($hasLang) {
        $checks.Add((New-CheckResult `
            -Category "Document" `
            -Check "Document language" `
            -Status "Pass" `
            -Severity "High" `
            -Evidence "Found a /Lang entry." `
            -Recommendation "Confirm the language value matches the document and mark language changes inside content." `
            -Reference "PDF/UA-1 7.2; WCAG 2.0 3.1.1"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Document" `
            -Check "Document language" `
            -Status "Fail" `
            -Severity "High" `
            -Evidence "No /Lang entry was found." `
            -Recommendation "Set the document language, for example en-US, in the PDF catalog or source document." `
            -Reference "PDF/UA-1 7.2; WCAG 2.0 3.1.1"))
    }

    if ($hasTitle) {
        $checks.Add((New-CheckResult `
            -Category "Document" `
            -Check "Document title" `
            -Status "Pass" `
            -Severity "Medium" `
            -Evidence "Found a title in PDF metadata or XMP." `
            -Recommendation "Confirm the title is concise and identifies the document." `
            -Reference "WCAG 2.0 2.4.2"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Document" `
            -Check "Document title" `
            -Status "Fail" `
            -Severity "Medium" `
            -Evidence "No PDF title metadata was found." `
            -Recommendation "Add a meaningful document title in the source file or PDF properties." `
            -Reference "WCAG 2.0 2.4.2"))
    }

    if ($displayDocTitle) {
        $checks.Add((New-CheckResult `
            -Category "Document" `
            -Check "Display document title" `
            -Status "Pass" `
            -Severity "Low" `
            -Evidence "Found /DisplayDocTitle true." `
            -Recommendation "Keep viewer preferences set to show the document title." `
            -Reference "WCAG 2.0 2.4.2"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Document" `
            -Check "Display document title" `
            -Status "Warning" `
            -Severity "Low" `
            -Evidence "No /DisplayDocTitle true viewer preference was found." `
            -Recommendation "Set viewer preferences to display the document title instead of the filename." `
            -Reference "WCAG 2.0 2.4.2"))
    }

    if ($pages -gt 9 -and -not $hasOutlines) {
        $checks.Add((New-CheckResult `
            -Category "Navigation" `
            -Check "Bookmarks/outlines" `
            -Status "Warning" `
            -Severity "Medium" `
            -Evidence "Estimated $pages pages and no /Outlines entry found." `
            -Recommendation "Add bookmarks for longer documents so users can navigate major sections." `
            -Reference "WCAG 2.0 2.4.5; 2.4.6"))
    }
    elseif ($hasOutlines) {
        $checks.Add((New-CheckResult `
            -Category "Navigation" `
            -Check "Bookmarks/outlines" `
            -Status "Pass" `
            -Severity "Medium" `
            -Evidence "Found /Outlines." `
            -Recommendation "Confirm bookmark labels are meaningful and match the document structure." `
            -Reference "WCAG 2.0 2.4.5; 2.4.6"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Navigation" `
            -Check "Bookmarks/outlines" `
            -Status "Info" `
            -Evidence "No /Outlines entry found. Short documents may not need bookmarks." `
            -Recommendation "Add bookmarks when the document has multiple sections or many pages." `
            -Reference "WCAG 2.0 2.4.5"))
    }

    if ($hasTabsStructure) {
        $checks.Add((New-CheckResult `
            -Category "Navigation" `
            -Check "Page tab order" `
            -Status "Pass" `
            -Severity "Medium" `
            -Evidence "Found /Tabs /S." `
            -Recommendation "Confirm keyboard focus follows the intended reading order on every page." `
            -Reference "PDF/UA-1 7.18.3; WCAG 2.0 2.4.3"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Navigation" `
            -Check "Page tab order" `
            -Status "Warning" `
            -Severity "Medium" `
            -Evidence "No /Tabs /S entry was found." `
            -Recommendation "Set page tab order to use the document structure, especially for forms and links." `
            -Reference "PDF/UA-1 7.18.3; WCAG 2.0 2.4.3"))
    }

    if ($images -eq 0) {
        $checks.Add((New-CheckResult `
            -Category "Images" `
            -Check "Image alternate text" `
            -Status "Pass" `
            -Severity "High" `
            -Evidence "No image XObjects were found." `
            -Recommendation "No image alternate text action detected by this scan." `
            -Reference "WCAG 2.0 1.1.1"))
    }
    elseif ($altEntries -ge $images -or ($figures -gt 0 -and $altEntries -gt 0)) {
        $checks.Add((New-CheckResult `
            -Category "Images" `
            -Check "Image alternate text" `
            -Status "Pass" `
            -Severity "High" `
            -Evidence "Found $images image XObjects, $figures figure tags, and $altEntries alternate/actual text entries." `
            -Recommendation "Manually verify each meaningful image has accurate alternate text and decorative images are artifacted." `
            -Reference "PDF/UA-1 7.3; WCAG 2.0 1.1.1"))
    }
    elseif ($altEntries -gt 0) {
        $checks.Add((New-CheckResult `
            -Category "Images" `
            -Check "Image alternate text" `
            -Status "Warning" `
            -Severity "High" `
            -Evidence "Found $images image XObjects but only $altEntries alternate/actual text entries." `
            -Recommendation "Review every meaningful image and add /Alt text or mark decorative images as artifacts." `
            -Reference "PDF/UA-1 7.3; WCAG 2.0 1.1.1"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Images" `
            -Check "Image alternate text" `
            -Status "Fail" `
            -Severity "High" `
            -Evidence "Found $images image XObjects and no /Alt or /ActualText entries." `
            -Recommendation "Add alternate text for meaningful images and artifact decorative images." `
            -Reference "PDF/UA-1 7.3; WCAG 2.0 1.1.1"))
    }

    if ($tableTags -gt 0 -and $tableHeaderTags -gt 0) {
        $checks.Add((New-CheckResult `
            -Category "Tables" `
            -Check "Table header tags" `
            -Status "Pass" `
            -Severity "High" `
            -Evidence "Found $tableTags table tag references and $tableHeaderTags table header references." `
            -Recommendation "Confirm table headers, scope, and cell relationships are correct." `
            -Reference "PDF/UA-1 7.5; WCAG 2.0 1.3.1"))
    }
    elseif ($tableTags -gt 0) {
        $checks.Add((New-CheckResult `
            -Category "Tables" `
            -Check "Table header tags" `
            -Status "Warning" `
            -Severity "High" `
            -Evidence "Found $tableTags table tag references but no /TH references." `
            -Recommendation "Use /TH tags for table headers and verify relationships for complex tables." `
            -Reference "PDF/UA-1 7.5; WCAG 2.0 1.3.1"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Tables" `
            -Check "Table header tags" `
            -Status "Info" `
            -Evidence "No /Table tags were found." `
            -Recommendation "If the document has visual tables, tag them as tables with header cells." `
            -Reference "PDF/UA-1 7.5; WCAG 2.0 1.3.1"))
    }

    if ($links -eq 0) {
        $checks.Add((New-CheckResult `
            -Category "Links" `
            -Check "Link annotations" `
            -Status "Info" `
            -Evidence "No link annotations were found." `
            -Recommendation "No link action detected by this scan." `
            -Reference "WCAG 2.0 2.4.4"))
    }
    elseif ($hasStructTree -and $linkStructure -gt 0) {
        $checks.Add((New-CheckResult `
            -Category "Links" `
            -Check "Link annotations" `
            -Status "Pass" `
            -Severity "Medium" `
            -Evidence "Found $links link annotations and link structure references." `
            -Recommendation "Confirm each link has meaningful visible or alternate text." `
            -Reference "PDF/UA-1 7.18.5; WCAG 2.0 2.4.4"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Links" `
            -Check "Link annotations" `
            -Status "Warning" `
            -Severity "Medium" `
            -Evidence "Found $links link annotations but limited link structure evidence." `
            -Recommendation "Ensure link annotations are included in the tag tree and have meaningful link text." `
            -Reference "PDF/UA-1 7.18.5; WCAG 2.0 2.4.4"))
    }

    if ($acroForm -or $formFields -gt 0) {
        if ($fieldTooltips -ge $formFields -and $formFields -gt 0) {
            $checks.Add((New-CheckResult `
                -Category "Forms" `
                -Check "Form field labels/tooltips" `
                -Status "Pass" `
                -Severity "High" `
                -Evidence "Found $formFields form fields and $fieldTooltips tooltip/name entries." `
                -Recommendation "Confirm every form control has a visible label, accessible name, and logical tab order." `
                -Reference "PDF/UA-1 7.18.4; WCAG 2.0 1.3.1; 3.3.2"))
        }
        elseif ($fieldTooltips -gt 0) {
            $checks.Add((New-CheckResult `
                -Category "Forms" `
                -Check "Form field labels/tooltips" `
                -Status "Warning" `
                -Severity "High" `
                -Evidence "Found $formFields form fields and $fieldTooltips tooltip/name entries." `
                -Recommendation "Add tooltips or accessible names for every form field and verify visible labels." `
                -Reference "PDF/UA-1 7.18.4; WCAG 2.0 1.3.1; 3.3.2"))
        }
        else {
            $checks.Add((New-CheckResult `
                -Category "Forms" `
                -Check "Form field labels/tooltips" `
                -Status "Fail" `
                -Severity "High" `
                -Evidence "Found form fields but no /TU tooltip entries." `
                -Recommendation "Add accessible names/tooltips and visible instructions for all form fields." `
                -Reference "PDF/UA-1 7.18.4; WCAG 2.0 1.3.1; 3.3.2"))
        }
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Forms" `
            -Check "Form field labels/tooltips" `
            -Status "Info" `
            -Evidence "No AcroForm fields were found." `
            -Recommendation "No form action detected by this scan." `
            -Reference "WCAG 2.0 3.3.2"))
    }

    if ($hasXmp) {
        $checks.Add((New-CheckResult `
            -Category "Metadata" `
            -Check "Metadata packet" `
            -Status "Pass" `
            -Severity "Low" `
            -Evidence "Found PDF metadata or XMP metadata." `
            -Recommendation "Confirm metadata values are accurate and do not expose sensitive information." `
            -Reference "PDF/UA-1 7.1"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Metadata" `
            -Check "Metadata packet" `
            -Status "Warning" `
            -Severity "Low" `
            -Evidence "No PDF metadata packet was found." `
            -Recommendation "Add document metadata from the source document or PDF properties." `
            -Reference "PDF/UA-1 7.1"))
    }

    if ($encrypted) {
        $checks.Add((New-CheckResult `
            -Category "Security" `
            -Check "Assistive technology access" `
            -Status "Warning" `
            -Severity "High" `
            -Evidence "Found /Encrypt in the PDF." `
            -Recommendation "Verify security settings allow text extraction and assistive technology access." `
            -Reference "WCAG 2.0 4.1.2"))
    }
    else {
        $checks.Add((New-CheckResult `
            -Category "Security" `
            -Check "Assistive technology access" `
            -Status "Pass" `
            -Severity "High" `
            -Evidence "No /Encrypt entry was found." `
            -Recommendation "Keep security settings compatible with assistive technology." `
            -Reference "WCAG 2.0 4.1.2"))
    }

    New-AccessibilityScanResult `
        -FilePath $FilePath `
        -FileType "PDF" `
        -FileSize $Bytes.Length `
        -ItemLabel "Estimated pages" `
        -EstimatedItems $pages `
        -Checks @($checks.ToArray()) `
        -Notes "Heuristic PDF scan. Use PAC, Acrobat Preflight, CommonLook, or manual assistive technology testing for certification."
}

function Invoke-WordAccessibilityScanData {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [string]$FilePath = "In-memory DOCX"
    )

    $checks = New-Object System.Collections.Generic.List[object]

    try {
        $entries = Get-ZipTextEntries -Bytes $Bytes
    }
    catch {
        [void]$checks.Add((New-CheckResult -Category "File" -Check "Open DOCX package" -Status "Fail" -Severity "Critical" -Evidence $_.Exception.Message -Recommendation "Repair the file or save it again as a modern .docx document." -Reference "WCAG 2.0 4.1.2"))
        return New-AccessibilityScanResult -FilePath $FilePath -FileType "Word document" -FileSize $Bytes.Length -ItemLabel "Estimated sections" -EstimatedItems 0 -Checks @($checks.ToArray())
    }

    $document = Get-ZipEntryText -Entries $entries -Name "word/document.xml"
    $settings = Get-ZipEntryText -Entries $entries -Name "word/settings.xml"
    $core = Get-ZipEntryText -Entries $entries -Name "docProps/core.xml"
    $allText = ($entries | ForEach-Object { $_.Text }) -join "`n"

    $paragraphs = Get-RegexCount -Text $document -Pattern "<w:p\b"
    $headings = Get-RegexCount -Text $document -Pattern "<w:pStyle\b[^>]*w:val\s*=\s*`"Heading[1-6]`""
    $tables = Get-RegexCount -Text $document -Pattern "<w:tbl\b"
    $tableHeaders = Get-RegexCount -Text $document -Pattern "<w:tblHeader\b"
    $images = Get-RegexCount -Text $allText -Pattern "<a:blip\b"
    $altTextCount = Get-OfficeAltTextCount -Text $allText
    $links = (Get-RegexCount -Text $document -Pattern "<w:hyperlink\b") + (Get-RegexCount -Text $allText -Pattern "relationships/hyperlink")
    $lists = Get-RegexCount -Text $document -Pattern "<w:numPr\b"
    $hasTitle = Test-Regex -Text $core -Pattern "<dc:title>\s*[^<]+"
    $hasLanguage = (Test-Regex -Text $document -Pattern "<w:lang\b") -or (Test-Regex -Text $settings -Pattern "<w:themeFontLang\b")

    if ($hasTitle) {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Document title" -Status "Pass" -Severity "Medium" -Evidence "Found a title in docProps/core.xml." -Recommendation "Confirm the title clearly identifies the document." -Reference "WCAG 2.0 2.4.2"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Document title" -Status "Fail" -Severity "Medium" -Evidence "No core title metadata found." -Recommendation "Add a document title in Word File > Info > Properties." -Reference "WCAG 2.0 2.4.2"))
    }

    if ($hasLanguage) {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Language" -Status "Pass" -Severity "High" -Evidence "Found Word language settings or run language markup." -Recommendation "Confirm the default language and any language changes are correct." -Reference "WCAG 2.0 3.1.1; 3.1.2"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Language" -Status "Warning" -Severity "High" -Evidence "No language settings were found in inspected XML." -Recommendation "Set proofing language for the document and language changes." -Reference "WCAG 2.0 3.1.1; 3.1.2"))
    }

    if ($headings -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Heading styles" -Status "Pass" -Severity "High" -Evidence "Found $headings Heading 1-6 paragraph styles." -Recommendation "Confirm headings are nested in order and are not used only for visual styling." -Reference "WCAG 2.0 1.3.1; 2.4.6"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Heading styles" -Status "Warning" -Severity "High" -Evidence "No Heading 1-6 paragraph styles were found." -Recommendation "Use built-in Word heading styles for document sections." -Reference "WCAG 2.0 1.3.1; 2.4.6"))
    }

    if ($lists -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "List structure" -Status "Pass" -Severity "Medium" -Evidence "Found $lists numbered/bulleted list references." -Recommendation "Confirm visual lists use Word list tools rather than typed symbols." -Reference "WCAG 2.0 1.3.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "List structure" -Status "Info" -Evidence "No Word list structures were found." -Recommendation "Use Word list tools for any bulleted or numbered content." -Reference "WCAG 2.0 1.3.1"))
    }

    if ($images -eq 0) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alternate text" -Status "Pass" -Severity "High" -Evidence "No embedded image references were found." -Recommendation "No image action detected by this scan." -Reference "WCAG 2.0 1.1.1"))
    }
    elseif ($altTextCount -ge $images) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alternate text" -Status "Pass" -Severity "High" -Evidence "Found $images image references and $altTextCount shape title/description entries." -Recommendation "Manually confirm each meaningful image has accurate alt text and decorative images are marked decorative." -Reference "WCAG 2.0 1.1.1"))
    }
    elseif ($altTextCount -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alternate text" -Status "Warning" -Severity "High" -Evidence "Found $images image references and $altTextCount shape title/description entries." -Recommendation "Add alt text to meaningful images and mark decorative images as decorative." -Reference "WCAG 2.0 1.1.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alternate text" -Status "Fail" -Severity "High" -Evidence "Found $images image references and no shape title/description entries." -Recommendation "Add alt text to meaningful images or mark them decorative in Word." -Reference "WCAG 2.0 1.1.1"))
    }

    if ($tables -gt 0 -and $tableHeaders -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Header rows" -Status "Pass" -Severity "High" -Evidence "Found $tables tables and $tableHeaders repeated header row markers." -Recommendation "Confirm header rows, simple structure, and reading order." -Reference "WCAG 2.0 1.3.1"))
    }
    elseif ($tables -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Header rows" -Status "Warning" -Severity "High" -Evidence "Found $tables tables and no repeated header row markers." -Recommendation "Use table header rows and avoid layout tables where possible." -Reference "WCAG 2.0 1.3.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Header rows" -Status "Info" -Evidence "No Word tables were found." -Recommendation "Use real tables with headers for tabular data." -Reference "WCAG 2.0 1.3.1"))
    }

    if ($links -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Links" -Check "Hyperlinks" -Status "Warning" -Severity "Medium" -Evidence "Found $links hyperlink references." -Recommendation "Confirm link text is meaningful out of context and not a raw URL unless the URL is the intended label." -Reference "WCAG 2.0 2.4.4"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Links" -Check "Hyperlinks" -Status "Info" -Evidence "No hyperlinks were found." -Recommendation "No link action detected by this scan." -Reference "WCAG 2.0 2.4.4"))
    }

    New-AccessibilityScanResult -FilePath $FilePath -FileType "Word document" -FileSize $Bytes.Length -ItemLabel "Estimated paragraphs" -EstimatedItems $paragraphs -Checks @($checks.ToArray())
}

function Invoke-PowerPointAccessibilityScanData {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [string]$FilePath = "In-memory PPTX"
    )

    $checks = New-Object System.Collections.Generic.List[object]

    try {
        $entries = Get-ZipTextEntries -Bytes $Bytes
    }
    catch {
        [void]$checks.Add((New-CheckResult -Category "File" -Check "Open PPTX package" -Status "Fail" -Severity "Critical" -Evidence $_.Exception.Message -Recommendation "Repair the file or save it again as a modern .pptx presentation." -Reference "WCAG 2.0 4.1.2"))
        return New-AccessibilityScanResult -FilePath $FilePath -FileType "PowerPoint presentation" -FileSize $Bytes.Length -ItemLabel "Estimated slides" -EstimatedItems 0 -Checks @($checks.ToArray())
    }

    $slides = @($entries | Where-Object { $_.Name -match "^ppt/slides/slide\d+\.xml$" })
    $slideText = ($slides | ForEach-Object { $_.Text }) -join "`n"
    $allText = ($entries | ForEach-Object { $_.Text }) -join "`n"
    $core = Get-ZipEntryText -Entries $entries -Name "docProps/core.xml"

    $slideCount = $slides.Count
    $hasTitle = Test-Regex -Text $core -Pattern "<dc:title>\s*[^<]+"
    $slideTitlePlaceholders = Get-RegexCount -Text $slideText -Pattern "<p:ph\b[^>]*type\s*=\s*`"(ctrTitle|title)`""
    $textRuns = Get-RegexCount -Text $slideText -Pattern "<a:t>"
    $images = Get-RegexCount -Text $allText -Pattern "<a:blip\b"
    $altTextCount = Get-OfficeAltTextCount -Text $allText
    $tables = Get-RegexCount -Text $slideText -Pattern "<a:tbl\b"
    $headerTables = Get-RegexCount -Text $slideText -Pattern "firstRow\s*=\s*`"1`""
    $links = Get-RegexCount -Text $allText -Pattern "hlinkClick|relationships/hyperlink"
    $shapes = Get-RegexCount -Text $slideText -Pattern "<p:sp\b"
    $language = Get-RegexCount -Text $slideText -Pattern "\blang\s*=\s*`"[^`"]+`""

    if ($hasTitle) {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Presentation title" -Status "Pass" -Severity "Medium" -Evidence "Found a title in docProps/core.xml." -Recommendation "Confirm the title identifies the presentation." -Reference "WCAG 2.0 2.4.2"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Presentation title" -Status "Fail" -Severity "Medium" -Evidence "No core title metadata found." -Recommendation "Add a presentation title in File > Info > Properties." -Reference "WCAG 2.0 2.4.2"))
    }

    if ($language -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Language" -Status "Pass" -Severity "Medium" -Evidence "Found language attributes in slide text." -Recommendation "Confirm slide language and language changes are correct." -Reference "WCAG 2.0 3.1.1; 3.1.2"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Language" -Status "Warning" -Severity "Medium" -Evidence "No slide language attributes were found." -Recommendation "Set proofing language for presentation text." -Reference "WCAG 2.0 3.1.1; 3.1.2"))
    }

    if ($slideCount -gt 0 -and $slideTitlePlaceholders -ge $slideCount) {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Slide titles" -Status "Pass" -Severity "High" -Evidence "Found $slideTitlePlaceholders title placeholders across $slideCount slides." -Recommendation "Confirm every slide has a unique, descriptive title." -Reference "WCAG 2.0 2.4.6"))
    }
    elseif ($slideTitlePlaceholders -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Slide titles" -Status "Warning" -Severity "High" -Evidence "Found $slideTitlePlaceholders title placeholders across $slideCount slides." -Recommendation "Give every slide a unique, descriptive title." -Reference "WCAG 2.0 2.4.6"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Slide titles" -Status "Fail" -Severity "High" -Evidence "No slide title placeholders were found." -Recommendation "Use layouts with title placeholders and give every slide a title." -Reference "WCAG 2.0 2.4.6"))
    }

    if ($textRuns -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Selectable text" -Status "Pass" -Severity "High" -Evidence "Found $textRuns text runs." -Recommendation "Keep text as real PowerPoint text rather than flattened images." -Reference "WCAG 2.0 1.4.5"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Selectable text" -Status "Fail" -Severity "High" -Evidence "No slide text runs were found." -Recommendation "Avoid image-only slides; use real text and provide accessible alternatives." -Reference "WCAG 2.0 1.4.5"))
    }

    if ($images -eq 0) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alternate text" -Status "Pass" -Severity "High" -Evidence "No embedded image references were found." -Recommendation "No image action detected by this scan." -Reference "WCAG 2.0 1.1.1"))
    }
    elseif ($altTextCount -ge $images) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alternate text" -Status "Pass" -Severity "High" -Evidence "Found $images image references and $altTextCount title/description entries." -Recommendation "Confirm alt text is accurate and decorative images are marked decorative." -Reference "WCAG 2.0 1.1.1"))
    }
    elseif ($altTextCount -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alternate text" -Status "Warning" -Severity "High" -Evidence "Found $images image references and $altTextCount title/description entries." -Recommendation "Add alt text to meaningful images and mark decorative images as decorative." -Reference "WCAG 2.0 1.1.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alternate text" -Status "Fail" -Severity "High" -Evidence "Found $images image references and no title/description entries." -Recommendation "Add alt text to meaningful images or mark them decorative." -Reference "WCAG 2.0 1.1.1"))
    }

    if ($tables -gt 0 -and $headerTables -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Table headers" -Status "Pass" -Severity "Medium" -Evidence "Found $tables tables and $headerTables first-row markers." -Recommendation "Confirm tables are simple and headers are meaningful." -Reference "WCAG 2.0 1.3.1"))
    }
    elseif ($tables -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Table headers" -Status "Warning" -Severity "Medium" -Evidence "Found $tables tables and no first-row header markers." -Recommendation "Identify table headers and avoid using tables for layout." -Reference "WCAG 2.0 1.3.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Table headers" -Status "Info" -Evidence "No slide tables were found." -Recommendation "Use table tools with headers for tabular data." -Reference "WCAG 2.0 1.3.1"))
    }

    if ($shapes -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Reading order" -Check "Object reading order" -Status "Warning" -Severity "Medium" -Evidence "Found $shapes slide shape references." -Recommendation "Verify each slide's reading order in PowerPoint's Accessibility Checker or Selection Pane." -Reference "WCAG 2.0 1.3.2; 2.4.3"))
    }

    if ($links -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Links" -Check "Hyperlinks" -Status "Warning" -Severity "Medium" -Evidence "Found $links hyperlink references." -Recommendation "Confirm hyperlink text or screen tips are meaningful." -Reference "WCAG 2.0 2.4.4"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Links" -Check "Hyperlinks" -Status "Info" -Evidence "No hyperlinks were found." -Recommendation "No link action detected by this scan." -Reference "WCAG 2.0 2.4.4"))
    }

    New-AccessibilityScanResult -FilePath $FilePath -FileType "PowerPoint presentation" -FileSize $Bytes.Length -ItemLabel "Estimated slides" -EstimatedItems $slideCount -Checks @($checks.ToArray())
}

function Invoke-ExcelAccessibilityScanData {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [string]$FilePath = "In-memory XLSX"
    )

    $checks = New-Object System.Collections.Generic.List[object]

    try {
        $entries = Get-ZipTextEntries -Bytes $Bytes
    }
    catch {
        [void]$checks.Add((New-CheckResult -Category "File" -Check "Open XLSX package" -Status "Fail" -Severity "Critical" -Evidence $_.Exception.Message -Recommendation "Repair the file or save it again as a modern .xlsx workbook." -Reference "WCAG 2.0 4.1.2"))
        return New-AccessibilityScanResult -FilePath $FilePath -FileType "Excel workbook" -FileSize $Bytes.Length -ItemLabel "Estimated sheets" -EstimatedItems 0 -Checks @($checks.ToArray())
    }

    $workbook = Get-ZipEntryText -Entries $entries -Name "xl/workbook.xml"
    $core = Get-ZipEntryText -Entries $entries -Name "docProps/core.xml"
    $worksheets = @($entries | Where-Object { $_.Name -match "^xl/worksheets/sheet\d+\.xml$" })
    $worksheetText = ($worksheets | ForEach-Object { $_.Text }) -join "`n"
    $allText = ($entries | ForEach-Object { $_.Text }) -join "`n"

    $sheetCount = $worksheets.Count
    $sheetNames = [regex]::Matches($workbook, "<sheet\b[^>]*name\s*=\s*`"([^`"]+)`"", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $genericSheetNames = 0
    foreach ($sheetName in $sheetNames) {
        if ($sheetName.Groups[1].Value -match "^Sheet\d+$") {
            $genericSheetNames++
        }
    }

    $hasTitle = Test-Regex -Text $core -Pattern "<dc:title>\s*[^<]+"
    $tables = @($entries | Where-Object { $_.Name -match "^xl/tables/table\d+\.xml$" })
    $tableText = ($tables | ForEach-Object { $_.Text }) -join "`n"
    $tablesWithoutHeaders = Get-RegexCount -Text $tableText -Pattern "headerRowCount\s*=\s*`"0`""
    $images = Get-RegexCount -Text $allText -Pattern "<a:blip\b"
    $altTextCount = Get-OfficeAltTextCount -Text $allText
    $links = Get-RegexCount -Text $worksheetText -Pattern "<hyperlink\b"
    $mergedCells = Get-RegexCount -Text $worksheetText -Pattern "<mergeCell\b"
    $comments = Get-RegexCount -Text $allText -Pattern "<comment\b"

    if ($hasTitle) {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Workbook title" -Status "Pass" -Severity "Medium" -Evidence "Found a title in docProps/core.xml." -Recommendation "Confirm the title identifies the workbook." -Reference "WCAG 2.0 2.4.2"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Workbook title" -Status "Fail" -Severity "Medium" -Evidence "No core title metadata found." -Recommendation "Add a workbook title in File > Info > Properties." -Reference "WCAG 2.0 2.4.2"))
    }

    if ($genericSheetNames -eq 0 -and $sheetCount -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Navigation" -Check "Worksheet names" -Status "Pass" -Severity "Medium" -Evidence "Found $sheetCount worksheet names and none appear to be default Sheet1-style names." -Recommendation "Confirm sheet names are short, unique, and descriptive." -Reference "WCAG 2.0 2.4.6"))
    }
    elseif ($sheetCount -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Navigation" -Check "Worksheet names" -Status "Warning" -Severity "Medium" -Evidence "Found $genericSheetNames default Sheet1-style worksheet names." -Recommendation "Rename worksheets with meaningful labels." -Reference "WCAG 2.0 2.4.6"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Navigation" -Check "Worksheet names" -Status "Fail" -Severity "Medium" -Evidence "No worksheets were found." -Recommendation "Repair the workbook or confirm it contains visible sheets." -Reference "WCAG 2.0 2.4.6"))
    }

    if ($tables.Count -gt 0 -and $tablesWithoutHeaders -eq 0) {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Excel tables" -Status "Pass" -Severity "High" -Evidence "Found $($tables.Count) Excel table definitions and none disable header rows." -Recommendation "Confirm table names and header labels are meaningful." -Reference "WCAG 2.0 1.3.1"))
    }
    elseif ($tables.Count -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Excel tables" -Status "Warning" -Severity "High" -Evidence "Found $($tables.Count) table definitions and $tablesWithoutHeaders without header rows." -Recommendation "Use formatted Excel tables with header rows for data ranges." -Reference "WCAG 2.0 1.3.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Excel tables" -Status "Warning" -Severity "Medium" -Evidence "No Excel table definitions were found." -Recommendation "Convert data ranges to Excel tables with headers when appropriate." -Reference "WCAG 2.0 1.3.1"))
    }

    if ($images -eq 0) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alternate text" -Status "Pass" -Severity "High" -Evidence "No embedded image references were found." -Recommendation "No image action detected by this scan." -Reference "WCAG 2.0 1.1.1"))
    }
    elseif ($altTextCount -ge $images) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alternate text" -Status "Pass" -Severity "High" -Evidence "Found $images image references and $altTextCount title/description entries." -Recommendation "Confirm alt text is accurate and decorative images are marked decorative." -Reference "WCAG 2.0 1.1.1"))
    }
    elseif ($altTextCount -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alternate text" -Status "Warning" -Severity "High" -Evidence "Found $images image references and $altTextCount title/description entries." -Recommendation "Add alt text to meaningful images and mark decorative images as decorative." -Reference "WCAG 2.0 1.1.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alternate text" -Status "Fail" -Severity "High" -Evidence "Found $images image references and no title/description entries." -Recommendation "Add alt text to meaningful images or mark them decorative." -Reference "WCAG 2.0 1.1.1"))
    }

    if ($mergedCells -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Merged cells" -Status "Warning" -Severity "Medium" -Evidence "Found $mergedCells merged cell references." -Recommendation "Avoid merged cells in data tables because they can disrupt navigation and sorting." -Reference "WCAG 2.0 1.3.1; 2.4.3"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Merged cells" -Status "Pass" -Severity "Medium" -Evidence "No merged cell references were found." -Recommendation "Keep data tables rectangular and navigable." -Reference "WCAG 2.0 1.3.1; 2.4.3"))
    }

    if ($links -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Links" -Check "Hyperlinks" -Status "Warning" -Severity "Medium" -Evidence "Found $links worksheet hyperlink references." -Recommendation "Confirm hyperlink display text is meaningful." -Reference "WCAG 2.0 2.4.4"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Links" -Check "Hyperlinks" -Status "Info" -Evidence "No worksheet hyperlinks were found." -Recommendation "No link action detected by this scan." -Reference "WCAG 2.0 2.4.4"))
    }

    if ($comments -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Review" -Check "Comments/notes" -Status "Info" -Evidence "Found $comments comment references." -Recommendation "Review comments and notes for essential information that should be available in cell content." -Reference "WCAG 2.0 1.3.1"))
    }

    New-AccessibilityScanResult -FilePath $FilePath -FileType "Excel workbook" -FileSize $Bytes.Length -ItemLabel "Estimated sheets" -EstimatedItems $sheetCount -Checks @($checks.ToArray())
}

function Invoke-HtmlAccessibilityScanData {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [string]$FilePath = "In-memory HTML"
    )

    $html = Get-TextFromBytes -Bytes $Bytes
    $checks = New-Object System.Collections.Generic.List[object]

    $hasLang = Test-Regex -Text $html -Pattern '<html\b[^>]*\blang\s*=\s*["''][^"'']+'
    $hasTitle = Test-Regex -Text $html -Pattern '<title>\s*[^<]+'
    $headingLevels = @(Get-HtmlHeadingLevels -Text $html)
    $h1Count = @($headingLevels | Where-Object { $_ -eq 1 }).Count
    $images = Get-RegexCount -Text $html -Pattern '<img\b'
    $altAttrs = Get-RegexCount -Text $html -Pattern '<img\b[^>]*\balt\s*='
    $tables = Get-RegexCount -Text $html -Pattern '<table\b'
    $tableHeaders = (Get-RegexCount -Text $html -Pattern '<th\b') + (Get-RegexCount -Text $html -Pattern '<caption\b')
    $inputs = Get-RegexCount -Text $html -Pattern '<(input|select|textarea)\b(?![^>]*type\s*=\s*["'']hidden["''])'
    $labelEvidence = (Get-RegexCount -Text $html -Pattern '<label\b') + (Get-RegexCount -Text $html -Pattern 'aria-label\s*=|aria-labelledby\s*=')
    $landmarks = Get-RegexCount -Text $html -Pattern '<(main|nav|header|footer|aside)\b|role\s*=\s*["''](main|navigation|banner|contentinfo|complementary)["'']'
    $links = Get-RegexCount -Text $html -Pattern '<a\b[^>]*\bhref\s*='
    $emptyLinks = 0
    foreach ($match in [regex]::Matches($html, '<a\b[^>]*\bhref\s*=[^>]*>(?<body>.*?)</a>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $tag = $match.Value
        $bodyText = Get-StrippedHtmlText -Html $match.Groups["body"].Value
        if ([string]::IsNullOrWhiteSpace($bodyText) -and $tag -notmatch 'aria-label\s*=|aria-labelledby\s*=|title\s*=') {
            $emptyLinks++
        }
    }

    if ($hasTitle) {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Page title" -Status "Pass" -Severity "High" -Evidence "Found a non-empty title element." -Recommendation "Confirm the title is unique and identifies the page." -Reference "WCAG 2.0 2.4.2"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Page title" -Status "Fail" -Severity "High" -Evidence "No non-empty title element was found." -Recommendation "Add a concise, unique page title." -Reference "WCAG 2.0 2.4.2"))
    }

    if ($hasLang) {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Page language" -Status "Pass" -Severity "High" -Evidence "Found a lang attribute on the html element." -Recommendation "Confirm the language code is correct and mark language changes." -Reference "WCAG 2.0 3.1.1; 3.1.2"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Document" -Check "Page language" -Status "Fail" -Severity "High" -Evidence "No html lang attribute was found." -Recommendation "Add lang to the html element, for example lang=""en""." -Reference "WCAG 2.0 3.1.1"))
    }

    if ($headingLevels.Count -eq 0) {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Headings" -Status "Warning" -Severity "High" -Evidence "No h1-h6 headings were found." -Recommendation "Use headings to identify page sections." -Reference "WCAG 2.0 1.3.1; 2.4.6"))
    }
    elseif ($h1Count -eq 0 -or (Test-HeadingLevelSkip -Levels $headingLevels)) {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Headings" -Status "Warning" -Severity "High" -Evidence "Found $($headingLevels.Count) headings, $h1Count h1 elements, and possible skipped levels." -Recommendation "Use one clear h1 and avoid skipping heading levels." -Reference "WCAG 2.0 1.3.1; 2.4.6"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Headings" -Status "Pass" -Severity "High" -Evidence "Found $($headingLevels.Count) headings and no simple level skips." -Recommendation "Confirm headings describe the following content." -Reference "WCAG 2.0 1.3.1; 2.4.6"))
    }

    if ($images -eq 0) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alt attributes" -Status "Pass" -Severity "High" -Evidence "No img elements were found." -Recommendation "No image action detected by this scan." -Reference "WCAG 2.0 1.1.1"))
    }
    elseif ($altAttrs -ge $images) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alt attributes" -Status "Pass" -Severity "High" -Evidence "Found $images img elements and $altAttrs alt attributes." -Recommendation "Confirm meaningful images have useful alt text and decorative images use empty alt." -Reference "WCAG 2.0 1.1.1"))
    }
    elseif ($altAttrs -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alt attributes" -Status "Warning" -Severity "High" -Evidence "Found $images img elements and $altAttrs alt attributes." -Recommendation "Add alt attributes to every img element." -Reference "WCAG 2.0 1.1.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alt attributes" -Status "Fail" -Severity "High" -Evidence "Found $images img elements and no alt attributes." -Recommendation "Add alt attributes to images; use alt="""" for decorative images." -Reference "WCAG 2.0 1.1.1"))
    }

    if ($tables -gt 0 -and $tableHeaders -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Table headers/captions" -Status "Pass" -Severity "High" -Evidence "Found $tables tables and $tableHeaders th/caption elements." -Recommendation "Confirm header associations and captions are correct." -Reference "WCAG 2.0 1.3.1"))
    }
    elseif ($tables -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Table headers/captions" -Status "Warning" -Severity "High" -Evidence "Found $tables tables and no th/caption elements." -Recommendation "Use th, scope, headers, and captions for data tables." -Reference "WCAG 2.0 1.3.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Table headers/captions" -Status "Info" -Evidence "No table elements were found." -Recommendation "Use semantic tables for tabular data." -Reference "WCAG 2.0 1.3.1"))
    }

    if ($inputs -gt 0 -and $labelEvidence -ge $inputs) {
        [void]$checks.Add((New-CheckResult -Category "Forms" -Check "Form labels" -Status "Pass" -Severity "High" -Evidence "Found $inputs controls and $labelEvidence label/name references." -Recommendation "Confirm every control has a programmatic name and visible instructions." -Reference "WCAG 2.0 1.3.1; 3.3.2; 4.1.2"))
    }
    elseif ($inputs -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Forms" -Check "Form labels" -Status "Warning" -Severity "High" -Evidence "Found $inputs controls and $labelEvidence label/name references." -Recommendation "Associate labels with every form control." -Reference "WCAG 2.0 1.3.1; 3.3.2; 4.1.2"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Forms" -Check "Form labels" -Status "Info" -Evidence "No form controls were found." -Recommendation "No form action detected by this scan." -Reference "WCAG 2.0 3.3.2"))
    }

    if ($landmarks -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Navigation" -Check "Landmarks" -Status "Pass" -Severity "Medium" -Evidence "Found $landmarks semantic landmark elements or roles." -Recommendation "Confirm landmarks are not excessive and have labels where needed." -Reference "WCAG 2.0 1.3.1; 2.4.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Navigation" -Check "Landmarks" -Status "Warning" -Severity "Medium" -Evidence "No common landmarks were found." -Recommendation "Use main, nav, header, footer, aside, or equivalent landmark roles." -Reference "WCAG 2.0 1.3.1; 2.4.1"))
    }

    if ($links -gt 0 -and $emptyLinks -eq 0) {
        [void]$checks.Add((New-CheckResult -Category "Links" -Check "Link names" -Status "Pass" -Severity "Medium" -Evidence "Found $links links and no empty-name links in a simple scan." -Recommendation "Confirm link names are meaningful out of context." -Reference "WCAG 2.0 2.4.4"))
    }
    elseif ($links -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Links" -Check "Link names" -Status "Warning" -Severity "Medium" -Evidence "Found $links links and $emptyLinks possible empty-name links." -Recommendation "Provide accessible names for icon-only or empty links." -Reference "WCAG 2.0 2.4.4; 4.1.2"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Links" -Check "Link names" -Status "Info" -Evidence "No links were found." -Recommendation "No link action detected by this scan." -Reference "WCAG 2.0 2.4.4"))
    }

    $lineCount = @($html -split "\r?\n").Count
    New-AccessibilityScanResult -FilePath $FilePath -FileType "HTML document" -FileSize $Bytes.Length -ItemLabel "Estimated lines" -EstimatedItems $lineCount -Checks @($checks.ToArray()) -Notes "Heuristic HTML scan. Use browser accessibility tree inspection, axe, Lighthouse, keyboard testing, and screen-reader testing for final validation."
}

function Invoke-MarkdownAccessibilityScanData {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [string]$FilePath = "In-memory Markdown"
    )

    $text = Get-TextFromBytes -Bytes $Bytes
    $checks = New-Object System.Collections.Generic.List[object]

    $levels = @(Get-MarkdownHeadingLevels -Text $text)
    $h1Count = @($levels | Where-Object { $_ -eq 1 }).Count
    $images = [regex]::Matches($text, "!\[(?<alt>[^\]]*)\]\([^)]+\)")
    $missingAlt = @($images | Where-Object { [string]::IsNullOrWhiteSpace($_.Groups["alt"].Value) }).Count
    $links = [regex]::Matches($text, "(?<!!)\[(?<label>[^\]]*)\]\([^)]+\)")
    $emptyLinks = @($links | Where-Object { [string]::IsNullOrWhiteSpace($_.Groups["label"].Value) }).Count
    $tableSeparators = Get-RegexCount -Text $text -Pattern "(?m)^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$"
    $lineCount = @($text -split "\r?\n").Count

    if ($h1Count -gt 0 -and -not (Test-HeadingLevelSkip -Levels $levels)) {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Headings" -Status "Pass" -Severity "High" -Evidence "Found $($levels.Count) headings and $h1Count top-level headings." -Recommendation "Confirm headings describe the following sections." -Reference "WCAG 2.0 1.3.1; 2.4.6"))
    }
    elseif ($levels.Count -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Headings" -Status "Warning" -Severity "High" -Evidence "Found $($levels.Count) headings, $h1Count h1 headings, or possible skipped levels." -Recommendation "Start with a top-level heading and avoid skipping levels." -Reference "WCAG 2.0 1.3.1; 2.4.6"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Headings" -Status "Warning" -Severity "High" -Evidence "No Markdown headings were found." -Recommendation "Use # headings to identify sections." -Reference "WCAG 2.0 1.3.1; 2.4.6"))
    }

    if ($images.Count -eq 0) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alt text" -Status "Pass" -Severity "High" -Evidence "No Markdown image syntax was found." -Recommendation "No image action detected by this scan." -Reference "WCAG 2.0 1.1.1"))
    }
    elseif ($missingAlt -eq 0) {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alt text" -Status "Pass" -Severity "High" -Evidence "Found $($images.Count) images and no empty alt text." -Recommendation "Confirm alt text is accurate and concise." -Reference "WCAG 2.0 1.1.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Images" -Check "Image alt text" -Status "Fail" -Severity "High" -Evidence "Found $missingAlt images with empty alt text out of $($images.Count)." -Recommendation "Add useful alt text for meaningful images." -Reference "WCAG 2.0 1.1.1"))
    }

    if ($links.Count -gt 0 -and $emptyLinks -eq 0) {
        [void]$checks.Add((New-CheckResult -Category "Links" -Check "Link text" -Status "Pass" -Severity "Medium" -Evidence "Found $($links.Count) links and no empty labels." -Recommendation "Confirm link text is meaningful out of context." -Reference "WCAG 2.0 2.4.4"))
    }
    elseif ($links.Count -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Links" -Check "Link text" -Status "Warning" -Severity "Medium" -Evidence "Found $emptyLinks empty link labels out of $($links.Count)." -Recommendation "Use descriptive text inside Markdown links." -Reference "WCAG 2.0 2.4.4"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Links" -Check "Link text" -Status "Info" -Evidence "No Markdown links were found." -Recommendation "No link action detected by this scan." -Reference "WCAG 2.0 2.4.4"))
    }

    if ($tableSeparators -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Markdown tables" -Status "Warning" -Severity "Medium" -Evidence "Found $tableSeparators Markdown table separator rows." -Recommendation "Confirm rendered tables have clear headers and avoid complex merged-cell layouts." -Reference "WCAG 2.0 1.3.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Markdown tables" -Status "Info" -Evidence "No Markdown table syntax was found." -Recommendation "Use simple tables with header rows for tabular data." -Reference "WCAG 2.0 1.3.1"))
    }

    [void]$checks.Add((New-CheckResult -Category "Document" -Check "Language metadata" -Status "Info" -Evidence "Markdown files do not usually carry document language metadata." -Recommendation "Set language in the publishing system or HTML wrapper used to render this Markdown." -Reference "WCAG 2.0 3.1.1"))

    New-AccessibilityScanResult -FilePath $FilePath -FileType "Markdown document" -FileSize $Bytes.Length -ItemLabel "Estimated lines" -EstimatedItems $lineCount -Checks @($checks.ToArray()) -Notes "Heuristic Markdown scan. Validate the rendered output in its target publishing system."
}

function Invoke-PlainTextAccessibilityScanData {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [string]$FilePath = "In-memory text"
    )

    $text = Get-TextFromBytes -Bytes $Bytes
    $checks = New-Object System.Collections.Generic.List[object]
    $lines = @($text -split "\r?\n")
    $nonEmptyLines = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    $longLines = @($lines | Where-Object { $_.Length -gt 120 }).Count

    if ($nonEmptyLines -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Content" -Check "Readable text" -Status "Pass" -Severity "High" -Evidence "Found $nonEmptyLines non-empty lines." -Recommendation "Keep text plain and avoid conveying structure only through spacing." -Reference "WCAG 2.0 1.3.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Content" -Check "Readable text" -Status "Fail" -Severity "High" -Evidence "No non-empty lines were found." -Recommendation "Add readable content or choose a richer format if structure is needed." -Reference "WCAG 2.0 1.3.1"))
    }

    [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Semantic structure" -Status "Warning" -Severity "Medium" -Evidence "Plain text cannot encode headings, tables, images, or language metadata in a standard programmatic way." -Recommendation "Use HTML, Markdown, Word, or PDF when semantic structure is required." -Reference "WCAG 2.0 1.3.1"))

    if ($longLines -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Readability" -Check "Line length" -Status "Warning" -Severity "Low" -Evidence "Found $longLines lines longer than 120 characters." -Recommendation "Wrap long lines or use a structured format for dense content." -Reference "WCAG 2.0 1.4.8"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Readability" -Check "Line length" -Status "Pass" -Severity "Low" -Evidence "No lines longer than 120 characters were found." -Recommendation "Keep line lengths manageable." -Reference "WCAG 2.0 1.4.8"))
    }

    New-AccessibilityScanResult -FilePath $FilePath -FileType "Plain text" -FileSize $Bytes.Length -ItemLabel "Estimated lines" -EstimatedItems $lines.Count -Checks @($checks.ToArray()) -Notes "Plain text has limited accessibility metadata. Validate how it is delivered to users."
}

function Invoke-CsvAccessibilityScanData {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [string]$FilePath = "In-memory CSV"
    )

    $text = Get-TextFromBytes -Bytes $Bytes
    $checks = New-Object System.Collections.Generic.List[object]
    $lines = @($text -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $firstLine = if ($lines.Count -gt 0) { $lines[0] } else { "" }
    $delimiter = if (($firstLine.ToCharArray() | Where-Object { $_ -eq "`t" }).Count -gt ($firstLine.ToCharArray() | Where-Object { $_ -eq "," }).Count) { "`t" } else { "," }
    $columns = if ($firstLine) { @($firstLine -split [regex]::Escape($delimiter)) } else { @() }
    $headerLooksTextual = $columns.Count -gt 0 -and (@($columns | Where-Object { $_ -match "^\s*\d+(\.\d+)?\s*$" }).Count -eq 0)
    $uniqueHeaders = @($columns | Select-Object -Unique).Count -eq $columns.Count
    $inconsistentRows = 0
    foreach ($line in $lines) {
        if (@($line -split [regex]::Escape($delimiter)).Count -ne $columns.Count) {
            $inconsistentRows++
        }
    }

    if ($lines.Count -gt 0) {
        [void]$checks.Add((New-CheckResult -Category "Content" -Check "Rows and columns" -Status "Pass" -Severity "High" -Evidence "Found $($lines.Count) rows and $($columns.Count) columns using delimiter '$delimiter'." -Recommendation "Confirm the file opens correctly in spreadsheet software." -Reference "WCAG 2.0 1.3.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Content" -Check "Rows and columns" -Status "Fail" -Severity "High" -Evidence "No rows were found." -Recommendation "Add tabular content or verify the file encoding." -Reference "WCAG 2.0 1.3.1"))
    }

    if ($headerLooksTextual -and $uniqueHeaders) {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Header row" -Status "Pass" -Severity "High" -Evidence "The first row appears to contain unique text headers." -Recommendation "Confirm headers describe each column clearly." -Reference "WCAG 2.0 1.3.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Header row" -Status "Warning" -Severity "High" -Evidence "The first row may be missing textual or unique column headers." -Recommendation "Use a first row with clear, unique column names." -Reference "WCAG 2.0 1.3.1"))
    }

    if ($inconsistentRows -eq 0) {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Consistent columns" -Status "Pass" -Severity "Medium" -Evidence "All inspected rows have the same column count." -Recommendation "Keep data rectangular and avoid embedded delimiters unless properly quoted." -Reference "WCAG 2.0 1.3.1"))
    }
    else {
        [void]$checks.Add((New-CheckResult -Category "Tables" -Check "Consistent columns" -Status "Warning" -Severity "Medium" -Evidence "Found $inconsistentRows rows with a different column count." -Recommendation "Fix quoting or delimiters so each row has consistent columns." -Reference "WCAG 2.0 1.3.1"))
    }

    [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Semantic metadata" -Status "Info" -Evidence "CSV cannot carry rich accessibility metadata such as language, captions, or table header associations." -Recommendation "Provide CSV with a data dictionary or publish an accessible HTML/XLSX version for complex data." -Reference "WCAG 2.0 1.3.1"))

    New-AccessibilityScanResult -FilePath $FilePath -FileType "CSV data" -FileSize $Bytes.Length -ItemLabel "Estimated rows" -EstimatedItems $lines.Count -Checks @($checks.ToArray()) -Notes "Heuristic CSV scan. Complex CSV quoting is approximated; validate in the target data tool."
}

function Invoke-LegacyOfficeAccessibilityScanData {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$FileType
    )

    $checks = New-Object System.Collections.Generic.List[object]
    [void]$checks.Add((New-CheckResult -Category "File" -Check "Legacy binary Office format" -Status "Warning" -Severity "High" -Evidence "This is a legacy binary Office file, not an Open XML package." -Recommendation "Save a copy as DOCX, PPTX, or XLSX and run the checker again for deeper inspection." -Reference "WCAG 2.0 4.1.2"))
    [void]$checks.Add((New-CheckResult -Category "Structure" -Check "Automated structure inspection" -Status "Info" -Evidence "The no-dependency scanner cannot inspect legacy binary Office internals." -Recommendation "Use Microsoft Office Accessibility Checker and manual keyboard/screen-reader testing." -Reference "WCAG 2.0 1.3.1; 2.4.3"))
    [void]$checks.Add((New-CheckResult -Category "Document" -Check "Modern format availability" -Status "Warning" -Severity "Medium" -Evidence "Modern Office formats expose more accessibility metadata for checking and remediation." -Recommendation "Maintain an accessible source file in a modern format before exporting to PDF or other formats." -Reference "WCAG 2.0 4.1.2"))

    New-AccessibilityScanResult -FilePath $FilePath -FileType $FileType -FileSize $Bytes.Length -ItemLabel "Estimated items" -EstimatedItems 0 -Checks @($checks.ToArray()) -Notes "Legacy Office binary files receive advisory checks only in this no-dependency app."
}

function ConvertTo-MarkdownCell {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return ($Value -replace "\|", "\|" -replace "`r?`n", " ")
}

function New-AccessibilityReportMarkdown {
    param([Parameter(Mandatory = $true)]$Scan)

    $lines = New-Object System.Collections.Generic.List[string]
    $itemLabel = if ($Scan.PSObject.Properties["ItemLabel"]) { $Scan.ItemLabel } else { "Estimated pages" }
    $estimatedItems = if ($Scan.PSObject.Properties["EstimatedItems"]) { $Scan.EstimatedItems } else { $Scan.EstimatedPages }

    $lines.Add("# ReadRite Accessibility Report")
    $lines.Add("")
    $lines.Add("Generated: $($Scan.GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss'))")
    $lines.Add("File: $($Scan.FilePath)")
    $lines.Add("Type: $($Scan.FileType)")
    $lines.Add("Size: $([Math]::Round($Scan.FileSize / 1KB, 1)) KB")
    $lines.Add("${itemLabel}: $estimatedItems")
    $lines.Add("Score: $($Scan.Score)%")
    $lines.Add("")
    $lines.Add("Summary: $($Scan.Counts.Pass) pass, $($Scan.Counts.Warning) warning, $($Scan.Counts.Fail) fail, $($Scan.Counts.Info) info")
    $lines.Add("")
    $lines.Add("> $($Scan.Notes)")
    $lines.Add("")
    $lines.Add("| Status | Severity | Category | Check | Evidence | Recommendation | Reference |")
    $lines.Add("| --- | --- | --- | --- | --- | --- | --- |")

    foreach ($check in $Scan.Checks) {
        $lines.Add("| $(ConvertTo-MarkdownCell $check.Status) | $(ConvertTo-MarkdownCell $check.Severity) | $(ConvertTo-MarkdownCell $check.Category) | $(ConvertTo-MarkdownCell $check.Check) | $(ConvertTo-MarkdownCell $check.Evidence) | $(ConvertTo-MarkdownCell $check.Recommendation) | $(ConvertTo-MarkdownCell $check.Reference) |")
    }

    $lines -join [Environment]::NewLine
}

function New-PdfAccessibilityReportMarkdown {
    param([Parameter(Mandatory = $true)]$Scan)

    New-AccessibilityReportMarkdown -Scan $Scan
}

function Format-Bytes {
    param([long]$Bytes)

    if ($Bytes -ge 1MB) {
        return ("{0:N1} MB" -f ($Bytes / 1MB))
    }
    if ($Bytes -ge 1KB) {
        return ("{0:N1} KB" -f ($Bytes / 1KB))
    }
    return "$Bytes bytes"
}

function Start-PdfAccessibilityChecker {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Xaml
    Add-Type -AssemblyName System.Windows.Forms

    [xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="ReadRite"
    Width="1120"
    Height="780"
    MinWidth="920"
    MinHeight="640"
    WindowStartupLocation="CenterScreen"
    Background="#F5F7FA"
    FontFamily="Segoe UI"
    FontSize="13"
    AllowDrop="True">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="MinHeight" Value="34"/>
            <Setter Property="MinWidth" Value="94"/>
            <Setter Property="Padding" Value="14,6"/>
            <Setter Property="Margin" Value="0,0,8,0"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="MinHeight" Value="34"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Padding" Value="8,0"/>
        </Style>
        <Style TargetType="DataGrid">
            <Setter Property="GridLinesVisibility" Value="Horizontal"/>
            <Setter Property="HeadersVisibility" Value="Column"/>
            <Setter Property="CanUserAddRows" Value="False"/>
            <Setter Property="CanUserDeleteRows" Value="False"/>
            <Setter Property="IsReadOnly" Value="True"/>
            <Setter Property="AutoGenerateColumns" Value="False"/>
            <Setter Property="SelectionMode" Value="Single"/>
            <Setter Property="SelectionUnit" Value="FullRow"/>
            <Setter Property="RowHeaderWidth" Value="0"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="AlternatingRowBackground" Value="#F7FAFC"/>
        </Style>
    </Window.Resources>
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="150"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <DockPanel Grid.Row="0" Margin="0,0,0,14">
            <StackPanel DockPanel.Dock="Left">
                <TextBlock Text="ReadRite" FontSize="24" FontWeight="SemiBold" Foreground="#162033"/>
                <TextBlock Text="Windows desktop scan for PDF, Office, HTML, Markdown, text, and CSV files" Foreground="#4A5568" Margin="0,3,0,0"/>
            </StackPanel>
            <Border DockPanel.Dock="Right" Background="#EAF2F8" BorderBrush="#B8D7EE" BorderThickness="1" CornerRadius="4" Padding="12,8">
                <StackPanel Orientation="Horizontal">
                    <TextBlock Text="Score" Foreground="#364152" Margin="0,0,8,0"/>
                    <TextBlock x:Name="ScoreText" Text="--" FontSize="18" FontWeight="Bold" Foreground="#0B5E80"/>
                </StackPanel>
            </Border>
        </DockPanel>

        <Grid Grid.Row="1" Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="FilePathTextBox" Grid.Column="0" IsReadOnly="True" AutomationProperties.Name="Selected document path"/>
            <Button x:Name="BrowseButton" Grid.Column="1" Content="Open File" AutomationProperties.Name="Open file"/>
            <Button x:Name="RunButton" Grid.Column="2" Content="Run Check" AutomationProperties.Name="Run accessibility check"/>
            <Button x:Name="ExportButton" Grid.Column="3" Content="Export Report" IsEnabled="False" AutomationProperties.Name="Export report"/>
        </Grid>

        <Grid Grid.Row="2" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Border Grid.Column="0" Background="White" BorderBrush="#D9E2EC" BorderThickness="1" CornerRadius="4" Padding="12" Margin="0,0,8,0">
                <StackPanel>
                    <TextBlock Text="Pass" Foreground="#3C4A5E"/>
                    <TextBlock x:Name="PassCountText" Text="0" FontSize="22" FontWeight="Bold" Foreground="#166534"/>
                </StackPanel>
            </Border>
            <Border Grid.Column="1" Background="White" BorderBrush="#D9E2EC" BorderThickness="1" CornerRadius="4" Padding="12" Margin="0,0,8,0">
                <StackPanel>
                    <TextBlock Text="Warnings" Foreground="#3C4A5E"/>
                    <TextBlock x:Name="WarningCountText" Text="0" FontSize="22" FontWeight="Bold" Foreground="#A15C07"/>
                </StackPanel>
            </Border>
            <Border Grid.Column="2" Background="White" BorderBrush="#D9E2EC" BorderThickness="1" CornerRadius="4" Padding="12" Margin="0,0,8,0">
                <StackPanel>
                    <TextBlock Text="Fails" Foreground="#3C4A5E"/>
                    <TextBlock x:Name="FailCountText" Text="0" FontSize="22" FontWeight="Bold" Foreground="#B91C1C"/>
                </StackPanel>
            </Border>
            <Border Grid.Column="3" Background="White" BorderBrush="#D9E2EC" BorderThickness="1" CornerRadius="4" Padding="12">
                <StackPanel>
                    <TextBlock Text="Info" Foreground="#3C4A5E"/>
                    <TextBlock x:Name="InfoCountText" Text="0" FontSize="22" FontWeight="Bold" Foreground="#475569"/>
                </StackPanel>
            </Border>
        </Grid>

        <DataGrid x:Name="ChecksGrid" Grid.Row="3" Margin="0,0,0,10" AutomationProperties.Name="Accessibility check results">
            <DataGrid.Columns>
                <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="90"/>
                <DataGridTextColumn Header="Severity" Binding="{Binding Severity}" Width="90"/>
                <DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="120"/>
                <DataGridTextColumn Header="Check" Binding="{Binding Check}" Width="180"/>
                <DataGridTextColumn Header="Evidence" Binding="{Binding Evidence}" Width="*"/>
            </DataGrid.Columns>
        </DataGrid>

        <Border Grid.Row="4" Background="White" BorderBrush="#D9E2EC" BorderThickness="1" CornerRadius="4" Padding="12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" Margin="0,0,12,0">
                    <TextBlock Text="Recommendation" FontWeight="SemiBold" Foreground="#162033" Margin="0,0,0,6"/>
                    <TextBox x:Name="RecommendationTextBox" TextWrapping="Wrap" IsReadOnly="True" BorderThickness="0" Background="Transparent" VerticalScrollBarVisibility="Auto"/>
                </StackPanel>
                <StackPanel Grid.Column="1">
                    <TextBlock Text="Reference" FontWeight="SemiBold" Foreground="#162033" Margin="0,0,0,6"/>
                    <TextBox x:Name="ReferenceTextBox" TextWrapping="Wrap" IsReadOnly="True" BorderThickness="0" Background="Transparent" VerticalScrollBarVisibility="Auto"/>
                </StackPanel>
            </Grid>
        </Border>

        <DockPanel Grid.Row="5" Margin="0,10,0,0">
            <TextBlock x:Name="StatusText" DockPanel.Dock="Left" Text="Ready" Foreground="#4A5568" VerticalAlignment="Center"/>
            <TextBlock DockPanel.Dock="Right" Text="Heuristic results require manual validation." Foreground="#4A5568" HorizontalAlignment="Right"/>
        </DockPanel>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $filePathTextBox = $window.FindName("FilePathTextBox")
    $browseButton = $window.FindName("BrowseButton")
    $runButton = $window.FindName("RunButton")
    $exportButton = $window.FindName("ExportButton")
    $checksGrid = $window.FindName("ChecksGrid")
    $scoreText = $window.FindName("ScoreText")
    $passCountText = $window.FindName("PassCountText")
    $warningCountText = $window.FindName("WarningCountText")
    $failCountText = $window.FindName("FailCountText")
    $infoCountText = $window.FindName("InfoCountText")
    $recommendationTextBox = $window.FindName("RecommendationTextBox")
    $referenceTextBox = $window.FindName("ReferenceTextBox")
    $statusText = $window.FindName("StatusText")

    $script:lastScan = $null

    function Set-StatusMessage {
        param([string]$Message)
        $statusText.Text = $Message
    }

    function Set-ScanResult {
        param([Parameter(Mandatory = $true)]$Scan)

        $script:lastScan = $Scan
        $checksGrid.ItemsSource = $Scan.Checks
        $scoreText.Text = "$($Scan.Score)%"
        $passCountText.Text = [string]$Scan.Counts.Pass
        $warningCountText.Text = [string]$Scan.Counts.Warning
        $failCountText.Text = [string]$Scan.Counts.Fail
        $infoCountText.Text = [string]$Scan.Counts.Info
        $exportButton.IsEnabled = $true
        $recommendationTextBox.Text = ""
        $referenceTextBox.Text = ""
        Set-StatusMessage "Scanned $($Scan.FileName) - $(Format-Bytes $Scan.FileSize), $($Scan.ItemLabel.ToLowerInvariant()): $($Scan.EstimatedItems)"

        if ($Scan.Checks.Count -gt 0) {
            $checksGrid.SelectedIndex = 0
        }
    }

    function Invoke-SelectedScan {
        $selectedPath = $filePathTextBox.Text
        if ([string]::IsNullOrWhiteSpace($selectedPath)) {
            [System.Windows.MessageBox]::Show(
                "Select a supported file first.",
                "ReadRite",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null
            return
        }

        try {
            Set-StatusMessage "Scanning..."
            $window.Cursor = [System.Windows.Input.Cursors]::Wait
            $scan = Invoke-DocumentAccessibilityScan -FilePath $selectedPath
            Set-ScanResult -Scan $scan
        }
        catch {
            Set-StatusMessage "Scan failed"
            [System.Windows.MessageBox]::Show(
                $_.Exception.Message,
                "Scan failed",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null
        }
        finally {
            $window.Cursor = $null
        }
    }

    function Set-SelectedFile {
        param([Parameter(Mandatory = $true)][string]$SelectedPath)

        $filePathTextBox.Text = $SelectedPath
        Set-StatusMessage "Selected $([System.IO.Path]::GetFileName($SelectedPath))"
    }

    $browseButton.Add_Click({
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Filter = "Supported files|*.pdf;*.docx;*.pptx;*.xlsx;*.html;*.htm;*.md;*.markdown;*.txt;*.csv;*.doc;*.ppt;*.xls|PDF files (*.pdf)|*.pdf|Office files (*.docx;*.pptx;*.xlsx;*.doc;*.ppt;*.xls)|*.docx;*.pptx;*.xlsx;*.doc;*.ppt;*.xls|Web and text files (*.html;*.htm;*.md;*.markdown;*.txt;*.csv)|*.html;*.htm;*.md;*.markdown;*.txt;*.csv|All files (*.*)|*.*"
        $dialog.Title = "Open file"
        if ($dialog.ShowDialog($window) -eq $true) {
            Set-SelectedFile -SelectedPath $dialog.FileName
            Invoke-SelectedScan
        }
    })

    $runButton.Add_Click({
        Invoke-SelectedScan
    })

    $exportButton.Add_Click({
        if ($null -eq $script:lastScan) {
            return
        }

        $dialog = New-Object Microsoft.Win32.SaveFileDialog
        $dialog.Filter = "Markdown report (*.md)|*.md|Text file (*.txt)|*.txt"
        $dialog.Title = "Export accessibility report"
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($script:lastScan.FileName)
        if ([string]::IsNullOrWhiteSpace($baseName)) {
            $baseName = "pdf-accessibility-report"
        }
        $dialog.FileName = "$baseName-accessibility-report.md"

        if ($dialog.ShowDialog($window) -eq $true) {
            try {
                $report = New-AccessibilityReportMarkdown -Scan $script:lastScan
                [System.IO.File]::WriteAllText($dialog.FileName, $report, [System.Text.Encoding]::UTF8)
                Set-StatusMessage "Report exported to $($dialog.FileName)"
            }
            catch {
                [System.Windows.MessageBox]::Show(
                    $_.Exception.Message,
                    "Export failed",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                ) | Out-Null
            }
        }
    })

    $checksGrid.Add_SelectionChanged({
        $selected = $checksGrid.SelectedItem
        if ($null -eq $selected) {
            $recommendationTextBox.Text = ""
            $referenceTextBox.Text = ""
            return
        }

        $recommendationTextBox.Text = $selected.Recommendation
        $referenceTextBox.Text = $selected.Reference
    })

    $window.Add_Drop({
        param($sender, $eventArgs)

        if ($eventArgs.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $files = $eventArgs.Data.GetData([System.Windows.DataFormats]::FileDrop)
            if ($files -and $files.Count -gt 0) {
                Set-SelectedFile -SelectedPath $files[0]
                Invoke-SelectedScan
            }
        }
    })

    $window.Add_DragOver({
        param($sender, $eventArgs)

        if ($eventArgs.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $eventArgs.Effects = [System.Windows.DragDropEffects]::Copy
        }
        else {
            $eventArgs.Effects = [System.Windows.DragDropEffects]::None
        }
        $eventArgs.Handled = $true
    })

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Set-SelectedFile -SelectedPath (Resolve-Path -LiteralPath $Path).Path
            $window.Add_ContentRendered({ Invoke-SelectedScan })
        }
    }

    [void]$window.ShowDialog()
}

function New-TestZipBytes {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entries
    )

    Import-ZipAssemblies
    $memory = [System.IO.MemoryStream]::new()
    $archive = [System.IO.Compression.ZipArchive]::new(
        $memory,
        [System.IO.Compression.ZipArchiveMode]::Create,
        $true
    )

    try {
        foreach ($name in $Entries.Keys) {
            $entry = $archive.CreateEntry($name)
            $stream = $entry.Open()
            try {
                $writer = [System.IO.StreamWriter]::new($stream)
                try {
                    $writer.Write([string]$Entries[$name])
                }
                finally {
                    $writer.Dispose()
                }
            }
            finally {
                $stream.Dispose()
            }
        }
    }
    finally {
        $archive.Dispose()
    }

    $bytes = $memory.ToArray()
    $memory.Dispose()
    return $bytes
}

function Invoke-SelfTest {
    $sample = @"
%PDF-1.7
1 0 obj
<< /Type /Catalog /Lang (en-US) /MarkInfo << /Marked true >> /StructTreeRoot 2 0 R /ViewerPreferences << /DisplayDocTitle true >> /Outlines 3 0 R /Metadata 4 0 R >>
endobj
2 0 obj
<< /Type /StructTreeRoot /K [ << /S /Document >> << /S /H1 >> << /S /P >> << /S /Figure /Alt (Chart showing progress) >> << /S /Table >> << /S /TH >> ] /RoleMap << /CustomHeading /H1 >> >>
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
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($sample)
    $pdfScan = Invoke-PdfAccessibilityScanData -Bytes $bytes -FilePath "self-test.pdf"

    if ($pdfScan.Score -le 0 -or $pdfScan.Checks.Count -eq 0) {
        throw "Self-test did not produce PDF scan results."
    }

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
    $htmlScan = Invoke-HtmlAccessibilityScanData -Bytes ([System.Text.Encoding]::UTF8.GetBytes($html)) -FilePath "self-test.html"

    if ($htmlScan.Score -le 0 -or $htmlScan.Checks.Count -eq 0) {
        throw "Self-test did not produce HTML scan results."
    }

    $docxBytes = New-TestZipBytes -Entries @{
        "[Content_Types].xml" = "<Types></Types>"
        "docProps/core.xml" = "<cp:coreProperties><dc:title>Accessible sample</dc:title></cp:coreProperties>"
        "word/settings.xml" = "<w:settings><w:themeFontLang w:val=""en-US""/></w:settings>"
        "word/document.xml" = "<w:document><w:body><w:p><w:pPr><w:pStyle w:val=""Heading1""/></w:pPr><w:r><w:t>Sample</w:t></w:r></w:p><w:p><w:numPr/></w:p><w:tbl><w:tr><w:trPr><w:tblHeader/></w:trPr></w:tr></w:tbl><w:drawing><wp:docPr id=""1"" name=""Picture 1"" descr=""Progress chart""/><a:blip/></w:drawing><w:hyperlink><w:r><w:t>Learn more</w:t></w:r></w:hyperlink></w:body></w:document>"
    }
    $wordScan = Invoke-WordAccessibilityScanData -Bytes $docxBytes -FilePath "self-test.docx"

    if ($wordScan.Score -le 0 -or $wordScan.Checks.Count -eq 0) {
        throw "Self-test did not produce Word scan results."
    }

    $pptxBytes = New-TestZipBytes -Entries @{
        "[Content_Types].xml" = "<Types></Types>"
        "docProps/core.xml" = "<cp:coreProperties><dc:title>Accessible sample deck</dc:title></cp:coreProperties>"
        "ppt/slides/slide1.xml" = "<p:sld><p:cSld><p:spTree><p:sp><p:nvSpPr><p:nvPr><p:ph type=""title""/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:rPr lang=""en-US""/><a:t>Sample slide</a:t></a:r></a:p></p:txBody></p:sp><p:pic><p:nvPicPr><p:cNvPr id=""2"" name=""Picture 1"" descr=""Progress chart""/></p:nvPicPr><p:blipFill><a:blip/></p:blipFill></p:pic><a:tbl><a:tblPr firstRow=""1""/></a:tbl></p:spTree></p:cSld></p:sld>"
    }
    $powerPointScan = Invoke-PowerPointAccessibilityScanData -Bytes $pptxBytes -FilePath "self-test.pptx"

    if ($powerPointScan.Score -le 0 -or $powerPointScan.Checks.Count -eq 0) {
        throw "Self-test did not produce PowerPoint scan results."
    }

    $xlsxBytes = New-TestZipBytes -Entries @{
        "[Content_Types].xml" = "<Types></Types>"
        "docProps/core.xml" = "<cp:coreProperties><dc:title>Accessible sample workbook</dc:title></cp:coreProperties>"
        "xl/workbook.xml" = "<workbook><sheets><sheet name=""Data"" sheetId=""1"" r:id=""rId1""/></sheets></workbook>"
        "xl/worksheets/sheet1.xml" = "<worksheet><sheetData><row r=""1""><c r=""A1""><v>Header</v></c></row></sheetData></worksheet>"
        "xl/tables/table1.xml" = "<table name=""DataTable"" displayName=""DataTable"" headerRowCount=""1""></table>"
    }
    $excelScan = Invoke-ExcelAccessibilityScanData -Bytes $xlsxBytes -FilePath "self-test.xlsx"

    if ($excelScan.Score -le 0 -or $excelScan.Checks.Count -eq 0) {
        throw "Self-test did not produce Excel scan results."
    }

    $report = New-AccessibilityReportMarkdown -Scan $pdfScan
    if ($report -notmatch "ReadRite Accessibility Report") {
        throw "Self-test did not produce a report."
    }

    "Self-test passed. PDF score: $($pdfScan.Score)%. HTML score: $($htmlScan.Score)%. Word score: $($wordScan.Score)%. PowerPoint score: $($powerPointScan.Score)%. Excel score: $($excelScan.Score)%."
}

if ($SelfTest) {
    Invoke-SelfTest
    return
}

if ($NoGui) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Use -Path with -NoGui."
    }
    $scan = Invoke-DocumentAccessibilityScan -FilePath $Path
    New-AccessibilityReportMarkdown -Scan $scan
    return
}

Start-PdfAccessibilityChecker
