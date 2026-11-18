# Runs "<exe> --startup-test" repeatedly: the Phase 0 ruler, extended to the whole process tree,
# because a WebView2 application spreads its memory over several processes.
# "fresh" = the caches beside the exe are deleted first; "warm" = they are kept.
param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$Out, [string]$Arguments='', [int]$Fresh=3, [int]$Warm=10)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class ProcessTree {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct Entry { public uint Size, Usage, Id; public IntPtr Heap; public uint Module, Threads, Parent; public int Priority; public uint Flags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string File; }
    [DllImport("kernel32", SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint process);
    [DllImport("kernel32", CharSet=CharSet.Unicode)] static extern bool Process32FirstW(IntPtr snapshot, ref Entry entry);
    [DllImport("kernel32", CharSet=CharSet.Unicode)] static extern bool Process32NextW(IntPtr snapshot, ref Entry entry);
    [DllImport("kernel32")] static extern bool CloseHandle(IntPtr handle);
    // Working set, private bytes and process count of the root and everything it started.
    public static long[] Sample(int root) {
        var parents=new Dictionary<int,int>();
        IntPtr snapshot=CreateToolhelp32Snapshot(2,0);
        try {
            var entry=new Entry(); entry.Size=(uint)Marshal.SizeOf(typeof(Entry));
            if(Process32FirstW(snapshot,ref entry)) do { parents[(int)entry.Id]=(int)entry.Parent; } while(Process32NextW(snapshot,ref entry));
        } finally { CloseHandle(snapshot); }
        var tree=new HashSet<int>(); if(parents.ContainsKey(root)) tree.Add(root);
        bool grew=true;
        while(grew) { grew=false; foreach(var pair in parents) if(!tree.Contains(pair.Key) && tree.Contains(pair.Value)) { tree.Add(pair.Key); grew=true; } }
        long working=0, priv=0, count=0;
        foreach(int id in tree) {
            try { using(var process=Process.GetProcessById(id)) { working+=process.WorkingSet64; priv+=process.PrivateMemorySize64; count++; } } catch { }
        }
        return new[]{working,priv,count};
    }
}
'@
$exe=(Resolve-Path -LiteralPath $Exe).Path
$dir=Split-Path $exe
$log=Join-Path $dir 'startup-test.log'
$caches=@('runtime-cache','webview-data') | ForEach-Object { Join-Path $dir $_ }
function Run-Once([string]$kind,[int]$n) {
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $p=Start-Process -FilePath $exe -ArgumentList (('--startup-test '+$Arguments).Trim()) -PassThru
    $peakWs=0L; $treeWs=0L; $treePrivate=0L; $processes=0L
    while (-not $p.HasExited) {
        if ($clock.ElapsedMilliseconds -gt 60000) { $p.Kill(); throw "Run exceeded 60 s ($kind $n)." }
        try {
            $p.Refresh(); if ($p.PeakWorkingSet64 -gt $peakWs) { $peakWs=$p.PeakWorkingSet64 }
            $sample=[ProcessTree]::Sample($p.Id)
            if ($sample[0] -gt $treeWs) { $treeWs=$sample[0] }; if ($sample[1] -gt $treePrivate) { $treePrivate=$sample[1] }; if ($sample[2] -gt $processes) { $processes=$sample[2] }
        } catch { }
        Start-Sleep -Milliseconds 5
    }
    $wall=$clock.ElapsedMilliseconds
    $row=[ordered]@{Kind=$kind; Sample=$n; ExitCode=$p.ExitCode; WallMs=$wall; PeakWorkingSetMB=[math]::Round($peakWs/1MB,1); TreeWorkingSetMB=[math]::Round($treeWs/1MB,1); TreePrivateMB=[math]::Round($treePrivate/1MB,1); Processes=$processes}
    if (Test-Path -LiteralPath $log) {
        foreach ($line in Get-Content -LiteralPath $log) {
            if ($line -match '^(READY|FirstFrameMs|BeforeShowMs|LoadedMs|RenderMs) ([0-9]+)$') { $row[$(if ($Matches[1] -eq 'READY') { 'ReadyMs' } else { $Matches[1] })]=[long]$Matches[2] }
        }
    }
    [pscustomobject]$row
}
$rows=@()
for ($i=1; $i -le $Fresh; $i++) { foreach ($cache in $caches) { if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Recurse -Force } }; $rows+=Run-Once 'fresh' $i }
for ($i=1; $i -le $Warm; $i++) { $rows+=Run-Once 'warm' $i }
function Median($values) { $sorted=@($values | Sort-Object); if ($sorted.Count -eq 0) { return $null }; $middle=[int][math]::Floor($sorted.Count/2); if ($sorted.Count % 2) { $sorted[$middle] } else { ($sorted[$middle-1]+$sorted[$middle])/2 } }
$warmRows=@($rows | Where-Object Kind -eq 'warm')
$files=@(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Extension -in '.exe','.dll','.winmd' })
$summary=[ordered]@{
    Exe=Split-Path $exe -Leaf; Arguments=$Arguments
    ExeBytes=(Get-Item -LiteralPath $exe).Length
    ShippedBytes=($files | Measure-Object Length -Sum).Sum
    ShippedFiles=@($files | ForEach-Object { $_.Name })
    FirstRunReadyMs=$rows[0].ReadyMs
    WarmReadyMs=Median $warmRows.ReadyMs; WarmReadyMin=($warmRows.ReadyMs | Measure-Object -Minimum).Minimum; WarmReadyMax=($warmRows.ReadyMs | Measure-Object -Maximum).Maximum
    WarmRenderMs=Median $warmRows.RenderMs
    WarmPeakWorkingSetMB=Median $warmRows.PeakWorkingSetMB
    WarmTreeWorkingSetMB=Median $warmRows.TreeWorkingSetMB
    WarmTreePrivateMB=Median $warmRows.TreePrivateMB
    Processes=($warmRows.Processes | Measure-Object -Maximum).Maximum
    ExitCodes=@($rows.ExitCode | Sort-Object -Unique)
}
[ordered]@{Summary=$summary; Runs=$rows} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Out -Encoding UTF8
$rows | Format-Table -AutoSize | Out-String -Width 220
$summary | ConvertTo-Json -Compress
