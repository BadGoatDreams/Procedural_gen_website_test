# Generate-Structure.ps1 (Corrected v3)

<#
.SYNOPSIS
Generates a text file representing the directory structure, with optional content previews.

.DESCRIPTION
Scans the current directory recursively up to a specified depth.
Outputs a tree structure to a text file.
Includes previews of the first few lines for common text/code files and CSVs if they are below a size threshold.

.PARAMETER OutputPath
The name of the file to save the structure to. Defaults to 'directory_structure.txt'.

.PARAMETER MaxDepth
The maximum directory depth to scan. Defaults to 4. 0 means only current directory files.

.PARAMETER MaxPreviewSizeKB
Maximum file size in Kilobytes to attempt reading content preview. Defaults to 512 KB.

.PARAMETER MaxPreviewLines
Maximum number of lines to show in the preview for general text/code files. Defaults to 15.

.PARAMETER MaxCSVPreviewLines
Maximum number of lines to show in the preview for CSV files. Defaults to 10.

.EXAMPLE
.\Generate-Structure.ps1

.EXAMPLE
.\Generate-Structure.ps1 -MaxDepth 2 -OutputPath ".\My Project Structure.txt"

.NOTES
Author: Gemini AI
Date:   2025-04-10 (Corrected 2025-04-10 v3)
Requires PowerShell 3.0 or higher (for Get-ChildItem -Depth).
Excel (.xls/.xlsx) preview is not supported natively.
Corrected encoding handling for Get-Content compatibility.
#>
param(
    [string]$OutputPath = ".\directory_structure.txt",
    [int]$MaxDepth = 4,
    [int]$MaxPreviewSizeKB = 512, # Max size in KB for preview
    [int]$MaxPreviewLines = 15,
    [int]$MaxCSVPreviewLines = 10
)

# --- Configuration ---
$PreviewExtensions = @('.py', '.js', '.txt', '.md', '.html', '.css', '.json', '.yaml', '.yml', '.sh', '.ps1', '.bat')
$CsvExtensions = @('.csv')
$MaxPreviewSizeBytes = $MaxPreviewSizeKB * 1024
# --- End Configuration ---

# Function to get file preview
function Get-FilePreview {
    param(
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo]$File,
        [int]$MaxLines,
        [long]$MaxSize
    )

    if ($File.Length -eq 0) { return "    [File is empty]" }
    if ($File.Length -gt $MaxSize) { return "    [File too large ($($File.Length / 1KB) KB) for content preview]" }

    try {
        # --- CORRECTED Encoding Detection ---
        # Determine the encoding NAME (string) expected by Get-Content
        $EncodingName = 'Default' # Default to system ANSI

        try {
            # Read first few bytes to check for UTF-8 BOM
            $FirstBytes = [System.IO.File]::ReadAllBytes($File.FullName) | Select-Object -First 3
            if ($FirstBytes.Count -ge 3 -and $FirstBytes[0] -eq 0xEF -and $FirstBytes[1] -eq 0xBB -and $FirstBytes[2] -eq 0xBF) {
                $EncodingName = 'UTF8' # Use 'UTF8' string for Get-Content
            } else {
                # Simple test: try reading the first line as UTF8 (no BOM).
                # If it works without error, assume UTF8. Otherwise, stick to Default (ANSI).
                # This isn't foolproof but avoids the type error and often works.
                 try {
                      Get-Content -Path $File.FullName -TotalCount 1 -Encoding UTF8 -ErrorAction Stop | Out-Null
                      $EncodingName = 'UTF8' # If the above didn't throw, use UTF8
                 } catch {
                      $EncodingName = 'Default' # Fallback to Default if UTF8 read failed
                 }
            }
        } catch {
            # If error reading bytes (e.g., permissions), stick with Default
            $EncodingName = 'Default'
            Write-Warning "Could not read initial bytes of '$($File.FullName)' to detect BOM. Using '$EncodingName'."
        }
        # --- END CORRECTED Encoding Detection ---


        # --- Use the determined $EncodingName (string) with Get-Content ---
        Write-Verbose "Attempting to read '$($File.FullName)' with encoding '$EncodingName'"
        $Content = Get-Content -Path $File.FullName -TotalCount $MaxLines -Encoding $EncodingName -ErrorAction SilentlyContinue

        $PreviewLines = @()
        $LineCount = 0
        foreach ($Line in $Content) {
            # Check if we got an error object instead of a string line (can happen with encoding issues)
            if ($Line -is [System.Management.Automation.ErrorRecord]) {
                 Write-Warning "Encoding error encountered reading line $($LineCount+1) of '$($File.FullName)' with encoding '$EncodingName'."
                 # Optionally add an error marker to the preview
                 # $PreviewLines += "    | [Encoding Error on this line]"
                 continue # Skip this line
            }
            $PreviewLines += "    | $($Line.TrimEnd())"
            $LineCount++
        }

        # Check if file was truncated
        if ($LineCount -eq $MaxLines) {
             # Use $EncodingName here too
             $TestContent = Get-Content -Path $File.FullName -TotalCount ($MaxLines + 1) -Encoding $EncodingName -ErrorAction SilentlyContinue
             if ($TestContent.Count -gt $MaxLines) {
                 $PreviewLines += "    | ... (truncated)"
             }
        }

        if ($PreviewLines.Count -eq 0) {
            # Check if the file actually has size > 0; if so, reading failed somehow
            if ($File.Length -gt 0) {
                 return "    [Could not read preview content - possibly binary or encoding issue with '$EncodingName']"
            } else {
                 # This case should have been caught earlier, but double-check
                 return "    [File is empty]"
            }
        }

        return $PreviewLines -join "`n"

    } catch {
        # Catch errors during Get-Content or other operations within the main try block
        return "    [Error processing file preview: $($_.Exception.Message)]"
    }
}

