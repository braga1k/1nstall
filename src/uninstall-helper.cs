using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using Microsoft.Win32;

// Windows uninstall workflow; bounded product discovery inspired by BCU.
// AppCompat/UserAssist path scanning and Rot13 adapted from BCU (modified for
// exact path boundaries, shared-app protection and value-only cleanup).
// Copyright (c) 2017 Marcin Szeniak (https://github.com/Klocman/)
// Apache License Version 2.0; see licenses/BCU. Other workflow code is independent.
public sealed class InstalledApp : INotifyPropertyChanged
{
    public string Id { get; set; }
    public string Name { get; set; }
    public string Publisher { get; set; }
    public string Version { get; set; }
    public string Kind { get; set; }
    public string Location { get; set; }
    public string Command { get; set; }
    public string RegistryPath { get; set; }
    public string PackageFamily { get; set; }
    public bool Machine { get; set; }
    public bool View32 { get; set; }
    public bool Msi { get; set; }
    public long RestartRequestedAt { get; set; }
    public bool CanRemove { get; set; }
    public long SizeKB { get; set; }
    public string Detail { get { return (Publisher ?? "Unknown publisher") + "  ·  " + Version + "  ·  " + Kind + (SizeKB > 0 ? "  ·  " + (SizeKB / 1024.0).ToString("0.#") + " MB" : ""); } }
    bool selected;
    public bool Selected { get { return selected; } set { selected = value; if (PropertyChanged != null) PropertyChanged(this, new PropertyChangedEventArgs("Selected")); } }
    public event PropertyChangedEventHandler PropertyChanged;
}
public sealed class LeftoverItem
{
    public string AppName { get; set; }
    public string Kind { get; set; }
    public string Path { get; set; }
    public string ValueName { get; set; }
    public string DisplayValueName { get; set; }
    public string Reason { get; set; }
    public InstalledApp Owner { get; set; }
    public bool Machine { get; set; }
    public bool View32 { get; set; }
    public bool Selected { get; set; }
    public string Detail { get { return Reason + "  ·  " + Path + (ValueName == null ? "" : "  →  " + (DisplayValueName ?? ValueName)); } }
}
public sealed class AppInventory
{
    public List<InstalledApp> Apps = new List<InstalledApp>();
    public List<string> Warnings = new List<string>();
}
public sealed class RemovalResult
{
    public List<LeftoverItem> Leftovers = new List<LeftoverItem>();
    public List<string> Messages = new List<string>();
    public string BackupFolder;
}
public static class OneInstallUninstall
{
    const string Arp = @"Software\Microsoft\Windows\CurrentVersion\Uninstall";
    static readonly string PowerShell = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
    static readonly string RegExe = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "reg.exe");
    public static readonly ConcurrentQueue<string> Progress = new ConcurrentQueue<string>();
    public static volatile bool StopRequested;
    public static string HistoryFile { get { return System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"1nstall\uninstall-history.json"); } }
    static JavaScriptSerializer Json() { return new JavaScriptSerializer { MaxJsonLength = 4194304 }; }
    static string Text(RegistryKey key, string name) { return Convert.ToString(key.GetValue(name, "")); }
    static bool Flag(RegistryKey key, string name) { return Convert.ToString(key.GetValue(name, 0)) == "1"; }
    static string Literal(string value) { return "'" + value.Replace("'", "''") + "'"; }
    [DllImport("kernel32.dll")] static extern ulong GetTickCount64();
    static long BootTime { get { return DateTime.UtcNow.Ticks - (long)GetTickCount64() * TimeSpan.TicksPerMillisecond; } }
    static bool WaitingForRestart(InstalledApp app) { return app.RestartRequestedAt > 0 && Math.Abs(app.RestartRequestedAt - BootTime) < TimeSpan.TicksPerMinute * 2; }
    [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)] static extern int SHLoadIndirectString(string source, StringBuilder output, uint size, IntPtr reserved);
    static string StoreLabel(string label, string package, string identity)
    {
        if (!String.IsNullOrEmpty(label) && label.StartsWith("ms-resource:", StringComparison.OrdinalIgnoreCase))
        {
            string resource = label.Substring(12).TrimStart('/');
            foreach (string uri in new[] { label, "ms-resource://" + identity + "/resources/" + resource, "ms-resource://" + identity + "/" + resource })
            {
                var output = new StringBuilder(1024);
                if (SHLoadIndirectString("@{" + package + "? " + uri + "}", output, 1024, IntPtr.Zero) == 0 && output.Length > 0) return output.ToString();
            }
        }
        else if (!String.IsNullOrWhiteSpace(label)) return label;
        return Regex.Replace(identity.Split('.').Last(), @"([a-z])([A-Z])", "$1 $2");
    }
    static string RunPowerShell(string code, int timeout)
    {
        var start = new ProcessStartInfo(PowerShell, "-NoProfile -NonInteractive -EncodedCommand " + Convert.ToBase64String(Encoding.Unicode.GetBytes("$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new(); " + code)));
        start.UseShellExecute = false; start.CreateNoWindow = true; start.RedirectStandardOutput = true; start.RedirectStandardError = true;
        start.StandardOutputEncoding = Encoding.UTF8; start.StandardErrorEncoding = Encoding.UTF8;
        using (var process = Process.Start(start))
        {
            var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(timeout)) { process.Kill(); throw new TimeoutException("Windows app service did not respond. Refresh to try again."); }
            if (process.ExitCode != 0) throw new InvalidOperationException(error.Result.Trim());
            return output.Result.Trim();
        }
    }
    static List<InstalledApp> Desktop(AppInventory result, bool includeHidden)
    {
        var apps = new List<InstalledApp>();
        foreach (bool machine in new[] { false, true }) foreach (bool view32 in new[] { false, true })
        {
            using (var hive = RegistryKey.OpenBaseKey(machine ? RegistryHive.LocalMachine : RegistryHive.CurrentUser, view32 ? RegistryView.Registry32 : RegistryView.Registry64))
            using (var parent = hive.OpenSubKey(Arp))
            {
                if (parent == null) continue;
                foreach (string child in parent.GetSubKeyNames())
                {
                    try
                    {
                        using (var key = parent.OpenSubKey(child))
                        {
                            if (key == null || String.IsNullOrWhiteSpace(Text(key, "DisplayName"))) continue;
                            if (!includeHidden && (Flag(key, "SystemComponent") || Text(key, "ParentKeyName") != "" || Regex.IsMatch(Text(key, "ReleaseType"), "Update|Hotfix", RegexOptions.IgnoreCase))) continue;
                            long size; Int64.TryParse(Text(key, "EstimatedSize"), out size);
                            var app = new InstalledApp { Id = (machine ? "HKLM" : "HKCU") + (view32 ? "32:" : "64:") + child, RegistryPath = Arp + "\\" + child,
                                Name = Text(key, "DisplayName"), Publisher = Text(key, "Publisher"), Version = Text(key, "DisplayVersion"), Kind = "Desktop",
                                Location = Text(key, "InstallLocation"), Command = Text(key, "UninstallString"), Machine = machine, View32 = view32, Msi = Flag(key, "WindowsInstaller"), SizeKB = size };
                            try { GetCommand(app); app.CanRemove = true; } catch { app.CanRemove = false; }
                            apps.Add(app);
                        }
                    }
                    catch (Exception e) { result.Warnings.Add("Could not read an installed app: " + e.Message); }
                }
            }
        }
        // HKCU Software is shared across views on many systems; retain distinct HKLM registrations.
        return apps.GroupBy(a => !a.Machine ? "HKCU:" + a.RegistryPath : a.Id, StringComparer.OrdinalIgnoreCase).Select(g => g.First()).ToList();
    }
    public static AppInventory Inventory()
    {
        var result = new AppInventory(); result.Apps = Desktop(result, false);
        try
        {
            string data = RunPowerShell("ConvertTo-Json -Compress -InputObject @(Get-AppxPackage | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage -and -not $_.NonRemovable } | ForEach-Object { $label=''; try { $manifest=Get-AppxPackageManifest $_; $label=[string]$manifest.Package.Properties.DisplayName } catch {}; [pscustomobject]@{Name=$label; Identity=$_.Name; Id=$_.PackageFullName; Family=$_.PackageFamilyName; Publisher=$_.Publisher; Version=[string]$_.Version} })", 60000);
            var rows = Json().Deserialize<List<Dictionary<string, object>>>(data);
            foreach (var row in rows ?? new List<Dictionary<string, object>>())
            {
                string id = Convert.ToString(row["Id"]), family = Convert.ToString(row["Family"]);
                if (!Regex.IsMatch(id, @"^[A-Za-z0-9._-]+$") || !Regex.IsMatch(family, @"^[A-Za-z0-9._-]+$")) continue;
                string publisher = Convert.ToString(row["Publisher"]); var cn = Regex.Match(publisher, @"(?:^|,\s*)CN=([^,]+)");
                result.Apps.Add(new InstalledApp { Id = id, PackageFamily = family, Name = StoreLabel(Convert.ToString(row["Name"]), id, Convert.ToString(row["Identity"])), Publisher = cn.Success ? cn.Groups[1].Value : publisher, Version = Convert.ToString(row["Version"]), Kind = "Microsoft Store", CanRemove = true });
            }
        }
        catch (Exception e) { result.Warnings.Add("Microsoft Store apps could not be read: " + e.Message); }
        result.Apps = result.Apps.OrderBy(a => a.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
        return result;
    }
    public static Task<AppInventory> InventoryAsync() { return Task.Run(() => Inventory()); }
    public static List<InstalledApp> LoadHistory()
    {
        try { if (new FileInfo(HistoryFile).Length > 1048576) return new List<InstalledApp>(); return Json().Deserialize<List<InstalledApp>>(File.ReadAllText(HistoryFile)) ?? new List<InstalledApp>(); }
        catch { return new List<InstalledApp>(); }
    }
    static void Remember(IEnumerable<InstalledApp> apps)
    {
        var history = LoadHistory();
        foreach (var app in apps) { history.RemoveAll(a => a.Id == app.Id); app.Selected = false; history.Add(app); }
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(HistoryFile));
        File.WriteAllText(HistoryFile, Json().Serialize(history.Skip(Math.Max(0, history.Count - 100)).ToList()));
    }
    [DllImport("shell32.dll", SetLastError = true)] static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string command, out int count);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
    public static ProcessStartInfo GetCommand(InstalledApp app)
    {
        if (app.Msi)
        {
            string code = System.IO.Path.GetFileName(app.RegistryPath); Guid guid;
            if (!Guid.TryParse(code, out guid)) throw new InvalidOperationException("Invalid Windows Installer product code.");
            return new ProcessStartInfo(System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "msiexec.exe"), "/x {" + guid.ToString() + "}");
        }
        string command = Environment.ExpandEnvironmentVariables(app.Command ?? "").Trim(), exe, arguments;
        if (command.StartsWith("\""))
        {
            int count; IntPtr memory = CommandLineToArgvW(command, out count);
            if (memory == IntPtr.Zero) throw new InvalidOperationException("Invalid uninstaller command.");
            try { exe = Marshal.PtrToStringUni(Marshal.ReadIntPtr(memory)); } finally { LocalFree(memory); }
            int end = command.IndexOf('"', 1); if (end < 0) throw new InvalidOperationException("Unclosed uninstaller path.");
            arguments = command.Substring(end + 1).Trim();
        }
        else
        {
            // Match the whole executable path before arguments, including legacy unquoted spaces.
            var match = Regex.Match(command, @"^(.+?\.exe)(?=\s|$)", RegexOptions.IgnoreCase);
            if (!match.Success) throw new InvalidOperationException("No executable uninstaller. Use Windows Settings.");
            exe = match.Groups[1].Value; arguments = command.Substring(match.Length).Trim();
        }
        if (!System.IO.Path.IsPathRooted(exe) || exe.StartsWith(@"\\") || !File.Exists(exe) || !exe.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Uninstaller is missing. Use Windows Settings.");
        if (Regex.IsMatch(System.IO.Path.GetFileNameWithoutExtension(exe), @"^(cmd|powershell|pwsh|wscript|cscript|rundll32|reg|mshta)$", RegexOptions.IgnoreCase)) throw new InvalidOperationException("This uninstaller needs Windows Settings.");
        return new ProcessStartInfo(exe, arguments);
    }
    static bool Registered(InstalledApp app, AppInventory inventory)
    {
        if (app.Kind == "Microsoft Store") return inventory.Apps.Any(a => a.Id == app.Id || a.PackageFamily == app.PackageFamily);
        if (String.IsNullOrEmpty(app.RegistryPath) || !app.RegistryPath.StartsWith(Arp + "\\", StringComparison.OrdinalIgnoreCase)) return true;
        using (var hive = RegistryKey.OpenBaseKey(app.Machine ? RegistryHive.LocalMachine : RegistryHive.CurrentUser, app.View32 ? RegistryView.Registry32 : RegistryView.Registry64))
        using (var key = hive.OpenSubKey(app.RegistryPath)) return key != null;
    }
    public static Task<RemovalResult> RemoveAsync(InstalledApp[] apps)
    {
        StopRequested = false;
        return Task.Run(() => {
            var result = new RemovalResult(); Remember(apps);
            foreach (var app in apps)
            {
                if (StopRequested) { result.Messages.Add("Stopped before the next app."); break; }
                Progress.Enqueue("Removing " + app.Name + "… Finish any publisher dialog that opens.");
                try
                {
                    if (app.Kind == "Microsoft Store")
                    {
                        if (!Regex.IsMatch(app.Id ?? "", @"^[A-Za-z0-9._-]+$")) throw new InvalidOperationException("Invalid package identity.");
                        RunPowerShell("Get-AppxPackage | Where-Object { $_.PackageFullName -eq " + Literal(app.Id) + " -and -not $_.NonRemovable -and -not $_.IsFramework } | Remove-AppxPackage -ErrorAction Stop", 180000);
                    }
                    else
                    {
                        // Re-read the registration: a stale inventory must not launch an old command.
                        var current = Desktop(new AppInventory(), false).FirstOrDefault(a => a.Id == app.Id);
                        if (current == null) { result.Messages.Add(app.Name + ": already absent."); continue; }
                        var start = GetCommand(current); start.UseShellExecute = true;
                        if (app.Machine) start.Verb = "runas";
                        using (var process = Process.Start(start))
                        {
                            process.WaitForExit();
                            if (process.ExitCode == 3010 || process.ExitCode == 1641) { app.RestartRequestedAt = BootTime; result.Messages.Add(app.Name + ": restart required. Leftovers are withheld until Windows restarts."); continue; }
                            if (process.ExitCode != 0) { result.Messages.Add(app.Name + ": uninstaller returned " + process.ExitCode + ". No cleanup was started."); continue; }
                        }
                    }
                    result.Messages.Add(app.Name + ": uninstaller finished. Registration will be checked before scanning.");
                }
                catch (Exception e) { result.Messages.Add(app.Name + ": " + e.Message); }
            }
            // Cleanup is always a separate user action, including for zero-exit uninstallers.
            Remember(apps);
            return result;
        });
    }
    static string Full(string path) { return System.IO.Path.GetFullPath(Environment.ExpandEnvironmentVariables(path.Trim().Trim('"'))).TrimEnd('\\'); }
    static bool Inside(string path, string root) { return path.Equals(root, StringComparison.OrdinalIgnoreCase) || path.StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase); }
    static string Token(string name) { return Regex.Replace(name ?? "", "[^A-Za-z0-9]", "").ToLowerInvariant(); }
    static bool Product(string name) { return Token(name).Length >= 4 && !Regex.IsMatch(Token(name), @"^(application|applications|app|apps|bin|current|x64|x86|software|microsoft|windows|programs|commonfiles|packages|data|cache|temp|1nstall)$"); }
    static List<string> Names(InstalledApp app)
    {
        var names = new List<string>();
        string name = Regex.Replace(app.Name ?? "", @"\s+(?:v?\d+(?:\.\d+)*.*|\(?(?:x64|x86|64-bit|32-bit)\)?)$", "", RegexOptions.IgnoreCase).Trim();
        if (Product(name) && !Regex.IsMatch(name, @"[\\/:*?""<>|]")) names.Add(name);
        if (!String.IsNullOrEmpty(app.Location))
        {
            try
            {
                string leaf = System.IO.Path.GetFileName(Full(app.Location));
                // Never infer ownership of a vendor root from a partial product name.
                if (Product(leaf) && (Token(name) == Token(leaf) || (Token(leaf).Length >= 6 && Token(name).Contains(Token(leaf)) && !Token(app.Publisher).Contains(Token(leaf))))) names.Add(leaf);
            }
            catch { }
        }
        return names.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }
    public static bool SafeDirectory(string path, InstalledApp owner, IEnumerable<InstalledApp> active)
    {
        try
        {
            path = Full(path);
            if (path.StartsWith(@"\\") || path.Length < 8 || !Directory.Exists(path)) return false;
            string windows = Full(Environment.GetFolderPath(Environment.SpecialFolder.Windows));
            if (Inside(path, windows)) return false;
            foreach (var folder in new[] { Environment.SpecialFolder.MyDocuments, Environment.SpecialFolder.Desktop, Environment.SpecialFolder.MyPictures, Environment.SpecialFolder.MyMusic, Environment.SpecialFolder.MyVideos })
                if (Inside(path, Full(Environment.GetFolderPath(folder)))) return false;
            string home = Full(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
            if (Inside(path, home + "\\Downloads") || Inside(path, home + "\\OneDrive")) return false;
            foreach (string root in new[] { System.IO.Path.GetPathRoot(path), home, Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData) })
                if (!String.IsNullOrEmpty(root) && Full(root).Equals(path, StringComparison.OrdinalIgnoreCase)) return false;
            string users = System.IO.Path.Combine(System.IO.Path.GetPathRoot(windows), "Users");
            if (Inside(path, users) && !Inside(path, home)) return false;
            foreach (string sensitive in new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) + "\\Common Files", Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86) + "\\Common Files", Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) + "\\WindowsApps", home + @"\AppData\Local\Packages" })
                if (Inside(path, Full(sensitive))) return false;
            if (!Names(owner).Any(n => Token(n) == Token(System.IO.Path.GetFileName(path)))) return false;
            string product = Token(System.IO.Path.GetFileName(path));
            if (active.Any(a => Names(a).Any(n => Token(n) == product) || Token(a.Publisher) == product)) return false;
            foreach (var other in active)
            {
                if (String.IsNullOrWhiteSpace(other.Location)) continue;
                string location = Full(other.Location);
                if (Inside(path, location) || Inside(location, path)) return false;
            }
            for (var parent = new DirectoryInfo(path); parent != null; parent = parent.Parent)
                if ((parent.Attributes & FileAttributes.ReparsePoint) != 0) return false;
            return true;
        }
        catch { return false; }
    }
    static bool NoLinks(string root)
    {
        // ponytail: 20k-entry scan cap; add cancellable large-tree scanning when big app profiles need review.
        var pending = new Stack<string>(); pending.Push(root); int seen = 0;
        while (pending.Count > 0)
        {
            foreach (string entry in Directory.EnumerateFileSystemEntries(pending.Pop()))
            {
                if (++seen > 20000) return false;
                var flags = File.GetAttributes(entry); if ((flags & FileAttributes.ReparsePoint) != 0) return false;
                if ((flags & FileAttributes.Directory) != 0) pending.Push(entry);
            }
        }
        return true;
    }
    public static bool SafeRegistry(string path, InstalledApp owner, IEnumerable<InstalledApp> active)
    {
        if (!Regex.IsMatch(path ?? "", @"^Software\\[\p{L}\p{N} ._()+-]+(?:\\[\p{L}\p{N} ._()+-]+){0,2}$", RegexOptions.IgnoreCase)) return false;
        var pieces = path.Split('\\'); string leaf = pieces[pieces.Length - 1];
        if (!Names(owner).Any(n => Token(n) == Token(leaf))) return false;
        if (pieces.Skip(1).Any(ReservedRegistryName)) return false;
        if (active.Any(a => Names(a).Any(n => Token(n) == Token(leaf)) || Token(a.Publisher) == Token(leaf))) return false;
        return true;
    }
    static bool KeyExists(string path, bool machine, bool view32)
    {
        using (var hive = RegistryKey.OpenBaseKey(machine ? RegistryHive.LocalMachine : RegistryHive.CurrentUser, view32 ? RegistryView.Registry32 : RegistryView.Registry64))
        using (var key = hive.OpenSubKey(path)) return key != null;
    }
    static bool ReservedRegistryName(string name) { return Regex.IsMatch(name, @"^(Microsoft|Windows|Classes|Policies|RegisteredApplications|Clients|Wow6432Node)$", RegexOptions.IgnoreCase); }
    static readonly string[] TraceKeys = {
        @"Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers",
        @"Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store",
        @"Software\Microsoft\Windows\CurrentVersion\Search\JumplistData",
        @"Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppBadgeUpdated",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppSwitched",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist\{CEBFF5CD-ACE2-4F4F-9178-9926F41749EA}\Count"
    };
    // Adapted from BCU UserAssistScanner, Copyright (c) 2017 Marcin Szeniak,
    // Apache-2.0. The caller resolves known-folder GUIDs and validates boundaries.
    static string Rot13(string input)
    {
        if (String.IsNullOrEmpty(input)) return input;
        return new string(input.Select(x => x >= 'a' && x <= 'z' ? (char)((x - 'a' + 13) % 26 + 'a')
            : (x >= 'A' && x <= 'Z' ? (char)((x - 'A' + 13) % 26 + 'A') : x)).ToArray());
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SHGetKnownFolderPath(ref Guid folder, uint flags, IntPtr token, out IntPtr path);
    static string TracePath(string key, string value)
    {
        string path = key.IndexOf("\\UserAssist\\", StringComparison.OrdinalIgnoreCase) >= 0 ? Rot13(value) : value;
        foreach (string suffix in new[] { ".FriendlyAppName", ".ApplicationCompany" })
            if (path.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)) path = path.Substring(0, path.Length - suffix.Length);
        if (path.StartsWith("{"))
        {
            int end = path.IndexOf('}'); Guid guid;
            if (end >= 0 && Guid.TryParse(path.Substring(0, end + 1), out guid))
            {
                IntPtr resolved;
                if (SHGetKnownFolderPath(ref guid, 0, IntPtr.Zero, out resolved) == 0)
                {
                    try { path = Marshal.PtrToStringUni(resolved).TrimEnd('\\') + path.Substring(end + 1); }
                    finally { Marshal.FreeCoTaskMem(resolved); }
                }
            }
        }
        return path;
    }
    public static bool SafeRegistryValue(string key, string value, InstalledApp owner, IEnumerable<InstalledApp> active)
    {
        if (!TraceKeys.Contains(key, StringComparer.OrdinalIgnoreCase) || String.IsNullOrEmpty(value) || value.IndexOfAny(new[] { '"', '\r', '\n', '\0' }) >= 0) return false;
        try
        {
            if (String.IsNullOrWhiteSpace(owner.Location)) return false;
            string location = Full(owner.Location), path = TracePath(key, value);
            if (Inside(location, Full(Environment.GetFolderPath(Environment.SpecialFolder.Windows)))) return false;
            foreach (var special in new[] { Environment.SpecialFolder.UserProfile, Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86, Environment.SpecialFolder.CommonApplicationData, Environment.SpecialFolder.LocalApplicationData, Environment.SpecialFolder.ApplicationData })
                if (location.Equals(Full(Environment.GetFolderPath(special)), StringComparison.OrdinalIgnoreCase)) return false;
            if (!System.IO.Path.IsPathRooted(path) || path.StartsWith(@"\\") || !path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) return false;
            path = Full(path);
            if (!Names(owner).Any(n => Token(n) == Token(System.IO.Path.GetFileName(location))) || !Inside(path, location) || File.Exists(path)) return false;
            if (active.Any(a => Names(a).Any(n => Names(owner).Any(o => Token(o) == Token(n))))) return false;
            foreach (var app in active)
                if (!String.IsNullOrWhiteSpace(app.Location) && (Inside(location, Full(app.Location)) || Inside(Full(app.Location), location))) return false;
            return true;
        }
        catch { return false; }
    }
    // ponytail: scan three levels / 20k entries in known roots, not the entire disk.
    // Extend with additional evidence-based providers if deeper app layouts require them.
    static void DiscoverFolders(string root, int depth, InstalledApp app, List<InstalledApp> active, RemovalResult result, HashSet<string> seen, ref int count)
    {
        try
        {
            foreach (string folder in Directory.EnumerateDirectories(root))
            {
                if (++count > 20000) { result.Messages.Add(app.Name + ": folder discovery limit reached; results may be incomplete."); return; }
                if ((File.GetAttributes(folder) & FileAttributes.ReparsePoint) != 0) continue;
                if (SafeDirectory(folder, app, active) && NoLinks(folder))
                {
                    if (seen.Add(folder)) result.Leftovers.Add(new LeftoverItem { Kind = "Folder", Path = folder, Owner = app, AppName = app.Name, Reason = "Exact product name · may include settings or personal app data" });
                }
                else if (depth < 2 && !Regex.IsMatch(System.IO.Path.GetFileName(folder), @"^(Microsoft|Windows|WindowsApps|Packages|Common Files|1nstall)$", RegexOptions.IgnoreCase))
                    DiscoverFolders(folder, depth + 1, app, active, result, seen, ref count);
                if (count > 20000) return;
            }
        }
        catch (Exception e) { result.Messages.Add(app.Name + ": folder discovery skipped " + root + ": " + e.Message); }
    }
    static void DiscoverKeys(RegistryKey root, string path, int depth, bool machine, bool view32, InstalledApp app, List<InstalledApp> active, RemovalResult result, HashSet<string> seen, ref int count)
    {
        try
        {
            foreach (string name in root.GetSubKeyNames())
            {
                if (++count > 20000) { result.Messages.Add(app.Name + ": registry discovery limit reached; results may be incomplete."); return; }
                if (ReservedRegistryName(name)) continue;
                string key = path + "\\" + name;
                using (var child = root.OpenSubKey(name))
                {
                    if (child == null) continue;
                    if (SafeRegistry(key, app, active))
                    {
                        if (seen.Add((machine ? "HKLM" + view32 : "HKCU") + key)) result.Leftovers.Add(new LeftoverItem { Kind = "Registry", Path = key, Owner = app, AppName = app.Name, Machine = machine, View32 = view32, Reason = "Exact product key · backup before removal" });
                    }
                    else if (depth < 2) DiscoverKeys(child, key, depth + 1, machine, view32, app, active, result, seen, ref count);
                }
                if (count > 20000) return;
            }
        }
        catch (Exception e) { result.Messages.Add(app.Name + ": registry discovery skipped " + path + ": " + e.Message); }
    }
    public static Task<RemovalResult> ScanAsync(InstalledApp[] owners)
    {
        return Task.Run(() => {
            var result = new RemovalResult(); var inventory = Inventory(); var protection = new AppInventory();
            var active = Desktop(protection, true); active.AddRange(inventory.Apps.Where(a => a.Kind == "Microsoft Store"));
            if (protection.Warnings.Count > 0) throw new InvalidOperationException("Installed-app protection could not be verified. No leftover scan was offered.");
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var app in owners)
            {
                Progress.Enqueue("Checking leftovers for " + app.Name + "…");
                if (WaitingForRestart(app)) { result.Messages.Add(app.Name + ": restart Windows before scanning leftovers."); continue; }
                if (app.Kind == "Microsoft Store" && inventory.Warnings.Count > 0) { result.Messages.Add(app.Name + ": Store inventory unavailable; cleanup withheld."); continue; }
                if (Registered(app, inventory)) { result.Messages.Add(app.Name + ": still registered. Finish removal or restart, then check again."); continue; }
                // Store package data is intentionally managed by Windows; no manual WindowsApps/Packages cleanup.
                if (app.Kind == "Microsoft Store") { result.Messages.Add(app.Name + ": removed; Windows manages its package data."); continue; }
                int folderCount = 0;
                foreach (var folder in new[] { Environment.SpecialFolder.LocalApplicationData, Environment.SpecialFolder.ApplicationData, Environment.SpecialFolder.CommonApplicationData, Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86 })
                {
                    if (folderCount > 20000) break;
                    DiscoverFolders(Environment.GetFolderPath(folder), 0, app, active, result, seen, ref folderCount);
                }
                foreach (bool machine in new[] { false, true }) foreach (bool view32 in new[] { false, true })
                {
                    using (var hive = RegistryKey.OpenBaseKey(machine ? RegistryHive.LocalMachine : RegistryHive.CurrentUser, view32 ? RegistryView.Registry32 : RegistryView.Registry64))
                    {
                        using (var software = hive.OpenSubKey("Software"))
                        {
                            int count = 0;
                            if (software != null) DiscoverKeys(software, "Software", 0, machine, view32, app, active, result, seen, ref count);
                        }
                        foreach (string key in TraceKeys)
                        {
                            try
                            {
                                using (var trace = hive.OpenSubKey(key))
                                {
                                    if (trace == null) continue;
                                    foreach (string value in trace.GetValueNames())
                                        if (SafeRegistryValue(key, value, app, active) && seen.Add((machine ? "HKLM" + view32 : "HKCU") + key + "::" + value))
                                            result.Leftovers.Add(new LeftoverItem { Kind = "Registry", Path = key, ValueName = value, DisplayValueName = TracePath(key, value), Owner = app, AppName = app.Name, Machine = machine, View32 = view32, Reason = "Windows app trace · only this value is removed; key is retained" });
                                }
                            }
                            catch (Exception e) { result.Messages.Add(app.Name + ": Windows trace check skipped: " + e.Message); }
                        }
                    }
                }
                if (!String.IsNullOrWhiteSpace(app.Location))
                {
                    try
                    {
                        string full = Full(app.Location);
                        if (SafeDirectory(full, app, active) && NoLinks(full) && seen.Add(full)) result.Leftovers.Add(new LeftoverItem { Kind = "Folder", Path = full, Owner = app, AppName = app.Name, Reason = "Product folder · may include settings or personal app data" });
                    }
                    catch (Exception e) { result.Messages.Add(app.Name + ": folder check skipped: " + e.Message); }
                }
                result.Messages.Add(app.Name + ": checked product folders, product keys and Windows app traces. Only verified candidates are shown; no matches does not prove every residue is absent.");
            }
            return result;
        });
    }
    public static Task<RemovalResult> CleanAsync(LeftoverItem[] items)
    {
        return Task.Run(() => {
            var result = new RemovalResult(); var inventory = Inventory(); var protection = new AppInventory(); var active = Desktop(protection, true);
            active.AddRange(inventory.Apps.Where(a => a.Kind == "Microsoft Store"));
            if (protection.Warnings.Count > 0) throw new InvalidOperationException("Installed-app protection could not be verified; cleanup stopped.");
            result.BackupFolder = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"1nstall\Backups", DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N").Substring(0, 8));
            Directory.CreateDirectory(result.BackupFolder);
            File.WriteAllText(System.IO.Path.Combine(result.BackupFolder, "items.json"), Json().Serialize(items));
            foreach (var item in items)
            {
                Progress.Enqueue("Removing reviewed leftover: " + item.Path);
                try
                {
                    // Revalidate other registrations after any preceding uninstaller/UAC dialog.
                    var currentProtection = new AppInventory(); active = Desktop(currentProtection, true);
                    if (currentProtection.Warnings.Count > 0) throw new InvalidOperationException("Shared-app protection could not be refreshed.");
                    active.AddRange(inventory.Apps.Where(a => a.Kind == "Microsoft Store"));
                    if (WaitingForRestart(item.Owner) || Registered(item.Owner, inventory)) throw new InvalidOperationException("The app is registered or waiting for a restart; cleanup was blocked.");
                    if (item.Kind == "Folder")
                    {
                        if (!SafeDirectory(item.Path, item.Owner, active) || !NoLinks(item.Path)) throw new InvalidOperationException("Folder protection changed; cleanup was blocked.");
                        RecycleFolder(item.Path);
                        result.Messages.Add(item.Path + ": sent to Recycle Bin.");
                    }
                    else if (item.Kind == "Registry")
                    {
                        if (item.ValueName == null ? !SafeRegistry(item.Path, item.Owner, active) : !SafeRegistryValue(item.Path, item.ValueName, item.Owner, active)) throw new InvalidOperationException("Registry protection changed; cleanup was blocked.");
                        string key = (item.Machine ? "HKLM\\" : "HKCU\\") + item.Path;
                        string backup = System.IO.Path.Combine(result.BackupFolder, Guid.NewGuid().ToString("N") + ".reg");
                        var export = new ProcessStartInfo(RegExe, "export \"" + key + "\" \"" + backup + "\" /y /reg:" + (item.View32 ? "32" : "64"));
                        export.UseShellExecute = false; export.CreateNoWindow = true;
                        using (var process = Process.Start(export)) { process.WaitForExit(); if (process.ExitCode != 0 || !File.Exists(backup) || new FileInfo(backup).Length < 10) throw new IOException("Registry backup failed; key was kept."); }
                        File.AppendAllText(System.IO.Path.Combine(result.BackupFolder, "RESTORE.txt"), key + " (" + (item.View32 ? "32-bit" : "64-bit") + ")\r\nTo restore from Command Prompt" + (item.Machine ? " as administrator" : "") + ":\r\nreg.exe import \"" + backup + "\" /reg:" + (item.View32 ? "32" : "64") + "\r\n\r\n");
                        var delete = new ProcessStartInfo(RegExe, "delete \"" + key + "\"" + (item.ValueName == null ? "" : " /v \"" + item.ValueName + "\"") + " /f /reg:" + (item.View32 ? "32" : "64"));
                        delete.UseShellExecute = true; delete.WindowStyle = ProcessWindowStyle.Hidden;
                        if (item.Machine) delete.Verb = "runas";
                        using (var process = Process.Start(delete)) { process.WaitForExit(); if (process.ExitCode != 0) throw new IOException("Registry removal was cancelled or failed; backup is available."); }
                        result.Messages.Add(key + (item.ValueName == null ? "" : " :: " + item.ValueName) + ": removed; .reg backup saved.");
                    }
                }
                catch (Exception e) { result.Messages.Add(item.Path + ": not completed · " + e.Message); }
            }
            return result;
        });
    }
    // Modern Shell recycling explicitly requests recycle-on-delete; no permanent-delete fallback.
    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellItem { }
    [ComImport, Guid("947AAB5F-0A5C-4C13-B4D6-4BF7836FC9F8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IFileOperation
    {
        void Advise(IntPtr sink, out uint cookie); void Unadvise(uint cookie);
        void SetOperationFlags(uint flags); void SetProgressMessage([MarshalAs(UnmanagedType.LPWStr)] string message);
        void SetProgressDialog(IntPtr dialog); void SetProperties(IntPtr properties); void SetOwnerWindow(IntPtr window);
        void ApplyPropertiesToItem(IntPtr item); void ApplyPropertiesToItems(IntPtr items);
        void RenameItem(IntPtr item, IntPtr name, IntPtr sink); void RenameItems(IntPtr items, IntPtr name);
        void MoveItem(IntPtr item, IntPtr folder, IntPtr name, IntPtr sink); void MoveItems(IntPtr items, IntPtr folder);
        void CopyItem(IntPtr item, IntPtr folder, IntPtr name, IntPtr sink); void CopyItems(IntPtr items, IntPtr folder);
        void DeleteItem(IShellItem item, IntPtr sink); void DeleteItems(IntPtr items);
        void NewItem(IntPtr folder, uint attributes, IntPtr name, IntPtr template, IntPtr sink);
        void PerformOperations(); void GetAnyOperationsAborted([MarshalAs(UnmanagedType.Bool)] out bool aborted);
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void SHCreateItemFromParsingName(string path, IntPtr binding, ref Guid iid, out IShellItem item);
    static void RecycleFolder(string path)
    {
        Exception failure = null;
        var thread = new Thread(() => {
            IShellItem item = null; IFileOperation operation = null;
            try
            {
                var iid = new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE");
                SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out item);
                operation = (IFileOperation)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("3AD05575-8857-4850-9277-11B85BDB8E09")));
                // RECYCLEONDELETE, ADDUNDORECORD, SHOWELEVATIONPROMPT, EARLYFAILURE, NOERRORUI, NOCONFIRMATION, SILENT.
                operation.SetOperationFlags(0x00080000 | 0x20000000 | 0x00040000 | 0x00100000 | 0x0400 | 0x0010 | 0x0004);
                operation.DeleteItem(item, IntPtr.Zero); operation.PerformOperations();
                bool aborted; operation.GetAnyOperationsAborted(out aborted);
                if (aborted || Directory.Exists(path)) throw new IOException("Windows could not recycle the whole folder. Check remaining files and Recycle Bin.");
            }
            catch (Exception e) { failure = e; }
            finally { if (item != null) Marshal.ReleaseComObject(item); if (operation != null) Marshal.ReleaseComObject(operation); }
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure != null) throw failure;
    }
    public static void SelfTest()
    {
        var app = new InstalledApp { Name = "Sample Editor 2.0 (x64)", Publisher = "Sample Company", Location = @"C:\Apps\Sample Editor" };
        var others = new[] { new InstalledApp { Name = "Another Editor", Publisher = "Sample Company", Location = @"C:\Apps\Sample Editor\Plugin" } };
        if (!Names(app).Contains("Sample Editor") || SafeRegistry(@"Software\Sample Company", app, others) || SafeRegistry(@"Software\Microsoft\Windows", app, others) || !SafeRegistry(@"Software\Sample Company\Sample Editor", app, others)) throw new Exception("Registry ownership regression.");
        if (SafeRegistry(@"Software\Sample Editor", app, new[] { app }) || SafeRegistry("Software\\Sample Editor\" & bad", app, new InstalledApp[0])) throw new Exception("Shared registry / command boundary regression.");
        if (Names(new InstalledApp { Name = "Adobe Example Editor", Publisher = "Adobe Inc.", Location = @"C:\Program Files\Adobe" }).Contains("Adobe")) throw new Exception("Vendor root ownership regression.");
        string traceKey = TraceKeys[2], tracePath = app.Location + @"\editor.exe";
        if (!SafeRegistryValue(traceKey, tracePath, app, new InstalledApp[0]) || SafeRegistryValue(traceKey, app.Location + @"Sibling\editor.exe", app, new InstalledApp[0]) || SafeRegistryValue(traceKey, tracePath, app, others) || SafeRegistryValue(traceKey, tracePath + "\" /f", app, new InstalledApp[0])) throw new Exception("Registry-value boundary/shared-app regression.");
        if (Rot13(Rot13(tracePath)) != tracePath || !SafeRegistryValue(TraceKeys[6], Rot13(tracePath), app, new InstalledApp[0])) throw new Exception("BCU UserAssist adaptation regression.");
        app.RestartRequestedAt = BootTime;
        if (!WaitingForRestart(app)) throw new Exception("Restart gate regression.");
        app.RestartRequestedAt = BootTime - TimeSpan.TicksPerDay; if (WaitingForRestart(app)) throw new Exception("Restart gate did not clear.");
        if (SafeDirectory(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), app, new InstalledApp[0]) || SafeDirectory(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), app, new InstalledApp[0])) throw new Exception("Protected root regression.");
        string exe = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "notepad.exe");
        app.Command = "\"" + exe + "\" /test \"quoted value\"";
        var parsed = GetCommand(app); if (parsed.FileName != exe || parsed.Arguments != "/test \"quoted value\"") throw new Exception("Quoted command regression.");
        app.Command = exe + " /test"; if (GetCommand(app).Arguments != "/test") throw new Exception("Unquoted command regression.");
        app.Msi = true; app.RegistryPath = Arp + @"\{01234567-89AB-CDEF-0123-456789ABCDEF}";
        if (GetCommand(app).Arguments != "/x {01234567-89ab-cdef-0123-456789abcdef}") throw new Exception("MSI removal command regression.");
        app.RegistryPath = Arp + "\\invalid"; bool rejected = false; try { GetCommand(app); } catch { rejected = true; } if (!rejected) throw new Exception("Invalid MSI accepted.");
        // Real filesystem boundary checks use only a new temporary fixture, never installed apps.
        string folder = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "1nstall-check-" + Guid.NewGuid().ToString("N"), "Sample Editor");
        Directory.CreateDirectory(folder);
        try
        {
            File.WriteAllText(System.IO.Path.Combine(folder, "fixture.txt"), "fixture");
            app.Location = folder;
            if (!SafeDirectory(folder, app, new InstalledApp[0]) || !NoLinks(folder)) throw new Exception("Product-folder validation failed.");
            if (SafeDirectory(folder, app, new[] { new InstalledApp { Location = folder + "\\Plugin" } })) throw new Exception("Shared install folder accepted.");
        }
        finally { Directory.Delete(System.IO.Path.GetDirectoryName(folder), true); }
    }
}
