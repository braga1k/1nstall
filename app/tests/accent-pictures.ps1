# Saves pictures of the window of a built 1nstall.exe with several accent colours, in the dark
# and in the light theme, to judge the appearance by eye. Needs an interactive desktop.
#
# The application runs with --ui-test and is told each colour through ONEINSTALL_TEST_ACCENT:
# the accent colour of Windows is neither read for the pictures nor changed.
#   .\app\tests\accent-pictures.ps1 -Exe dist\1nstall.exe -Out pictures
param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$Out)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$exe=(Resolve-Path -LiteralPath $Exe).Path
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$accents=[ordered]@{ blue='0078D4'; green='107C10'; red='E81123'; yellow='FFB900'; purple='744DA9'; teal='00B7C3' }
foreach ($name in $accents.Keys) {
    $root=Start-App '--ui-test' @{ONEINSTALL_TEST_ACCENT=$accents[$name]}
    try {
        # A selection shows the accent where it matters: switches, the count and the Install button.
        Toggle (Named $root '7-Zip'); Toggle (Named $root 'Adobe Acrobat Reader')
        Start-Sleep -Milliseconds 1500
        Picture $Out ('dark-'+$name) | Out-Null
        Invoke (Named $root 'Settings')
        $combo=Wait-Until { ById $root 'ThemeChoice' } 10
        $combo.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Expand(); Start-Sleep -Milliseconds 350
        (Wait-Until { Named $combo 'Light' } 10).GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 250
        $combo.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse(); Start-Sleep -Milliseconds 600
        Invoke (ById $root 'InstallMode') 1500
        Picture $Out ('light-'+$name) | Out-Null
        "pictured $name (#$($accents[$name]))"
    } finally { Stop-App }
}
