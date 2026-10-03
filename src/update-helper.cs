using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

public sealed class OneInstallRelease {
    public string Version;
    public string Path;
    public string Hash;
    public string Error;
}

public static class OneInstallUpdate {
    const string Repository = "https://github.com/braga1k/1nstall/releases/download/";
    public static string HashFile(string path) {
        using(var hash=SHA256.Create()) using(var input=File.OpenRead(path))
            return BitConverter.ToString(hash.ComputeHash(input)).Replace("-","").ToLowerInvariant();
    }
    static byte[] Download(string url, int limit) {
        var request=(HttpWebRequest)WebRequest.Create(url);
        request.UserAgent="1nstall-updater"; request.Accept="application/vnd.github+json";
        request.Timeout=20000; request.ReadWriteTimeout=20000;
        using(var response=(HttpWebResponse)request.GetResponse()) {
            if(response.ResponseUri.Scheme!="https") throw new IOException("HTTPS required.");
            if(response.ContentLength>limit) throw new IOException("Download too large.");
            using(var input=response.GetResponseStream()) using(var output=new MemoryStream()) {
                var buffer=new byte[65536]; int count;
                while((count=input.Read(buffer,0,buffer.Length))>0) {
                    if(output.Length+count>limit) throw new IOException("Download too large.");
                    output.Write(buffer,0,count);
                }
                return output.ToArray();
            }
        }
    }
    public static bool IsNewer(string tag,string current) {
        Version next,installed;
        return Regex.IsMatch(tag??"",@"^v?\d+\.\d+\.\d+$") &&
            Version.TryParse(tag.TrimStart('v'),out next) && Version.TryParse(current,out installed) &&
            next>new Version(installed.Major,installed.Minor,Math.Max(0,installed.Build));
    }
    static string AssetUrl(Dictionary<string,object> asset,string tag) {
        string url=Convert.ToString(asset["browser_download_url"]);
        if(!url.StartsWith(Repository+Uri.EscapeDataString(tag)+"/",StringComparison.Ordinal))
            throw new IOException("Unexpected release asset URL.");
        return url;
    }
    public static Task<OneInstallRelease> CheckAsync(string current,string root,bool download) {
        return Task.Run(delegate {
            var result=new OneInstallRelease(); string temporary=null;
            try {
                ServicePointManager.SecurityProtocol|=SecurityProtocolType.Tls12;
                var json=new JavaScriptSerializer { MaxJsonLength=1048576 };
                var release=(Dictionary<string,object>)json.DeserializeObject(Encoding.UTF8.GetString(Download("https://api.github.com/repos/braga1k/1nstall/releases/latest",1048576)));
                string tag=Convert.ToString(release["tag_name"]);
                if((bool)release["draft"] || (bool)release["prerelease"] || !IsNewer(tag,current)) return result;
                Dictionary<string,object> executable=null,checksums=null;
                foreach(Dictionary<string,object> asset in (object[])release["assets"]) {
                    if(Convert.ToString(asset["name"])=="1nstall.exe") executable=asset;
                    if(Convert.ToString(asset["name"])=="SHA256SUMS.txt") checksums=asset;
                }
                if(executable==null) throw new IOException("Missing release executable.");
                result.Version=tag.TrimStart('v');
                if(!download) return result;
                string digest=executable.ContainsKey("digest")?Convert.ToString(executable["digest"]):"";
                if(Regex.IsMatch(digest,@"^sha256:[a-fA-F0-9]{64}$")) result.Hash=digest.Substring(7).ToLowerInvariant();
                else {
                    if(checksums==null) throw new IOException("Missing release checksum.");
                    string sums=Encoding.UTF8.GetString(Download(AssetUrl(checksums,tag),65536));
                    var match=Regex.Match(sums,@"(?m)^([a-fA-F0-9]{64})[ \t]+\*?1nstall\.exe\r?$");
                    if(!match.Success) throw new IOException("Missing executable checksum.");
                    result.Hash=match.Groups[1].Value.ToLowerInvariant();
                }
                string folder=System.IO.Path.Combine(root,result.Version); Directory.CreateDirectory(folder);
                string path=System.IO.Path.Combine(folder,"1nstall.exe");
                if(!File.Exists(path) || HashFile(path)!=result.Hash) {
                    temporary=path+"."+Guid.NewGuid().ToString("N")+".tmp";
                    File.WriteAllBytes(temporary,Download(AssetUrl(executable,tag),100*1024*1024));
                    if(HashFile(temporary)!=result.Hash) throw new IOException("Checksum mismatch.");
                    if(File.Exists(path)) File.Replace(temporary,path,null); else File.Move(temporary,path);
                }
                var identity=AssemblyName.GetAssemblyName(path);
                if(identity.Name!="1nstall" || new Version(identity.Version.Major,identity.Version.Minor,identity.Version.Build)!=new Version(result.Version)) throw new IOException("Release executable version mismatch.");
                result.Path=path;
            } catch(Exception error) { result.Path=null; result.Error=error.Message; }
            finally { try { if(temporary!=null && File.Exists(temporary)) File.Delete(temporary); } catch(IOException) { } catch(UnauthorizedAccessException) { } }
            return result;
        });
    }
    public static void ReplaceVerified(string source,string target,string expected,string original) {
        if(HashFile(source)!=expected || HashFile(target)!=original) throw new IOException("Update integrity check failed.");
        string pending=target+"."+Guid.NewGuid().ToString("N")+".update";
        try {
            File.Copy(source,pending,false);
            if(HashFile(pending)!=expected) throw new IOException("Copied update failed verification.");
            File.Replace(pending,target,target+".previous",true);
        } finally { if(File.Exists(pending)) File.Delete(pending); }
    }
    static string Encode(string value) { return Convert.ToBase64String(Encoding.UTF8.GetBytes(value)); }
    static string Decode(string value) { return Encoding.UTF8.GetString(Convert.FromBase64String(value)); }
    public static void Schedule(OneInstallRelease release,string target,bool restart) {
        if(release==null || String.IsNullOrEmpty(release.Path) || HashFile(release.Path)!=release.Hash) throw new IOException("No verified update is ready.");
        string worker=System.IO.Path.Combine(System.IO.Path.GetDirectoryName(release.Path),"apply-"+Guid.NewGuid().ToString("N")+".exe");
        File.Copy(target,worker,false);
        var start=new ProcessStartInfo(worker,"--apply-update "+Process.GetCurrentProcess().Id+" "+Encode(target)+" "+Encode(release.Path)+" "+release.Hash+" "+HashFile(target)+" "+(restart?"1":"0"));
        start.UseShellExecute=false; start.CreateNoWindow=true; start.WindowStyle=ProcessWindowStyle.Hidden;
        Process.Start(start);
    }
    public static int Apply(string[] args) {
        string target=null;
        try {
            if(args.Length!=7) throw new ArgumentException("Invalid update arguments.");
            target=System.IO.Path.GetFullPath(Decode(args[2]));
            string source=System.IO.Path.GetFullPath(Decode(args[3]));
            string root=System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"1nstall","Updates")+System.IO.Path.DirectorySeparatorChar;
            if(!source.StartsWith(root,StringComparison.OrdinalIgnoreCase) || !Regex.IsMatch(args[4],"^[a-f0-9]{64}$") || !Regex.IsMatch(args[5],"^[a-f0-9]{64}$") || HashFile(Process.GetCurrentProcess().MainModule.FileName)!=args[5]) throw new IOException("Unexpected update source.");
            try { using(var parent=Process.GetProcessById(Int32.Parse(args[1]))) { if(!parent.WaitForExit(60000)) return 1; } } catch(ArgumentException) { }
            for(int attempt=0;;attempt++) {
                try { ReplaceVerified(source,target,args[4],args[5]); break; }
                catch(IOException) { if(attempt==9) throw; Thread.Sleep(1000); }
            }
            string errorLog=System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"1nstall","update-error.log");
            try { if(File.Exists(errorLog)) File.Delete(errorLog); } catch(IOException) { } catch(UnauthorizedAccessException) { }
            if(args[6]=="1") Process.Start(new ProcessStartInfo(target) { UseShellExecute=true });
            return 0;
        } catch(Exception error) {
            try { File.WriteAllText(System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"1nstall","update-error.log"),error.ToString()); } catch { }
            return 1;
        }
    }
}
