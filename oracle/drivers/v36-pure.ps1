# Characterization driver for the 3.6 engine.
# Evaluates every case in oracle/corpus/pure.json against the C# helpers and writes one JSON object per line.
# Only pure functions are called: nothing is installed, removed, written to the registry or deleted.
param([string]$Corpus, [Parameter(Mandatory)][string]$Out)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path (Split-Path $PSScriptRoot)
if (-not $Corpus) { $Corpus=Join-Path $repo 'oracle/corpus/pure.json' }
foreach ($helper in @('package-helper.cs','uninstall-helper.cs')) {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $repo ('src/'+$helper)))) -ReferencedAssemblies System.dll,System.Core.dll,System.Web.Extensions.dll
}
# Fixed culture: number formatting and framework messages must not depend on the machine's language.
$english=[Globalization.CultureInfo]::GetCultureInfo('en-US')
[Threading.Thread]::CurrentThread.CurrentCulture=$english
[Threading.Thread]::CurrentThread.CurrentUICulture=$english
$flags=[Reflection.BindingFlags]'Public,NonPublic,Static'
$P=[OneInstallPackages]; $U=[OneInstallUninstall]
$system32=[Environment]::GetFolderPath([Environment+SpecialFolder]::System)
. (Join-Path (Split-Path $PSScriptRoot) 'lib\json.ps1')