# --- Main Execution ---
$StartTime = Get-Date
$CurrentLocation = (Get-Location).Path
# Use -Verbose switch when running the script to see detailed messages like encoding attempts
Write-Host "Generating directory structure for '$CurrentLocation'..."
Write-Host "Using Max Depth: $MaxDepth"
Write-Host "Saving to: $OutputPath"

$Structure = @()
$Structure += "Directory Structure For: $CurrentLocation"
$Structure += "Maximum Depth: $MaxDepth"
$Structure += "Content Preview Max Size: ${MaxPreviewSizeKB} KB"
$Structure += ('-' * 60)

# Get all items recursively, controlling depth
Write-Verbose "Getting directory items..."
$Items = Get-ChildItem -Path $CurrentLocation -Recurse -Depth $MaxDepth -ErrorAction SilentlyContinue | Sort-Object -Property @{Expression={$_.PSIsContainer}; Descending=$true}, @{Expression={$_.FullName}; Ascending=$true}
Write-Verbose "Found $($Items.Count) items within depth limit (pre-filtering)."

$RootDir = Get-Item -Path $CurrentLocation
$Structure += "$($RootDir.Name)/ (Scanning Root)"

foreach ($Item in $Items) {
    # Calculate relative path and depth
    $RelativePath = $Item.FullName.Substring($CurrentLocation.Length)
    if ($RelativePath.StartsWith('\') -or $RelativePath.StartsWith('/')) {
        $RelativePath = $RelativePath.Substring(1)
    }
    $PathParts = $RelativePath.Split([System.IO.Path]::DirectorySeparatorChar) | Where-Object { $_.Length -gt 0 }
    $Depth = $PathParts.Count
    if ($Item.PSIsContainer) { $Depth -=1 }

    # Skip items deeper than MaxDepth
    if ($Depth -ge $MaxDepth) {
        Write-Verbose "Skipping item deeper than max depth: $($Item.FullName)"
        continue
    }

    $Indent = "  " * ($Depth + 1) + "|-- "
    Write-Verbose "Processing item: $($Item.FullName) at depth $Depth"

    # Construct the item string
    $ItemString = "$Indent$($Item.Name)"
    if ($Item.PSIsContainer) {
        $ItemString += "/"
    }
    $Structure += $ItemString

    # Add preview for files
    if (-not $Item.PSIsContainer) {
        $Ext = $Item.Extension.ToLower()
        $Preview = $null

        try {
            if ($PreviewExtensions -contains $Ext) {
                Write-Verbose "Getting preview for text file: $($Item.Name)"
                $Preview = Get-FilePreview -File $Item -MaxLines $MaxPreviewLines -MaxSize $MaxPreviewSizeBytes
            } elseif ($CsvExtensions -contains $Ext) {
                 Write-Verbose "Getting preview for CSV file: $($Item.Name)"
                $Preview = Get-FilePreview -File $Item -MaxLines $MaxCSVPreviewLines -MaxSize $MaxPreviewSizeBytes
            } elseif ($Ext -in '.xls', '.xlsx') {
                $Structure += ("  " * ($Depth + 1)) + "    [Excel file ($($Item.Length / 1KB) KB) - Preview not supported]"
            }

            if ($Preview) {
                # Indent preview lines further
                $IndentedPreview = $Preview.Split("`n") | ForEach-Object { "  " * ($Depth + 1) + $_ }
                $Structure += $IndentedPreview -join "`n"
            }
        } catch {
             $Structure += ("  " * ($Depth + 1)) + "    [Error processing file $($Item.Name): $($_.Exception.Message)]"
        }
    }
}

$Structure += "`n" + ('-' * 60)
$Structure += "Scan completed at $(Get-Date)"

# Save to file
try {
    Write-Verbose "Saving structure to '$OutputPath'"
    Out-File -InputObject ($Structure -join "`r`n") -FilePath $OutputPath -Encoding UTF8 -Force
    Write-Host "`nStructure saved to: '$(Resolve-Path $OutputPath)'"
} catch {
    Write-Error "Failed to write output file: $($_.Exception.Message)"
}