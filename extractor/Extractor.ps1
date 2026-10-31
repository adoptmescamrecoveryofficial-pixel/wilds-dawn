param(
    [string]$BaseNsp,
    [string]$UpdateNsp,
    [string]$KeysDirectory,
    [switch]$CheckOnly,
    [string]$UnpackedDirectory,
    [switch]$Headless,
    [string]$WorkDirectory,
    [string]$ResultFile,
    [string]$StatusFile
)

$ErrorActionPreference = 'Stop'
$tool = Join-Path $PSScriptRoot 'nstool.exe'
if (!$KeysDirectory) {
    $bundledKeys = Join-Path $PSScriptRoot 'keys'
    $KeysDirectory = if (Test-Path -LiteralPath (Join-Path $bundledKeys 'prod.keys') -PathType Leaf) { $bundledKeys } else { $PSScriptRoot }
}
$keyFile = Join-Path $KeysDirectory 'prod.keys'
$script:logFile = $null
function Report-Stage {
    param([int]$Step,[string]$Message)
    if ($StatusFile) { [IO.File]::WriteAllText($StatusFile, "$Step|$Message") }
    Write-Host $Message -ForegroundColor Cyan
}

function Run-Tool {
    param([string[]]$Arguments, [switch]$CheckPartitions)
    $lines = @(& $tool @Arguments 2>&1)
    $code = $LASTEXITCODE
    $text = $lines -join "`r`n"
    if ($script:logFile) { Add-Content -LiteralPath $script:logFile -Value $text }
    if ($code -ne 0) { throw "NSTool failed:`r`n$text" }
    if ($text -match '(?im)^\[[^\]\r\n]*ERROR[^\]\r\n]*\]') {
        throw "NSTool reported an error:`r`n$text"
    }
    if ($CheckPartitions -and $text -match '(?im)^\[WARNING\] NCA Partition [01] not readable') {
        throw "NSTool could not read a required game partition:`r`n$text"
    }
    return $text
}

function Pick-Package {
    param([string]$Title, [string]$Suggested)
    Add-Type -AssemblyName System.Windows.Forms
    if ($Headless) { throw "Select the base-game and update NSPs in the launcher first." }
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Title
    $dialog.Filter = 'Nintendo Switch package (*.nsp)|*.nsp'
    $dialog.InitialDirectory = $PSScriptRoot
    if ($Suggested) { $dialog.FileName = $Suggested }
    try {
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            throw 'Cancelled. No game files were changed.'
        }
        return $dialog.FileName
    } finally { $dialog.Dispose() }
}

function Find-Program {
    param([string]$Folder, [string[]]$KeyArguments, [string]$BasePath)
    $inspectArgs = $KeyArguments
    if ($BasePath) { $inspectArgs += @('--basenca', $BasePath) }
    $found = @(
        foreach ($nca in Get-ChildItem -LiteralPath $Folder -Filter '*.nca' -File -Recurse) {
            $info = Run-Tool -Arguments ($inspectArgs + @($nca.FullName))
            if ($info -match 'Content Type:\s+Program\b') {
                if ($info -notmatch 'ProgID:\s+0x([0-9a-fA-F]{16})') {
                    throw 'Could not read the Program ID.'
                }
                [pscustomobject]@{ Path = $nca.FullName; ID = $Matches[1] }
            }
        }
    )
    if ($found.Count -ne 1) {
        throw "Expected exactly one Program NCA in $Folder; found $($found.Count). Use a standard base-game or update NSP, without multiple games."
    }
    if ($found[0].ID -ne '01007ef00011e000') {
        throw 'This package is not the Switch version of Breath of the Wild supported by this extractor.'
    }
    return $found[0]
}

