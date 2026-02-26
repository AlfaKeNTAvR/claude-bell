#Requires -Version 5.1
<#
.SYNOPSIS
Install claude-bell hooks for Windows Terminal / PowerShell.

Idempotent: safe to run multiple times.
Does not require administrator rights.
#>

$ErrorActionPreference = 'Stop'

$Repo = $PSScriptRoot

Write-Host 'Installing claude-bell (Windows)...'
Write-Host ''

# -- 1. Register ClaudeCode app ID (HKCU - no admin required) -----------------
$AppId   = 'ClaudeCode'
$RegPath = "HKCU:\Software\Classes\AppUserModelId\$AppId"
$isNew   = -not (Test-Path $RegPath)
New-Item -Path $RegPath -Force | Out-Null
New-ItemProperty -Path $RegPath -Name DisplayName -Value 'Claude Code' `
    -PropertyType String -Force | Out-Null
New-ItemProperty -Path $RegPath -Name ShowInSettings -Value 1 `
    -PropertyType DWord -Force | Out-Null
if ($isNew) {
    Write-Host '  + Registered ClaudeCode app ID in HKCU'
} else {
    Write-Host '  v ClaudeCode app ID already registered'
}

# -- 2. Register windowsterminal: URI handler (HKCU - no admin required) ------
$WtCmd = (Get-Command wt.exe -ErrorAction SilentlyContinue)
if ($WtCmd) {
    $WtExe    = $WtCmd.Source
    $UriPath  = 'HKCU:\Software\Classes\windowsterminal'
    $isNewUri = -not (Test-Path $UriPath)
    New-Item -Path "$UriPath\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path $UriPath -Name '(default)'    -Value 'URL:Windows Terminal'
    Set-ItemProperty -Path $UriPath -Name 'URL Protocol' -Value ''
    Set-ItemProperty -Path "$UriPath\shell\open\command" -Name '(default)' -Value "`"$WtExe`" -w 0 focus-tab"
    if ($isNewUri) {
        Write-Host "  + Registered windowsterminal: URI handler -> $WtExe"
    } else {
        Write-Host '  v windowsterminal: URI handler already registered'
    }
} else {
    Write-Host '  ! wt.exe not found - skipping windowsterminal: URI handler'
}

# -- 3. Copy hook scripts ------------------------------------------------------
$HooksDir = Join-Path $HOME '.claude\hooks'
New-Item -ItemType Directory -Path $HooksDir -Force | Out-Null

Copy-Item "$Repo\hooks\stop.ps1"   "$HooksDir\stop.ps1"   -Force
Copy-Item "$Repo\hooks\notify.ps1" "$HooksDir\notify.ps1" -Force
Write-Host "  + Hooks -> $HooksDir"

# -- 4. Merge settings-hooks-windows.json into ~/.claude/settings.json ---------
$Settings = Join-Path $HOME '.claude\settings.json'
$NewHooks = Get-Content "$Repo\settings-hooks-windows.json" -Raw | ConvertFrom-Json

if (-not (Test-Path $Settings)) {
    Copy-Item "$Repo\settings-hooks-windows.json" $Settings
    Write-Host "  + Settings -> $Settings (created)"
} else {
    $existing = $null
    try {
        $existing = Get-Content $Settings -Raw | ConvertFrom-Json
    } catch {
        $backup = $Settings + '.bak'
        Write-Host "  ! $Settings is not valid JSON - backing up to $backup and recreating from template."
        Copy-Item $Settings $backup -Force
        Copy-Item "$Repo\settings-hooks-windows.json" $Settings -Force
        Write-Host "  + Settings -> $Settings (recreated from template)"
    }
    if ($existing -ne $null) {
        $merged = $existing
        if (-not $merged.hooks) {
            $merged | Add-Member -MemberType NoteProperty -Name hooks -Value ([PSCustomObject]@{})
        }
        $anyMerged = $false
        foreach ($event in $NewHooks.hooks.PSObject.Properties.Name) {
            $cur     = $merged.hooks.$event
            $addList = @($NewHooks.hooks.$event)
            if ($cur) {
                $existingArr = @($cur)
                foreach ($hook in $addList) {
                    $hookJson = ($hook | ConvertTo-Json -Depth 10 -Compress)
                    $already  = $existingArr | Where-Object { ($_ | ConvertTo-Json -Depth 10 -Compress) -eq $hookJson }
                    if (-not $already) {
                        $existingArr += $hook
                        $anyMerged    = $true
                    }
                }
                $merged.hooks.$event = $existingArr
            } else {
                $merged.hooks | Add-Member -MemberType NoteProperty -Name $event -Value $addList -Force
                $anyMerged = $true
            }
        }
        if ($anyMerged) {
            [System.IO.File]::WriteAllText($Settings, ($merged | ConvertTo-Json -Depth 10))
            Write-Host "  + Hooks merged -> $Settings"
        } else {
            Write-Host "  v Hooks already present in $Settings (skipped)"
        }
    }
}

Write-Host ''
Write-Host 'Done.'
Write-Host ''
Write-Host 'Note: toasts are suppressed when Windows Terminal is already in focus.'
Write-Host 'When Focus Assist / Do Not Disturb suppresses them, they still land in the notification center (Win+N).'
