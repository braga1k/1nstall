# Canonical JSON writer shared by the oracle scripts: ASCII-only, insertion-ordered keys, no whitespace.
# ConvertTo-Json is avoided on purpose: its escaping and array handling differ between PowerShell versions.
function Add-JsonString([Text.StringBuilder]$builder,[string]$text) {
    [void]$builder.Append('"')
    # \z, not $: in .NET "$" also matches before a final newline, which would leak a raw line break.
    if ($text -cmatch '\A[\x20\x21\x23-\x5B\x5D-\x7E]*\z') { [void]$builder.Append($text) }
    else {
        foreach ($character in $text.ToCharArray()) {
            $code=[int]$character
            if ($code -eq 34) { [void]$builder.Append('\"') }
            elseif ($code -eq 92) { [void]$builder.Append('\\') }
            elseif ($code -lt 32 -or $code -gt 126) { [void]$builder.Append('\u').Append($code.ToString('x4')) }
            else { [void]$builder.Append($character) }
        }
    }
    [void]$builder.Append('"')
}
function Add-Json([Text.StringBuilder]$builder,$value) {
    if ($null -eq $value) { [void]$builder.Append('null'); return }
    $object=$value.PSObject.BaseObject
    if ($object -is [string]) { Add-JsonString $builder $object; return }
    if ($object -is [bool]) { [void]$builder.Append($(if ($object) { 'true' } else { 'false' })); return }
    if ($object -is [int] -or $object -is [long] -or $object -is [uint32] -or $object -is [decimal]) {
        [void]$builder.Append(([IFormattable]$object).ToString($null,[Globalization.CultureInfo]::InvariantCulture)); return
    }
    if ($object -is [Collections.IDictionary]) {
        [void]$builder.Append('{'); $first=$true
        # GetEnumerator, not .Keys: PowerShell resolves $dictionary.Keys to an entry named "Keys" when one exists.
        foreach ($entry in $object.GetEnumerator()) {
            if (-not $first) { [void]$builder.Append(',') }; $first=$false
            Add-JsonString $builder ([string]$entry.Key); [void]$builder.Append(':'); Add-Json $builder $entry.Value
        }
        [void]$builder.Append('}'); return
    }
    if ($object -is [Management.Automation.PSCustomObject]) {
        [void]$builder.Append('{'); $first=$true
        # Properties live on the wrapper; the base object of a custom object is an empty shared placeholder.
        foreach ($entry in $value.PSObject.Properties) {
            if (-not $first) { [void]$builder.Append(',') }; $first=$false
            Add-JsonString $builder $entry.Name; [void]$builder.Append(':'); Add-Json $builder $entry.Value
        }
        [void]$builder.Append('}'); return
    }
    if ($object -is [Collections.IEnumerable]) {
        [void]$builder.Append('['); $first=$true
        foreach ($item in $object) {
            if (-not $first) { [void]$builder.Append(',') }; $first=$false
            Add-Json $builder $item
        }
        [void]$builder.Append(']'); return
    }
    throw "Unsupported value type $($object.GetType().FullName)."
}

function ConvertTo-CanonicalJson($value) {
    $builder=New-Object Text.StringBuilder
    Add-Json $builder $value
    return $builder.ToString()
}