try {
    Write-Host "WILD'S DAWN - BREATH OF THE WILD EXTRACTOR" -ForegroundColor Cyan
    Write-Host 'Keep this window open until extraction finishes.'
    Write-Host 'Your original NSPs and keys will not be changed.'
    if (!(Test-Path -LiteralPath $tool -PathType Leaf)) { throw 'nstool.exe is missing. Extract the entire ZIP first.' }
    if (!(Test-Path -LiteralPath $keyFile -PathType Leaf)) {
        throw 'The extractor key files are missing. Re-extract the complete launcher package, including extractor/keys, or select a valid keys folder.'
    }
    if (!(Test-Path -LiteralPath $keyFile) -or (Get-Item -LiteralPath $keyFile).Length -eq 0) { throw 'prod.keys is empty.' }

    # Offer matching filenames, but let the user explicitly select each package.
    $packages = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.nsp' -File)
    $baseGuess = @($packages | Where-Object { $_.Name -match '(?i)\[v0\]|base' })
    $updateGuess = @($packages | Where-Object { $_.Name -match '(?i)upd|update|01007ef00011e800' })
    if (!$BaseNsp) {
        $suggestion = if ($baseGuess.Count -eq 1) { $baseGuess[0].Name } else { '' }
        $BaseNsp = Pick-Package 'STEP 1 - Select the Breath of the Wild BASE GAME NSP' $suggestion
    }
    if (!$UpdateNsp) {
        $suggestion = if ($updateGuess.Count -eq 1) { $updateGuess[0].Name } else { '' }
        $UpdateNsp = Pick-Package 'STEP 2 - Select the supported Breath of the Wild UPDATE NSP' $suggestion
    }
    $BaseNsp = (Resolve-Path -LiteralPath $BaseNsp).Path
    $UpdateNsp = (Resolve-Path -LiteralPath $UpdateNsp).Path
    if ($BaseNsp -eq $UpdateNsp) { throw 'Select two different files: the base game and its update.' }
    foreach ($path in @($BaseNsp, $UpdateNsp)) {
        if ([IO.Path]::GetExtension($path) -ne '.nsp') { throw 'Only .nsp packages are supported.' }
    }

    if ($CheckOnly) {
        if (!$UnpackedDirectory) { throw 'CheckOnly requires an existing unpacked package directory.' }
        if (Test-Path -LiteralPath (Join-Path $UnpackedDirectory 'Base') -PathType Container) {
            $baseFolder = Join-Path $UnpackedDirectory 'Base'
            $updateFolder = Join-Path $UnpackedDirectory 'Update'
        } else {
            $baseFolder = Join-Path $UnpackedDirectory 'Package-2'
            $updateFolder = Join-Path $UnpackedDirectory 'Package-1'
        }
    } else {
        if (!$WorkDirectory) { $WorkDirectory = $PSScriptRoot }
        $WorkDirectory = [IO.Path]::GetFullPath($WorkDirectory)
        [IO.Directory]::CreateDirectory($WorkDirectory) | Out-Null
        $driveRoot = [IO.Path]::GetPathRoot($WorkDirectory)
        $drive = New-Object IO.DriveInfo($driveRoot)
        $minimum = (Get-Item -LiteralPath $BaseNsp).Length + (Get-Item -LiteralPath $UpdateNsp).Length + 20GB
        if ($Headless) { $minimum += 18GB } # launcher data image, shader cache and compiler workspace
        if ($drive.AvailableFreeSpace -lt $minimum) { throw "Not enough free disk space. This extraction and setup needs at least $([math]::Ceiling($minimum / 1GB)) GB free on $driveRoot." }
        $run = Join-Path $WorkDirectory ('Extraction-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6))
        $baseFolder = Join-Path $run 'Packages\Base'
        $updateFolder = Join-Path $run 'Packages\Update'
        $output = Join-Path $run 'BOTW-ready'
        foreach ($folder in @($baseFolder, $updateFolder, "$output\exefs", "$output\romfs")) {
            New-Item -ItemType Directory -Path $folder | Out-Null
        }
        $script:logFile = Join-Path $run 'Extraction.log'
        Report-Stage 1 'Unpacking base game. This may take several minutes...'
        $null = Run-Tool -Arguments @('-x', $baseFolder, $BaseNsp)
        Report-Stage 2 'Unpacking update...'
        $null = Run-Tool -Arguments @('-x', $updateFolder, $UpdateNsp)
    }

    $keyArgs = @('-k', $keyFile)
    foreach ($ticket in Get-ChildItem -LiteralPath $baseFolder, $updateFolder -Filter '*.tik' -File -Recurse) {
        $keyArgs += @('--tik', $ticket.FullName)
    }
    Report-Stage 3 'Checking keys and matching game contents...'
    $base = Find-Program $baseFolder $keyArgs
    $patch = Find-Program $updateFolder $keyArgs $base.Path
    $patchArgs = $keyArgs + @('--basenca', $base.Path)
    $tree = Run-Tool -Arguments ($patchArgs + @('--fstree', $patch.Path))
    if ($tree -match '(?i)not readable|\[.*ERROR\]|AES-CTR Key was not determined' -or $tree -notmatch 'main\.npdm') {
        throw 'Game contents could not be decrypted. Check prod.keys and the tickets in your dumps. See Extraction.log when available.'
    }
    if ($CheckOnly) {
        Write-Host 'CHECK PASSED: matching BOTW Program NCAs and readable patched ExeFS/RomFS.' -ForegroundColor Green
        exit 0
    }

    Report-Stage 4 'Extracting updated ExeFS...'
    $null = Run-Tool -CheckPartitions -Arguments ($patchArgs + @('-x', '/0', "$output\exefs", $patch.Path))
    Report-Stage 5 'Extracting complete updated RomFS. Please wait...'
    $null = Run-Tool -CheckPartitions -Arguments ($patchArgs + @('-x', '/1', "$output\romfs", $patch.Path))
    foreach ($name in @('main', 'main.npdm', 'rtld', 'sdk', 'subsdk0')) {
        $file = Join-Path "$output\exefs" $name
        if (!(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -eq 0) {
            throw "Incomplete ExeFS: $name is missing or empty."
        }
    }
    $romfs = Get-ChildItem -LiteralPath "$output\romfs" -Recurse -File | Measure-Object -Property Length -Sum
    if ($romfs.Count -eq 0) { throw 'RomFS is empty. Check the extraction log.' }
    $message = "Select this folder in Wild's Dawn, then click Set Up Game Files:`r`n$output`r`n`r`nRomFS files: $($romfs.Count)`r`nUse the game update version supported by your Wild's Dawn build."
    [IO.File]::WriteAllText((Join-Path $run 'SELECT-THIS-FOLDER.txt'), $message)
    Write-Host "`nEXTRACTION FINISHED" -ForegroundColor Green
    Write-Host $message -ForegroundColor Yellow
    Write-Host "`nThe Packages folder contains temporary unpacked archives. You may remove it after checking the result."
    if ($ResultFile) { [IO.File]::WriteAllText($ResultFile, $output) }
    Report-Stage 6 "Package extraction finished."
    if (!$Headless) { Invoke-Item -LiteralPath $output }
    exit 0
} catch {
    if ($StatusFile) { [IO.File]::WriteAllText($StatusFile, "0|$($_.Exception.Message)") }
    Write-Host "`nSTOPPED: $($_.Exception.Message)" -ForegroundColor Red
    if ($script:logFile) { Write-Host "Log: $script:logFile" }
    exit 1
}
