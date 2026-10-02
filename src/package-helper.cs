using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

// No display-name correlation and no shell execution. DTOs are the boundary to WPF.
public sealed class PackageRecord
{
    public string Id { get; set; }
    public string Name { get; set; }
    public string Source { get; set; }
    public string InstalledVersion { get; set; }

}
public sealed class PackageInventory
{
    public bool Complete { get; set; }
    public bool Partial { get; set; }
    public List<PackageRecord> Packages = new List<PackageRecord>();
    public string Message { get; set; }
}
public sealed class ProcessResult
{
    public int ExitCode;
    public string Output;
    public string Error;
}
public sealed class OperationRecord
{
    public string Timestamp { get; set; }
    public string Action { get; set; }
    public string Id { get; set; }
    public string Source { get; set; }
    public string Name { get; set; }
    public string Outcome { get; set; }
    public string Message { get; set; }
    public string LogPath { get; set; }
    public int ExitCode { get; set; }
    public string Detail { get { return Timestamp + " · " + Action + " · " + Name + " · " + Outcome + "\r\n" + Message; } }
}
public sealed class SetupEntry
{
    public string Id { get; set; }
    public string Source { get; set; }
    public string Name { get; set; }
    public string Version { get; set; }
}
public sealed class SetupSelection
{
    public int Version { get; set; }
    public List<string> Keys = new List<string>();
    public List<SetupEntry> Apps = new List<SetupEntry>();
}
public sealed class WinGetExport
{
    public List<WinGetExportSource> Sources { get; set; }
}
public sealed class WinGetExportSource
{
    public Dictionary<string, string> SourceDetails { get; set; }
    public List<WinGetExportPackage> Packages { get; set; }
}
public sealed class WinGetExportPackage
{
    public string PackageIdentifier { get; set; }
    public string Version { get; set; }
}
public static class OneInstallPackages
{
    static readonly object HistoryGate = new object();
    static JavaScriptSerializer Json() { return new JavaScriptSerializer { MaxJsonLength = 4194304, RecursionLimit = 20 }; }
    public static string DataRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "1nstall");
    public static string WinGetPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\WindowsApps\winget.exe");
    public static string FindWinGet()
    {
        if (File.Exists(WinGetPath)) return WinGetPath;
        foreach (string entry in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';'))
        {
            try {
                if (string.IsNullOrWhiteSpace(entry)) continue;
                string candidate = Path.Combine(entry.Trim().Trim('"'), "winget.exe");
                if (File.Exists(candidate)) return candidate;
            } catch (ArgumentException) { }
        }
        return "";
    }
    public static string HistoryPath { get { return Path.Combine(DataRoot, "operations.json"); } }
    public static string HistoryError { get; private set; }
    public static bool ValidId(string id) { return id != null && id.Length <= 200 && Regex.IsMatch(id, @"^[A-Za-z0-9][A-Za-z0-9.+_-]*$"); }
    public static bool ValidSource(string source) { return source == "winget" || source == "msstore"; }
    public static bool KnownVersion(string version) { return !String.IsNullOrWhiteSpace(version) && !Regex.IsMatch(version, @"^(unknown|latest|n/a|<.*>)$", RegexOptions.IgnoreCase); }
    public static string Quote(string value)
    {
        if (value == null || value.IndexOf('\0') >= 0) throw new ArgumentException("Invalid argument.");
        var result = new StringBuilder("\""); int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { result.Append('\\', slashes * 2 + 1); result.Append(c); }
            else { result.Append('\\', slashes); result.Append(c); }
            slashes = 0;
        }
        result.Append('\\', slashes * 2); result.Append('"'); return result.ToString();
    }
    public static string Arguments(string id, string source)
    {
        if (!ValidId(id) || !ValidSource(source)) throw new ArgumentException("Invalid package identity.");
        return "install --id " + Quote(id) + " --exact --source " + Quote(source) +
            " --no-upgrade --accept-source-agreements --accept-package-agreements --disable-interactivity";
    }
    public static ProcessResult Run(string exe, string arguments, int timeout)
    {
        var start = new ProcessStartInfo(exe, arguments) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
        using (var p = Process.Start(start))
        {
            if (p == null) throw new IOException("Could not start the package service.");
            var output = p.StandardOutput.ReadToEndAsync(); var error = p.StandardError.ReadToEndAsync();
            if (timeout > 0 && !p.WaitForExit(timeout)) { p.Kill(); p.WaitForExit(); throw new TimeoutException("The package service timed out. Check connectivity and refresh."); }
            p.WaitForExit();
            string o = output.Result, e = error.Result;
            return new ProcessResult { ExitCode = p.ExitCode, Output = o.Length > 1048576 ? o.Substring(0, 1048576) + "\n[truncated]" : o, Error = e.Length > 1048576 ? e.Substring(0, 1048576) + "\n[truncated]" : e };
        }
    }
    static string Shell7
    {
        get
        {
            string candidate = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"PowerShell\7\pwsh.exe");
            if (!File.Exists(candidate)) throw new InvalidOperationException("Installed status requires PowerShell 7 and Microsoft's Microsoft.WinGet.Client module. Install them yourself; 1nstall never installs prerequisites automatically. Automatic catalog installation remains available with WinGet.");
            return candidate;
        }
    }
    static string Structured(string script)
    {
        string code = "$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new(); Import-Module Microsoft.WinGet.Client -MinimumVersion 1.7.0 -ErrorAction Stop; " + script;
        var r = Run(Shell7, "-NoLogo -NoProfile -NonInteractive -EncodedCommand " + Convert.ToBase64String(Encoding.Unicode.GetBytes(code)), 90000);
        if (r.ExitCode != 0) throw new IOException("WinGet inventory unavailable. Check the Microsoft.WinGet.Client module and connectivity. " + r.Error.Trim());
        return r.Output.Trim().TrimStart('\uFEFF');
    }
    public static PackageInventory Inventory()
    {
        var result = new PackageInventory();
        try
        {
            string payload = Structured("$rows=@(Get-WinGetPackage -ErrorAction Stop | ForEach-Object { [pscustomobject]@{Id=[string]$_.Id;Name=[string]$_.Name;Source=[string]$_.Source;InstalledVersion=[string]$_.InstalledVersion} }); ConvertTo-Json -InputObject $rows -Depth 4 -Compress");
            result.Packages = Json().Deserialize<List<PackageRecord>>(payload) ?? new List<PackageRecord>();
            if (result.Packages.Any(p => p.Id == null || p.Name == null)) throw new IOException("Unexpected structured inventory shape.");
            result.Complete = true;
            result.Message = "Inventory refreshed. WinGet reports aggregate installed versions; installation scopes are not exposed by this interface. Guided and uncorrelated apps remain Unknown.";
        }
        catch (Exception e)
        {
            result.Message = e.Message;
                string temp = Path.Combine(Path.GetTempPath(), "1nstall-inventory-" + Guid.NewGuid().ToString("N") + ".json");
                try
                {
                    var export = Run(WinGetPath, "export --output " + Quote(temp) + " --include-versions --disable-interactivity", 90000);
                    if (export.ExitCode != 0 || !File.Exists(temp) || new FileInfo(temp).Length > 4194304) throw new IOException("WinGet export unavailable; check sources, source agreements and connectivity.");
                    var partial = ParseExport(File.ReadAllText(temp));
                    partial.Message = "Partial identity inventory from WinGet export. Included apps can be confirmed; omitted apps remain Unknown. " + e.Message;
                    return partial;
                }
                catch (Exception fallback) { result.Message += " " + fallback.Message; }
                finally { try { if (File.Exists(temp)) File.Delete(temp); } catch { } }
        }
        return result;
    }
    public static Task<PackageInventory> InventoryAsync() { return Task.Run(() => Inventory()); }
    public static PackageInventory ParseExport(string json)
    {
        var data = Json().Deserialize<WinGetExport>(json);
        if (data == null || data.Sources == null) throw new IOException("Unexpected WinGet export schema.");
        var result = new PackageInventory { Partial = true };
        foreach (var source in data.Sources)
        {
            string name;
            if (source.SourceDetails == null || !source.SourceDetails.TryGetValue("Name", out name) || source.Packages == null) throw new IOException("Incomplete WinGet export schema.");
            if (!ValidSource(name)) continue;
            foreach (var package in source.Packages)
            {
                if (!ValidId(package.PackageIdentifier)) throw new IOException("Invalid exported identity.");
                result.Packages.Add(new PackageRecord { Id = package.PackageIdentifier, Name = package.PackageIdentifier, Source = name, InstalledVersion = package.Version });
            }
        }
        return result;
    }
    public static string InstalledState(PackageInventory inventory, string[] ids, string source)
    {
        if (ids == null || ids.Length == 0 || (!inventory.Complete && !inventory.Partial)) return "Unknown";
        bool absent = false; var versions = new List<string>();
        foreach (string id in ids)
        {
            var matches = inventory.Packages.Where(p => String.Equals(p.Id, id, StringComparison.OrdinalIgnoreCase) && p.Source == source).ToArray();
            if (matches.Length > 1) return "Unknown · multiple registrations";
            if (matches.Length == 0) absent = true;
            else versions.Add(KnownVersion(matches[0].InstalledVersion) ? matches[0].InstalledVersion : "version unknown");
        }
        if (absent) return inventory.Complete && versions.Count == 0 ? "Not installed" : "Unknown · omitted or partially installed";
        return "Installed · " + String.Join(" / ", versions);
    }
    public static string Outcome(int code)
    {
        uint h = unchecked((uint)code);
        if (code == 3010 || code == 1641 || h == 0x8A150109 || h == 0x8A15010A || h == 0x8A15010B) return "Restart required";
        if (code == 1602 || code == 1223 || h == 0x800704C7 || h == 0x8A150005 || h == 0x8A15010C || h == 0x8A150077) return "Cancelled";
        if (code == 0 || h == 0x8A150061 || h == 0x8A15010D) return "Unknown"; // verify, never equate exit success with state
        if (h == 0x8A150076 || h == 0x8A150041 || h == 0x8A150046) return "Manual action required";
        return "Failed";
    }
    public static string Explain(int code)
    {
        uint h = unchecked((uint)code);
        if (h == 0x8A150008 || h == 0x8A150107) return "Download/network failure. Check connectivity and retry after refreshing.";
        if (h == 0x8A150068) return "WinGet pin prevents this operation. Review the pin in WinGet; 1nstall will not override it.";
        if (h == 0x8A150104 || h == 0x8A150110) return "Dependency failed. Complete its installation before retrying.";
        return "Process returned " + code + " / 0x" + h.ToString("X8") + ". Review detailed logs and publisher instructions.";
    }
    public static OperationRecord Record(string action, string id, string source, string name, string outcome, string message, int code, string log)
    {
        var r = new OperationRecord { Timestamp = DateTimeOffset.Now.ToString("o"), Action = action, Id = id, Source = source, Name = name, Outcome = outcome, Message = message, ExitCode = code, LogPath = log };
        try
        {
            lock (HistoryGate)
            {
                var rows = History();
                if (HistoryError != null) throw new IOException(HistoryError + " Existing history was preserved.");
                rows.Add(r); Directory.CreateDirectory(DataRoot);
                string temp = HistoryPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
                File.WriteAllText(temp, Json().Serialize(rows.Skip(Math.Max(0, rows.Count - 500)).ToList()), Encoding.UTF8);
                if (File.Exists(HistoryPath)) File.Replace(temp, HistoryPath, null); else File.Move(temp, HistoryPath);
            }
        }
        catch (Exception e) { r.Message += " History could not be saved: " + e.Message; }
        return r;
    }
    public static List<OperationRecord> History()
    {
        lock (HistoryGate)
        {
            HistoryError = null;
            try
            {
                if (!File.Exists(HistoryPath)) return new List<OperationRecord>();
                if (new FileInfo(HistoryPath).Length > 4194304) throw new IOException("Operation history exceeds its limit.");
                var rows = Json().Deserialize<List<OperationRecord>>(File.ReadAllText(HistoryPath));
                if (rows == null || rows.Any(r => r == null || String.IsNullOrWhiteSpace(r.Timestamp) || String.IsNullOrWhiteSpace(r.Action) || String.IsNullOrWhiteSpace(r.Outcome))) throw new IOException("Invalid operation history records.");
                return rows;
            }
            catch (Exception e) { HistoryError = "Operation history unavailable: " + e.Message; return new List<OperationRecord>(); }
        }
    }
    public static OperationRecord Install(string exe, string id, string source, string name, string logs)
    {
        string log = null;
        try
        {
            Directory.CreateDirectory(logs); log = Path.Combine(logs, Guid.NewGuid().ToString("N") + ".log");
            var r = Run(exe, Arguments(id, source), 0);
            File.WriteAllText(log, r.Output + "\r\n" + r.Error, Encoding.UTF8);
            string outcome = Outcome(r.ExitCode), message = Explain(r.ExitCode);
            if (outcome == "Unknown")
            {
                var inventory = Inventory(); string state = InstalledState(inventory, new[] { id }, source);
                if (state.StartsWith("Installed ·")) { outcome = "Success"; message = "Exact package identity verified: " + state; }
                else message = "Installer finished; resulting state could not be confirmed. " + state + ". " + inventory.Message;
            }
            return Record("Install", id, source, name, outcome, message, r.ExitCode, log);
        }
        catch (Exception e) { return Record("Install", id, source, name, "Failed", e.Message, -1, log); }
    }
    public static string Redact(string text)
    {
        text = text ?? "";
        text = Regex.Replace(text, @"(?i)(?:[A-Z]:\\|\\\\)[^\r\n""<>]+", "<path>");
        text = Regex.Replace(text, @"(?:/Users/|/home/)[^\s""<>]+", "<path>");
        text = Regex.Replace(text, @"(?i)\b(token|password|passwd|secret|authorization|api[_-]?key|credential)\s*[:=]\s*[^\r\n,;]+", "$1=<redacted>");
        text = Regex.Replace(text, @"(?i)\bBearer\s+\S+", "Bearer <redacted>");
        text = Regex.Replace(text, @"(?i)(https?://)[^\s/@]+:[^\s/@]+@", "$1<credentials>@");
        text = Regex.Replace(text, @"(?i)(https?://[^\s?]+)\?[^\s]+", "$1?<redacted>");
        text = Regex.Replace(text, @"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b", "<email>");
        return text;
    }
    public static string Diagnostics()
    {
        return Redact("1nstall diagnostics (review before sharing)\r\nWindows " + Environment.OSVersion.Version + " · x64 " + Environment.Is64BitOperatingSystem + "\r\n" + String.Join("\r\n", History().TakeLastCompat(100).Select(r => r.Timestamp + " · " + r.Action + " · " + r.Id + " · " + r.Source + " · " + r.Outcome + " · " + r.ExitCode + "\r\n" + r.Message)));
    }
    public static SetupSelection ReadSetup(string file)
    {
        if (new FileInfo(file).Length > 65536) throw new IOException("Setup file exceeds 64 KiB.");
        return ParseSetup(File.ReadAllText(file));
    }
    public static SetupSelection ParseSetup(string text)
    {
        if (Encoding.UTF8.GetByteCount(text) > 65536) throw new IOException("Setup file exceeds 64 KiB.");
        var root = Json().DeserializeObject(text) as Dictionary<string, object>;
        if (root == null || !root.ContainsKey("Version") || !(root["Version"] is int) || !root.ContainsKey("Apps")) throw new IOException("Invalid setup schema.");
        int version = (int)root["Version"];
        if (version != 1 && version != 2) throw new IOException("Unsupported setup version.");
        if (root.Keys.Any(k => k != "Version" && k != "Apps" && !(version == 2 && k == "Kind"))) throw new IOException("Unsupported setup fields. Commands and executable content are not allowed.");
        if (version == 2 && (!root.ContainsKey("Kind") || Convert.ToString(root["Kind"]) != "1nstall-selection")) throw new IOException("Invalid setup kind.");
        var items = root["Apps"] as object[];
        if (items == null || items.Length == 0 || items.Length > 500) throw new IOException("Setup must contain 1–500 app selections.");
        var result = new SetupSelection { Version = version }; var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (object item in items)
        {
            if (version == 1)
            {
                var key = item as string;
                if (!ValidId(key) || !seen.Add(key)) throw new IOException("Invalid or duplicate catalog key.");
                result.Keys.Add(key);
            }
            else
            {
                var fields = item as Dictionary<string, object>;
                if (fields == null || fields.Keys.Any(k => k != "Id" && k != "Source" && k != "Name" && k != "Version") || !fields.ContainsKey("Id") || !fields.ContainsKey("Source") || !fields.ContainsKey("Name") || !fields.ContainsKey("Version") || fields.Values.Any(v => !(v is string))) throw new IOException("Invalid app fields. Executable content is not allowed.");
                var entry = new SetupEntry { Id = (string)fields["Id"], Source = (string)fields["Source"], Name = (string)fields["Name"], Version = (string)fields["Version"] };
                if (!ValidId(entry.Id) || !ValidSource(entry.Source) || entry.Name.Length > 200 || entry.Version.Length > 100 || Regex.IsMatch(entry.Name + entry.Version, @"[\x00-\x1f]") || !seen.Add(entry.Source + ":" + entry.Id)) throw new IOException("Invalid or duplicate package identity.");
                result.Apps.Add(entry);
            }
        }
        return result;
    }
    public static void SaveSetup(string path, SetupEntry[] entries)
    {
        foreach (var entry in entries) { if (entry.Version == null) entry.Version = "Unknown"; if (String.IsNullOrWhiteSpace(entry.Name)) entry.Name = entry.Id; }
        string json = Json().Serialize(new { Version = 2, Kind = "1nstall-selection", Apps = entries });
        if (Encoding.UTF8.GetByteCount(json) > 65536) throw new IOException("Selection exceeds 64 KiB.");
        ParseSetup(json); // apply the same schema validation before writing an export
        File.WriteAllText(path, json, Encoding.UTF8);
    }
    static IEnumerable<T> TakeLastCompat<T>(this IEnumerable<T> rows, int count) { var all = rows.ToList(); return all.Skip(Math.Max(0, all.Count - count)); }
}