# Reflection keeps real nulls (PowerShell would turn a null string argument into "") and reaches private helpers.
function Call([type]$type,[string]$name,[object[]]$arguments) {
    $method=@($type.GetMethods($flags) | Where-Object { $_.Name -eq $name -and $_.GetParameters().Length -eq $arguments.Length })
    if ($method.Count -ne 1) { throw "Missing or ambiguous method $name/$($arguments.Length)." }
    $clean=New-Object object[] $arguments.Length
    for ($i=0;$i -lt $arguments.Length;$i++) { if ($null -ne $arguments[$i]) { $clean[$i]=$arguments[$i].PSObject.BaseObject } }
    return $method[0].Invoke($null,$clean)
}
function Set-Member($target,[string]$name,$value) {
    $property=$target.GetType().GetProperty($name)
    if (-not $property) { throw "Unknown property $($target.GetType().Name).$name" }
    if ($null -eq $value) { $property.SetValue($target,$null,$null) }
    else { $property.SetValue($target,[Convert]::ChangeType($value.PSObject.BaseObject,$property.PropertyType),$null) }
}
function New-App($spec) {
    $app=New-Object InstalledApp
    foreach ($entry in $spec.PSObject.Properties) { Set-Member $app $entry.Name $entry.Value }
    return $app
}
function New-Apps($list) {
    $apps=New-Object 'System.Collections.Generic.List[InstalledApp]'
    if ($null -ne $list) { foreach ($item in $list) { $apps.Add((New-App $item)) } }
    return ,$apps.ToArray()
}
function New-Inventory($spec) {
    $inventory=New-Object PackageInventory
    $inventory.Complete=[bool]$spec.Complete; $inventory.Partial=[bool]$spec.Partial
    foreach ($item in $spec.Packages) {
        $record=New-Object PackageRecord
        foreach ($name in @('Id','Name','Source','InstalledVersion')) { Set-Member $record $name $item.$name }
        $inventory.Packages.Add($record)
    }
    return $inventory
}
function New-StringArray($list) {
    if ($null -eq $list) { return $null }
    $items=@($list); $result=New-Object string[] $items.Length
    for ($i=0;$i -lt $items.Length;$i++) { if ($null -ne $items[$i]) { $result[$i]=[string]$items[$i] } }
    return ,$result
}
function To-Code($value) {
    if ($value -is [string]) { return [BitConverter]::ToInt32([BitConverter]::GetBytes([Convert]::ToUInt32($value.Substring(2),16)),0) }
    return [int]$value
}
function Show-Inventory($inventory) {
    return [ordered]@{
        Complete=$inventory.Complete; Partial=$inventory.Partial; Message=$inventory.Message
        Packages=@($inventory.Packages | ForEach-Object { [ordered]@{ Id=$_.Id; Name=$_.Name; Source=$_.Source; InstalledVersion=$_.InstalledVersion } })
    }
}
function Show-Setup($setup) {
    return [ordered]@{
        Version=$setup.Version; Keys=@($setup.Keys)
        Apps=@($setup.Apps | ForEach-Object { [ordered]@{ Id=$_.Id; Source=$_.Source; Name=$_.Name; Version=$_.Version } })
    }
}
function Show-Command($start) {
    $file=[regex]::Replace($start.FileName,[regex]::Escape($system32),'{SYSTEM32}',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    return [ordered]@{ FileName=$file; Arguments=$start.Arguments }
}

$functions=@{
    'Packages.ValidId'               ={ param($a) Call $P 'ValidId' @($a[0]) }
    'Packages.ValidSource'           ={ param($a) Call $P 'ValidSource' @($a[0]) }
    'Packages.KnownVersion'          ={ param($a) Call $P 'KnownVersion' @($a[0]) }
    'Packages.Quote'                 ={ param($a) Call $P 'Quote' @($a[0]) }
    'Packages.Arguments'             ={ param($a) Call $P 'Arguments' @($a[0],$a[1]) }
    'Packages.Outcome'               ={ param($a) Call $P 'Outcome' @((To-Code $a[0])) }
    'Packages.Explain'               ={ param($a) Call $P 'Explain' @((To-Code $a[0])) }
    'Packages.ParseExport'           ={ param($a) Show-Inventory (Call $P 'ParseExport' @($a[0])) }
    'Packages.InstalledState'        ={ param($a) Call $P 'InstalledState' @((New-Inventory $a[0]),(New-StringArray $a[1]),$a[2]) }
    'Packages.ParseSetup'            ={ param($a) Show-Setup (Call $P 'ParseSetup' @($a[0])) }
    'Packages.Redact'                ={ param($a) Call $P 'Redact' @($a[0]) }
    'Uninstall.QuoteArgument'        ={ param($a) Call $U 'QuoteArgument' @($a[0]) }
    'Uninstall.Token'                ={ param($a) Call $U 'Token' @($a[0]) }
    'Uninstall.Product'              ={ param($a) Call $U 'Product' @($a[0]) }
    'Uninstall.Names'                ={ param($a) ,@(Call $U 'Names' @((New-App $a[0]))) }
    'Uninstall.ReservedRegistryName' ={ param($a) Call $U 'ReservedRegistryName' @($a[0]) }
    'Uninstall.Rot13'                ={ param($a) Call $U 'Rot13' @($a[0]) }
    'Uninstall.Inside'               ={ param($a) Call $U 'Inside' @($a[0],$a[1]) }
    'Uninstall.FormatBytes'          ={ param($a) Call $U 'FormatBytes' @([long]$a[0]) }
    'Uninstall.FormatBytes@pt-PT'    ={ param($a)
        [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('pt-PT')
        try { Call $U 'FormatBytes' @([long]$a[0]) } finally { [Threading.Thread]::CurrentThread.CurrentCulture=$english }
    }
    'Uninstall.SafeRegistry'         ={ param($a) Call $U 'SafeRegistry' @($a[0],(New-App $a[1]),(New-Apps $a[2])) }
    'Uninstall.SafeRegistryValue'    ={ param($a) Call $U 'SafeRegistryValue' @($a[0],$a[1],(New-App $a[2]),(New-Apps $a[3])) }
    'Uninstall.GetCommand'           ={ param($a) Show-Command (Call $U 'GetCommand' @((New-App $a[0]))) }
}

# Corpus generators keep very long inputs readable. The golden file records the generator, not its expansion.
function Test-Generator($value) { return ($value -is [Management.Automation.PSCustomObject]) -and ($null -ne $value.PSObject.Properties['$gen']) }
function Expand-Generator($spec) {
    switch ([string]$spec.'$gen') {
        'repeat' {
            $text=([string]$spec.unit)*[int]$spec.count
            if ($spec.PSObject.Properties['suffix']) { $text+=[string]$spec.suffix }
            return $text
        }
        'join' {
            $parts=New-Object 'System.Collections.Generic.List[string]'
            for ($i=0;$i -lt [int]$spec.count;$i++) { $parts.Add(([string]$spec.prefix)+$i+([string]$spec.suffix)) }
            return [string]::Join([string]$spec.sep,$parts)
        }
        'concat' {
            $text=New-Object Text.StringBuilder
            foreach ($part in $spec.parts) { if (Test-Generator $part) { [void]$text.Append((Expand-Generator $part)) } else { [void]$text.Append([string]$part) } }
            return $text.ToString()
        }
        default { throw "Unknown generator $($spec.'$gen')." }
    }
}

$corpusData=[IO.File]::ReadAllText($Corpus,[Text.Encoding]::UTF8) | ConvertFrom-Json
$lines=New-Object 'System.Collections.Generic.List[string]'
foreach ($function in $corpusData.functions) {
    $name=[string]$function.fn
    if (-not $functions.ContainsKey($name)) { throw "No driver mapping for $name." }
    $cases=New-Object System.Collections.ArrayList
    if ($function.PSObject.Properties['cases']) { foreach ($case in $function.cases) { [void]$cases.Add($case) } }
    if ($function.PSObject.Properties['ranges']) {
        foreach ($range in $function.ranges) {
            $from=[Convert]::ToUInt32(([string]$range[0]).Substring(2),16); $to=[Convert]::ToUInt32(([string]$range[1]).Substring(2),16)
            for ($code=[long]$from;$code -le [long]$to;$code++) { [void]$cases.Add(@(,('0x{0:X8}' -f $code))) }
        }
    }
    foreach ($case in $cases) {
        $inputs=New-Object object[] $case.Length
        for ($i=0;$i -lt $case.Length;$i++) { $inputs[$i]=$case[$i]; if (Test-Generator $case[$i]) { $inputs[$i]=Expand-Generator $case[$i] } }
        $row=[ordered]@{ fn=$name; args=$case }
        try { $row['out']=& $functions[$name] $inputs }
        catch { $failure=$_.Exception.GetBaseException(); $row['err']=[ordered]@{ type=$failure.GetType().Name; message=$failure.Message } }
        $lines.Add((ConvertTo-CanonicalJson $row))
    }
}
$folder=Split-Path -Parent ([IO.Path]::GetFullPath($Out))
if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
[IO.File]::WriteAllText($Out,([string]::Join("`n",$lines)+"`n"),(New-Object Text.UTF8Encoding($false)))
Write-Output ('{0} cases across {1} functions -> {2}' -f $lines.Count,@($corpusData.functions).Count,$Out)
