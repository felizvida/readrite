param(
    [string]$Path,
    [switch]$NoGui,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-RRResult {
    param([string]$Category,[string]$Check,[string]$Status,[string]$Severity="None",[string]$Evidence="",[string]$Recommendation="",[string]$Reference="")
    [pscustomobject]@{Status=$Status;Severity=$Severity;Category=$Category;Check=$Check;Evidence=$Evidence;Recommendation=$Recommendation;Reference=$Reference}
}

function Get-RRCount { param([string]$Text,[string]$Pattern) ([regex]::Matches($Text,$Pattern,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count }
function Test-RRText { param([string]$Text,[string]$Pattern) [regex]::IsMatch($Text,$Pattern,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }

function Get-RRScore {
    param([object[]]$Checks)
    $weights=@{Critical=18;High=12;Medium=8;Low=4;None=0}; $max=0; $earned=0
    foreach($c in $Checks){ $w=$weights[$c.Severity]; if($w -le 0 -or $c.Status -eq "Info"){continue}; $max+=$w; if($c.Status -eq "Pass"){$earned+=$w}; if($c.Status -eq "Warning"){$earned+=[math]::Round($w*.45,2)} }
    if($max -eq 0){0}else{[math]::Round(($earned/$max)*100)}
}

function New-RRScan {
    param([string]$FilePath,[string]$FileType,[long]$FileSize,[string]$ItemLabel,[int]$EstimatedItems,[object[]]$Checks,[string]$Notes="Heuristic scan. Validate with source tools and manual assistive technology testing.")
    $counts=@{Pass=@($Checks|? Status -eq Pass).Count; Warning=@($Checks|? Status -eq Warning).Count; Fail=@($Checks|? Status -eq Fail).Count; Info=@($Checks|? Status -eq Info).Count}
    [pscustomobject]@{FilePath=$FilePath;FileName=[IO.Path]::GetFileName($FilePath);FileType=$FileType;FileSize=$FileSize;ItemLabel=$ItemLabel;EstimatedItems=$EstimatedItems;Score=(Get-RRScore $Checks);Counts=$counts;Checks=$Checks;GeneratedAt=[datetime]::Now;Notes=$Notes}
}

function Get-RRTextFromBytes { param([byte[]]$Bytes) try{[Text.Encoding]::UTF8.GetString($Bytes)}catch{[Text.Encoding]::Default.GetString($Bytes)} }

function Get-RRZipText {
    param([byte[]]$Bytes)
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $ms=[IO.MemoryStream]::new($Bytes); $out=New-Object System.Collections.Generic.List[object]
    try{ $zip=[IO.Compression.ZipArchive]::new($ms,[IO.Compression.ZipArchiveMode]::Read,$true); try{ foreach($e in $zip.Entries){ if($e.FullName -match '\.(xml|rels)$' -or $e.FullName -eq '[Content_Types].xml'){ $s=$e.Open(); try{ $r=[IO.StreamReader]::new($s); try{$out.Add([pscustomobject]@{Name=$e.FullName;Text=$r.ReadToEnd()})}finally{$r.Dispose()} }finally{$s.Dispose()} } } }finally{$zip.Dispose()} }finally{$ms.Dispose()}
    @($out.ToArray())
}

function Invoke-RRPdfScan {
    param([byte[]]$Bytes,[string]$FilePath)
    $text=[Text.Encoding]::GetEncoding(28591).GetString($Bytes); $c=New-Object System.Collections.Generic.List[object]
    $pages=Get-RRCount $text '/Type\s*/Page\b(?!s)'; if($pages -eq 0){$pages=Get-RRCount $text '/Count\s+\d+'}
    $tagged=(Test-RRText $text '/Marked\s+true\b') -and (Test-RRText $text '/StructTreeRoot\b')
    if($tagged){$c.Add((New-RRResult Structure 'Tagged PDF structure' Pass Critical 'Found /Marked true and /StructTreeRoot.' 'Review tag order, semantics, and reading order in a full PDF/UA tool.' 'PDF/UA-1 7.1; WCAG 2.0 1.3.1'))}else{$c.Add((New-RRResult Structure 'Tagged PDF structure' Fail Critical 'Missing /Marked true and/or /StructTreeRoot evidence.' 'Create a tagged PDF from the source document or remediate the tag tree.' 'PDF/UA-1 7.1; WCAG 2.0 1.3.1'))}
    if(Test-RRText $text '/Lang\s*(\(|<|/[A-Za-z]{2})'){$c.Add((New-RRResult Document 'Document language' Pass High 'Found language metadata.' 'Confirm the language value is correct.' 'WCAG 2.0 3.1.1'))}else{$c.Add((New-RRResult Document 'Document language' Fail High 'No /Lang entry found.' 'Set the document language.' 'WCAG 2.0 3.1.1'))}
    if((Test-RRText $text '/Title\s*(\(|<)') -or (Test-RRText $text '<dc:title|<title')){$c.Add((New-RRResult Document 'Document title' Pass Medium 'Found title metadata.' 'Confirm the title identifies the document.' 'WCAG 2.0 2.4.2'))}else{$c.Add((New-RRResult Document 'Document title' Fail Medium 'No title metadata found.' 'Add a meaningful document title.' 'WCAG 2.0 2.4.2'))}
    if(Test-RRText $text '/Tabs\s*/S\b'){$c.Add((New-RRResult Navigation 'Page tab order' Pass Medium 'Found /Tabs /S.' 'Verify keyboard focus order manually.' 'WCAG 2.0 2.4.3'))}else{$c.Add((New-RRResult Navigation 'Page tab order' Warning Medium 'No /Tabs /S entry found.' 'Set page tab order to use document structure.' 'WCAG 2.0 2.4.3'))}
    $images=Get-RRCount $text '/Subtype\s*/Image\b'; $alts=(Get-RRCount $text '/Alt\s*(\(|<)')+(Get-RRCount $text '/ActualText\s*(\(|<)')
    if($images -eq 0){$c.Add((New-RRResult Images 'Image alternate text' Pass High 'No image XObjects found.' 'No image action detected.' 'WCAG 2.0 1.1.1'))}elseif($alts -gt 0){$c.Add((New-RRResult Images 'Image alternate text' Warning High "Found $images images and $alts alternate text signals." 'Verify every meaningful image has accurate alt text and decorative images are artifacted.' 'WCAG 2.0 1.1.1'))}else{$c.Add((New-RRResult Images 'Image alternate text' Fail High "Found $images images and no alt text signals." 'Add alternate text or artifact decorative images.' 'WCAG 2.0 1.1.1'))}
    $tables=Get-RRCount $text '/Table\b'; $ths=Get-RRCount $text '/TH\b'
    if($tables -gt 0 -and $ths -gt 0){$c.Add((New-RRResult Tables 'Table headers' Pass High "Found $tables tables and $ths header cells." 'Verify table relationships manually.' 'WCAG 2.0 1.3.1'))}elseif($tables -gt 0){$c.Add((New-RRResult Tables 'Table headers' Warning High "Found $tables tables and no /TH signals." 'Add table header cells and verify relationships.' 'WCAG 2.0 1.3.1'))}else{$c.Add((New-RRResult Tables 'Table headers' Info None 'No table tags found.' 'No table action detected.' 'WCAG 2.0 1.3.1'))}
    if(Test-RRText $text '/Encrypt\b'){$c.Add((New-RRResult Security 'Assistive technology access' Warning High 'Found /Encrypt.' 'Verify security settings permit assistive technology access.' 'WCAG 2.0 4.1.2'))}else{$c.Add((New-RRResult Security 'Assistive technology access' Pass High 'No /Encrypt entry found.' 'Keep security settings compatible with assistive technology.' 'WCAG 2.0 4.1.2'))}
    New-RRScan $FilePath PDF $Bytes.Length 'Estimated pages' $pages @($c.ToArray()) 'Heuristic PDF scan. Use PAC, Acrobat Preflight, CommonLook, and manual testing for final decisions.'
}

function Invoke-RROfficeScan {
    param([byte[]]$Bytes,[string]$FilePath,[string]$Kind)
    $c=New-Object System.Collections.Generic.List[object]
    try{$entries=Get-RRZipText $Bytes}catch{$c.Add((New-RRResult File "Open $Kind package" Fail Critical $_.Exception.Message 'Repair the file or save as a modern Office file.' 'WCAG 2.0 4.1.2')); return New-RRScan $FilePath $Kind $Bytes.Length 'Estimated items' 0 @($c.ToArray())}
    $all=($entries|% Text)-join "`n"; $core=($entries|? Name -eq 'docProps/core.xml'|select -First 1).Text
    $title=Test-RRText $core '<dc:title>\s*[^<]+'; if($title){$c.Add((New-RRResult Document Title Pass Medium 'Found core title metadata.' 'Confirm the title is meaningful.' 'WCAG 2.0 2.4.2'))}else{$c.Add((New-RRResult Document Title Fail Medium 'No core title metadata found.' 'Add a title in File > Info > Properties.' 'WCAG 2.0 2.4.2'))}
    $images=Get-RRCount $all '<a:blip\b'; $alt=Get-RRCount $all '(descr|title)\s*=\s*"[^"]+"'
    if($images -eq 0){$c.Add((New-RRResult Images 'Image alternate text' Pass High 'No embedded image references found.' 'No image action detected.' 'WCAG 2.0 1.1.1'))}elseif($alt -ge $images){$c.Add((New-RRResult Images 'Image alternate text' Pass High "Found $images image references and $alt title/description signals." 'Verify alt text manually.' 'WCAG 2.0 1.1.1'))}else{$c.Add((New-RRResult Images 'Image alternate text' Warning High "Found $images images and $alt title/description signals." 'Add alt text or mark decorative images.' 'WCAG 2.0 1.1.1'))}
    if($Kind -eq 'Word document'){
        $doc=($entries|? Name -eq 'word/document.xml'|select -First 1).Text; $items=Get-RRCount $doc '<w:p\b'; $heads=Get-RRCount $doc 'Heading[1-6]'; $tables=Get-RRCount $doc '<w:tbl\b'; $headers=Get-RRCount $doc '<w:tblHeader\b'
        if($heads -gt 0){$c.Add((New-RRResult Structure 'Heading styles' Pass High "Found $heads heading style references." 'Verify heading order.' 'WCAG 2.0 1.3.1; 2.4.6'))}else{$c.Add((New-RRResult Structure 'Heading styles' Warning High 'No Heading 1-6 style references found.' 'Use built-in heading styles.' 'WCAG 2.0 1.3.1; 2.4.6'))}
        if($tables -gt 0 -and $headers -gt 0){$c.Add((New-RRResult Tables 'Header rows' Pass High "Found $tables tables and $headers header row markers." 'Verify table structure.' 'WCAG 2.0 1.3.1'))}elseif($tables -gt 0){$c.Add((New-RRResult Tables 'Header rows' Warning High "Found $tables tables and no header row markers." 'Use table header rows.' 'WCAG 2.0 1.3.1'))}
        return New-RRScan $FilePath $Kind $Bytes.Length 'Estimated paragraphs' $items @($c.ToArray())
    }
    if($Kind -eq 'PowerPoint presentation'){
        $slides=@($entries|? Name -match '^ppt/slides/slide\d+\.xml$'); $slideText=($slides|% Text)-join "`n"; $titles=Get-RRCount $slideText '<p:ph\b[^>]*type\s*=\s*"(ctrTitle|title)"'; $textRuns=Get-RRCount $slideText '<a:t>'
        if($titles -ge $slides.Count -and $slides.Count -gt 0){$c.Add((New-RRResult Structure 'Slide titles' Pass High "Found title placeholders for $titles of $($slides.Count) slides." 'Confirm titles are unique.' 'WCAG 2.0 2.4.6'))}else{$c.Add((New-RRResult Structure 'Slide titles' Warning High "Found $titles title placeholders across $($slides.Count) slides." 'Give every slide a descriptive title.' 'WCAG 2.0 2.4.6'))}
        if($textRuns -gt 0){$c.Add((New-RRResult Structure 'Selectable text' Pass High "Found $textRuns text runs." 'Keep text as real text.' 'WCAG 2.0 1.4.5'))}else{$c.Add((New-RRResult Structure 'Selectable text' Fail High 'No slide text runs found.' 'Avoid image-only slides.' 'WCAG 2.0 1.4.5'))}
        return New-RRScan $FilePath $Kind $Bytes.Length 'Estimated slides' $slides.Count @($c.ToArray())
    }
    $sheets=@($entries|? Name -match '^xl/worksheets/sheet\d+\.xml$'); $workbook=($entries|? Name -eq 'xl/workbook.xml'|select -First 1).Text; $generic=Get-RRCount $workbook 'name\s*=\s*"Sheet\d+"'; $tables=@($entries|? Name -match '^xl/tables/table\d+\.xml$')
    if($generic -eq 0 -and $sheets.Count -gt 0){$c.Add((New-RRResult Navigation 'Worksheet names' Pass Medium 'No default Sheet1-style names detected.' 'Confirm worksheet names are meaningful.' 'WCAG 2.0 2.4.6'))}else{$c.Add((New-RRResult Navigation 'Worksheet names' Warning Medium "Found $generic default sheet-name signals." 'Rename sheets with descriptive names.' 'WCAG 2.0 2.4.6'))}
    if($tables.Count -gt 0){$c.Add((New-RRResult Tables 'Excel tables' Pass High "Found $($tables.Count) Excel table definitions." 'Confirm header labels are meaningful.' 'WCAG 2.0 1.3.1'))}else{$c.Add((New-RRResult Tables 'Excel tables' Warning Medium 'No Excel table definitions found.' 'Use formatted tables with headers for data ranges.' 'WCAG 2.0 1.3.1'))}
    New-RRScan $FilePath $Kind $Bytes.Length 'Estimated sheets' $sheets.Count @($c.ToArray())
}

function Invoke-RRHtmlScan {
    param([byte[]]$Bytes,[string]$FilePath)
    $t=Get-RRTextFromBytes $Bytes; $c=New-Object System.Collections.Generic.List[object]
    if(Test-RRText $t '<title>\s*[^<]+'){$c.Add((New-RRResult Document 'Page title' Pass High 'Found title element.' 'Confirm the title is unique.' 'WCAG 2.0 2.4.2'))}else{$c.Add((New-RRResult Document 'Page title' Fail High 'No non-empty title element found.' 'Add a concise title.' 'WCAG 2.0 2.4.2'))}
    if(Test-RRText $t '<html\b[^>]*\blang\s*='){$c.Add((New-RRResult Document 'Page language' Pass High 'Found html lang attribute.' 'Confirm language code.' 'WCAG 2.0 3.1.1'))}else{$c.Add((New-RRResult Document 'Page language' Fail High 'No html lang attribute found.' 'Add lang to the html element.' 'WCAG 2.0 3.1.1'))}
    $heads=Get-RRCount $t '<h[1-6]\b'; if($heads -gt 0){$c.Add((New-RRResult Structure Headings Pass High "Found $heads headings." 'Verify hierarchy and labels.' 'WCAG 2.0 1.3.1; 2.4.6'))}else{$c.Add((New-RRResult Structure Headings Warning High 'No headings found.' 'Use headings for page sections.' 'WCAG 2.0 1.3.1; 2.4.6'))}
    $imgs=Get-RRCount $t '<img\b'; $alts=Get-RRCount $t '<img\b[^>]*\balt\s*='; if($imgs -eq 0){$c.Add((New-RRResult Images 'Image alt attributes' Pass High 'No img elements found.' 'No image action detected.' 'WCAG 2.0 1.1.1'))}elseif($alts -ge $imgs){$c.Add((New-RRResult Images 'Image alt attributes' Pass High "Found $imgs images and $alts alt attributes." 'Verify alt quality.' 'WCAG 2.0 1.1.1'))}else{$c.Add((New-RRResult Images 'Image alt attributes' Fail High "Found $imgs images and only $alts alt attributes." 'Add alt attributes to every img.' 'WCAG 2.0 1.1.1'))}
    $inputs=Get-RRCount $t '<(input|select|textarea)\b'; $labels=(Get-RRCount $t '<label\b')+(Get-RRCount $t 'aria-label\s*=|aria-labelledby\s*='); if($inputs -gt 0 -and $labels -lt $inputs){$c.Add((New-RRResult Forms 'Form labels' Warning High "Found $inputs controls and $labels label/name signals." 'Associate labels with controls.' 'WCAG 2.0 3.3.2; 4.1.2'))}elseif($inputs -gt 0){$c.Add((New-RRResult Forms 'Form labels' Pass High "Found $inputs controls and $labels label/name signals." 'Verify accessible names.' 'WCAG 2.0 3.3.2; 4.1.2'))}
    New-RRScan $FilePath 'HTML document' $Bytes.Length 'Estimated lines' @(($t -split "`n")).Count @($c.ToArray())
}

function Invoke-RRMarkdownScan {
    param([byte[]]$Bytes,[string]$FilePath)
    $t=Get-RRTextFromBytes $Bytes; $c=New-Object System.Collections.Generic.List[object]
    $heads=Get-RRCount $t '(?m)^\s{0,3}#{1,6}\s+\S'; if($heads -gt 0){$c.Add((New-RRResult Structure Headings Pass High "Found $heads Markdown headings." 'Confirm heading order.' 'WCAG 2.0 1.3.1; 2.4.6'))}else{$c.Add((New-RRResult Structure Headings Warning High 'No Markdown headings found.' 'Use # headings for structure.' 'WCAG 2.0 1.3.1; 2.4.6'))}
    $imgs=[regex]::Matches($t,'!\[([^\]]*)\]\([^)]+\)'); $empty=0; foreach($i in $imgs){if([string]::IsNullOrWhiteSpace($i.Groups[1].Value)){$empty++}}
    if($imgs.Count -eq 0){$c.Add((New-RRResult Images 'Image alt text' Pass High 'No Markdown images found.' 'No image action detected.' 'WCAG 2.0 1.1.1'))}elseif($empty -eq 0){$c.Add((New-RRResult Images 'Image alt text' Pass High "Found $($imgs.Count) images and no empty alt text." 'Verify alt quality.' 'WCAG 2.0 1.1.1'))}else{$c.Add((New-RRResult Images 'Image alt text' Fail High "Found $empty empty image alt labels." 'Add useful alt text.' 'WCAG 2.0 1.1.1'))}
    $tables=Get-RRCount $t '(?m)^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$'; if($tables -gt 0){$c.Add((New-RRResult Tables 'Markdown tables' Warning Medium "Found $tables Markdown table separators." 'Verify rendered table headers.' 'WCAG 2.0 1.3.1'))}
    New-RRScan $FilePath 'Markdown document' $Bytes.Length 'Estimated lines' @(($t -split "`n")).Count @($c.ToArray()) 'Validate Markdown in its rendered publishing context.'
}

function Invoke-RRTextScan {
    param([byte[]]$Bytes,[string]$FilePath,[string]$Type)
    $t=Get-RRTextFromBytes $Bytes; $lines=@($t -split "`r?`n"|?{$_ -ne ''}); $c=New-Object System.Collections.Generic.List[object]
    if($lines.Count -gt 0){$c.Add((New-RRResult Content 'Readable content' Pass High "Found $($lines.Count) non-empty rows/lines." 'Keep content clear and structured.' 'WCAG 2.0 1.3.1'))}else{$c.Add((New-RRResult Content 'Readable content' Fail High 'No readable content found.' 'Verify file encoding and content.' 'WCAG 2.0 1.3.1'))}
    if($Type -eq 'CSV data' -and $lines.Count -gt 0){$cols=@($lines[0] -split ','); if(@($cols|?{$_ -match '^\s*\d'}).Count -eq 0){$c.Add((New-RRResult Tables 'Header row' Pass High 'First row appears textual.' 'Confirm headers are clear and unique.' 'WCAG 2.0 1.3.1'))}else{$c.Add((New-RRResult Tables 'Header row' Warning High 'First row may not contain clear headers.' 'Use a first row with column names.' 'WCAG 2.0 1.3.1'))}}
    New-RRScan $FilePath $Type $Bytes.Length 'Estimated lines' $lines.Count @($c.ToArray())
}

function Invoke-ReadRiteScan {
    param([string]$FilePath)
    if(-not(Test-Path -LiteralPath $FilePath -PathType Leaf)){throw "File not found: $FilePath"}
    $bytes=[IO.File]::ReadAllBytes($FilePath); $ext=[IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    switch($ext){ '.pdf'{Invoke-RRPdfScan $bytes $FilePath}; '.docx'{Invoke-RROfficeScan $bytes $FilePath 'Word document'}; '.pptx'{Invoke-RROfficeScan $bytes $FilePath 'PowerPoint presentation'}; '.xlsx'{Invoke-RROfficeScan $bytes $FilePath 'Excel workbook'}; '.html'{Invoke-RRHtmlScan $bytes $FilePath}; '.htm'{Invoke-RRHtmlScan $bytes $FilePath}; '.md'{Invoke-RRMarkdownScan $bytes $FilePath}; '.markdown'{Invoke-RRMarkdownScan $bytes $FilePath}; '.csv'{Invoke-RRTextScan $bytes $FilePath 'CSV data'}; '.txt'{Invoke-RRTextScan $bytes $FilePath 'Plain text'}; '.doc'{Invoke-RRTextScan $bytes $FilePath 'Legacy Word document advisory'}; '.ppt'{Invoke-RRTextScan $bytes $FilePath 'Legacy PowerPoint advisory'}; '.xls'{Invoke-RRTextScan $bytes $FilePath 'Legacy Excel advisory'}; default{throw "Unsupported file type: $ext"} }
}

function New-ReadRiteReport {
    param($Scan)
    $lines=New-Object System.Collections.Generic.List[string]
    $lines.Add('# ReadRite Accessibility Report'); $lines.Add(''); $lines.Add("Generated: $($Scan.GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss'))"); $lines.Add("File: $($Scan.FilePath)"); $lines.Add("Type: $($Scan.FileType)"); $lines.Add("$($Scan.ItemLabel): $($Scan.EstimatedItems)"); $lines.Add("Score: $($Scan.Score)%"); $lines.Add(''); $lines.Add("Summary: $($Scan.Counts.Pass) pass, $($Scan.Counts.Warning) warning, $($Scan.Counts.Fail) fail, $($Scan.Counts.Info) info"); $lines.Add(''); $lines.Add("$($Scan.Notes)"); $lines.Add(''); $lines.Add('| Status | Severity | Category | Check | Evidence | Recommendation | Reference |'); $lines.Add('| --- | --- | --- | --- | --- | --- | --- |')
    foreach($r in $Scan.Checks){$lines.Add("| $($r.Status) | $($r.Severity) | $($r.Category) | $($r.Check) | $($r.Evidence -replace '\|','/') | $($r.Recommendation -replace '\|','/') | $($r.Reference -replace '\|','/') |")}
    $lines -join [Environment]::NewLine
}

function Start-ReadRiteUi {
    Add-Type -AssemblyName PresentationFramework; Add-Type -AssemblyName PresentationCore; Add-Type -AssemblyName WindowsBase
    $w=New-Object Windows.Window; $w.Title='ReadRite'; $w.Width=1080; $w.Height=720; $w.MinWidth=860; $w.MinHeight=560; $w.WindowStartupLocation='CenterScreen'; $w.FontFamily='Segoe UI'; $w.Background='#F5F7FA'
    $grid=New-Object Windows.Controls.Grid; $grid.Margin='16'; 0..4|%{$rd=New-Object Windows.Controls.RowDefinition; $rd.Height=if($_ -eq 3){'*'}else{'Auto'}; $grid.RowDefinitions.Add($rd)}
    $title=New-Object Windows.Controls.TextBlock; $title.Text='ReadRite'; $title.FontSize=26; $title.FontWeight='SemiBold'; $title.Margin='0,0,0,2'; [Windows.Controls.Grid]::SetRow($title,0); $grid.Children.Add($title)|Out-Null
    $sub=New-Object Windows.Controls.TextBlock; $sub.Text='Windows document accessibility triage for PDF, Office, HTML, Markdown, text, and CSV'; $sub.Margin='0,34,0,12'; $sub.Foreground='#4A5568'; [Windows.Controls.Grid]::SetRow($sub,0); $grid.Children.Add($sub)|Out-Null
    $bar=New-Object Windows.Controls.DockPanel; [Windows.Controls.Grid]::SetRow($bar,1); $grid.Children.Add($bar)|Out-Null
    $pathBox=New-Object Windows.Controls.TextBox; $pathBox.IsReadOnly=$true; $pathBox.MinHeight=34; $pathBox.Margin='0,0,8,10'; [Windows.Controls.DockPanel]::SetDock($pathBox,'Left'); $bar.Children.Add($pathBox)|Out-Null
    $open=New-Object Windows.Controls.Button; $open.Content='Open File'; $open.MinWidth=95; $open.Margin='0,0,8,10'; $bar.Children.Add($open)|Out-Null
    $run=New-Object Windows.Controls.Button; $run.Content='Run Check'; $run.MinWidth=95; $run.Margin='0,0,8,10'; $bar.Children.Add($run)|Out-Null
    $export=New-Object Windows.Controls.Button; $export.Content='Export Report'; $export.MinWidth=110; $export.IsEnabled=$false; $export.Margin='0,0,0,10'; $bar.Children.Add($export)|Out-Null
    $summary=New-Object Windows.Controls.TextBlock; $summary.Text='Ready'; $summary.Margin='0,0,0,10'; [Windows.Controls.Grid]::SetRow($summary,2); $grid.Children.Add($summary)|Out-Null
    $dg=New-Object Windows.Controls.DataGrid; $dg.AutoGenerateColumns=$true; $dg.IsReadOnly=$true; $dg.CanUserAddRows=$false; $dg.Background='White'; [Windows.Controls.Grid]::SetRow($dg,3); $grid.Children.Add($dg)|Out-Null
    $detail=New-Object Windows.Controls.TextBox; $detail.IsReadOnly=$true; $detail.TextWrapping='Wrap'; $detail.Height=90; $detail.Margin='0,10,0,0'; [Windows.Controls.Grid]::SetRow($detail,4); $grid.Children.Add($detail)|Out-Null
    $script:last=$null
    $scanAction={ if([string]::IsNullOrWhiteSpace($pathBox.Text)){[Windows.MessageBox]::Show('Select a supported file first.','ReadRite')|Out-Null; return}; try{$w.Cursor=[Windows.Input.Cursors]::Wait; $script:last=Invoke-ReadRiteScan $pathBox.Text; $dg.ItemsSource=$script:last.Checks; $summary.Text="Score $($script:last.Score)% - $($script:last.Counts.Pass) pass, $($script:last.Counts.Warning) warning, $($script:last.Counts.Fail) fail"; $export.IsEnabled=$true}catch{[Windows.MessageBox]::Show($_.Exception.Message,'ReadRite scan failed')|Out-Null}finally{$w.Cursor=$null} }
    $open.Add_Click({$d=New-Object Microsoft.Win32.OpenFileDialog; $d.Filter='Supported files|*.pdf;*.docx;*.pptx;*.xlsx;*.html;*.htm;*.md;*.markdown;*.txt;*.csv;*.doc;*.ppt;*.xls|All files|*.*'; if($d.ShowDialog($w)){ $pathBox.Text=$d.FileName; & $scanAction }})
    $run.Add_Click($scanAction)
    $export.Add_Click({if($null -eq $script:last){return}; $d=New-Object Microsoft.Win32.SaveFileDialog; $d.Filter='Markdown report (*.md)|*.md|Text file (*.txt)|*.txt'; $d.FileName=([IO.Path]::GetFileNameWithoutExtension($script:last.FileName)+'-readrite-report.md'); if($d.ShowDialog($w)){[IO.File]::WriteAllText($d.FileName,(New-ReadRiteReport $script:last),[Text.Encoding]::UTF8)}})
    $dg.Add_SelectionChanged({if($dg.SelectedItem){$detail.Text=$dg.SelectedItem.Recommendation + "`r`n" + $dg.SelectedItem.Reference}})
    $w.Content=$grid; if($Path -and (Test-Path -LiteralPath $Path)){ $pathBox.Text=(Resolve-Path $Path).Path; $w.Add_ContentRendered($scanAction) }; [void]$w.ShowDialog()
}

if($SelfTest){$sample='<html lang="en"><head><title>Sample</title></head><body><main><h1>Sample</h1><img alt="Chart" src="x.png"></main></body></html>'; $scan=Invoke-RRHtmlScan ([Text.Encoding]::UTF8.GetBytes($sample)) 'self-test.html'; if($scan.Score -le 0){throw 'Self-test failed'}; "Self-test passed. Score: $($scan.Score)%."; return}
if($NoGui){if([string]::IsNullOrWhiteSpace($Path)){throw 'Use -Path with -NoGui.'}; New-ReadRiteReport (Invoke-ReadRiteScan $Path); return}
Start-ReadRiteUi
