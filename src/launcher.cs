using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Windows;
using System.Security.Cryptography;

[assembly: AssemblyTitle("1nstall")]
[assembly: AssemblyDescription("1nstall - Windows app manager")]
[assembly: AssemblyProduct("1nstall")]
[assembly: AssemblyVersion("3.5.0.0")]
[assembly: AssemblyFileVersion("3.5.0.0")]

internal static class Launcher
{
    public sealed class StartupTimer {
        readonly double offset;
        readonly Stopwatch watch;
        public StartupTimer() {
            offset=(DateTime.UtcNow-Process.GetCurrentProcess().StartTime.ToUniversalTime()).TotalMilliseconds;
            watch=Stopwatch.StartNew();
        }
        public long ElapsedMilliseconds { get { return (long)offset+watch.ElapsedMilliseconds; } }
    }
    static string ReadResource(string name) {
        using(var reader=new StreamReader(Assembly.GetExecutingAssembly().GetManifestResourceStream(name))) return reader.ReadToEnd();
    }
    static string Hash(byte[] bytes) {
        using(var sha=SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();
    }
    static string CacheAssembly(string resourceName,string fileName,bool test) {
        byte[] bytes;
        using(var resource=Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName))
        using(var buffer=new MemoryStream()) { resource.CopyTo(buffer); bytes=buffer.ToArray(); }
        string hash=Hash(bytes);
        // One immutable directory per assembly revision; old revisions can be removed
        // by a future updater when the app gains an installation lifecycle.
        string root=test?Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"runtime-cache"):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"1nstall","Runtime");
        string directory=Path.Combine(root,hash);
        Directory.CreateDirectory(directory);
        string path=Path.Combine(directory,fileName);
        if(File.Exists(path) && Hash(File.ReadAllBytes(path))==hash) return path;
        string temporary=Path.Combine(directory,Guid.NewGuid().ToString("N")+".tmp");
        try {
            File.WriteAllBytes(temporary,bytes);
            if(File.Exists(path)) File.Replace(temporary,path,null);
            else {
                try { File.Move(temporary,path); }
                catch(IOException) { if(!File.Exists(path) || Hash(File.ReadAllBytes(path))!=hash) throw; }
            }
        } finally { if(File.Exists(temporary)) File.Delete(temporary); }
        return path;
    }
    static void Invoke(PowerShell ps, StringBuilder output) {
        foreach(var item in ps.Invoke(null,new PSInvocationSettings { ApartmentState=Thread.CurrentThread.GetApartmentState() })) if(item!=null) output.AppendLine(item.ToString());
        if(ps.InvocationStateInfo.State==PSInvocationState.Failed) throw ps.InvocationStateInfo.Reason;
    }
    internal static Type WindowHelper() {
        return Assembly.LoadFrom(CacheAssembly("1nstall.Helpers","1nstall.Helpers.dll",false)).GetType("FirstInstallWindow",true);
    }
    [STAThread]
    private static int Main(string[] args)
    {
        if(args.Length>0 && args[0]=="--apply-update") {
            try {
                var assembly=Assembly.LoadFrom(CacheAssembly("1nstall.Helpers","1nstall.Helpers.dll",false));
                return (int)assembly.GetType("OneInstallUpdate").GetMethod("Apply").Invoke(null,new object[]{args});
            } catch { return 1; }
        }
        try {
            bool test=args.Length==1 && args[0].StartsWith("--",StringComparison.Ordinal);
            string root=test?Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"runtime-cache"):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"1nstall","Runtime");
            Directory.CreateDirectory(root);
            System.Runtime.ProfileOptimization.SetProfileRoot(root);
            System.Runtime.ProfileOptimization.StartProfile("startup.profile");
        } catch(IOException) { } catch(UnauthorizedAccessException) { }
        using(var opening=(args.Length==0 || args.Length==1 && args[0]=="--startup-test")?new StartupView():null) return Run(args,opening);
    }
    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
    private static int Run(string[] args,StartupView opening)
    {
        var clock=new StartupTimer();
        bool test=args.Length==1 && (args[0]=="--smoke-test" || args[0]=="--self-test" || args[0]=="--manager-test" || args[0]=="--startup-test");
        string folder=Path.Combine(Path.GetTempPath(),"1nstall-"+Guid.NewGuid().ToString("N"));
        var output=new StringBuilder();
        Task<Runspace> prepare=null;
        Runspace runspace=null;
        try {
            if(args.Length>0 && !test) throw new ArgumentException("Unknown argument.");
            Directory.CreateDirectory(folder);
            string helpersPath=CacheAssembly("1nstall.Helpers","1nstall.Helpers.dll",test);
            string uiPath=CacheAssembly("1nstall.UI","1nstall.UI.dll",test);
            string source=ReadResource("1nstall.Payload");
            int split=source.IndexOf("# UI starts here",StringComparison.Ordinal);
            if(split<0) throw new InvalidDataException("Missing application entry point.");
            string parameter=test ? (args[0]=="--smoke-test"?"SmokeTest":args[0]=="--manager-test"?"ManagerTest":args[0]=="--self-test"?"SelfTest":"StartupTest") : null;
            prepare=Task.Factory.StartNew(delegate {
                var state=InitialSessionState.CreateDefault2();
                var session=RunspaceFactory.CreateRunspace(state);
                session.ApartmentState=ApartmentState.STA;
                session.ThreadOptions=PSThreadOptions.UseCurrentThread;
                try {
                    Assembly.LoadFrom(helpersPath);
                    session.Open();
                    using(var ps=PowerShell.Create()) {
                        ps.Runspace=session; ps.AddScript(source.Substring(0,split),false).AddParameter("ResourceRoot",folder);
                        if(parameter!=null) ps.AddParameter(parameter);
                        Invoke(ps,output);
                    }
                    return session;
                } catch { session.Dispose(); throw; }
            });
            Window window=null;
            if(parameter!="SelfTest") {
                var assembly=Assembly.LoadFrom(uiPath);
                window=(Window)assembly.CreateInstance("OneInstall.MainWindow");
                if(opening!=null) {
                    window.Loaded+=delegate { if(opening.Cancelled) window.Close(); };
                    window.ContentRendered+=delegate { opening.Complete(window); };
                }
                assembly.GetType("OneInstall.NativeUI").GetMethod("Populate").Invoke(null,new object[]{window,ReadResource("1nstall.Catalog")});
            }
            runspace=prepare.GetAwaiter().GetResult();
            if(opening!=null && opening.Cancelled) return 0;
            if(window!=null) {
                runspace.SessionStateProxy.SetVariable("NativeWindow",window);
                runspace.SessionStateProxy.SetVariable("AppExecutable",Assembly.GetExecutingAssembly().Location);
                runspace.SessionStateProxy.SetVariable("StartupClock",clock);
                using(var ps=PowerShell.Create()) {
                    ps.Runspace=runspace; ps.AddScript(source.Substring(split),false); Invoke(ps,output);
                }
                if(parameter=="StartupTest") {
                    if(!(window.Tag is long)) throw new Exception("Window did not reach the ready checkpoint.");
                    output.AppendLine("READY "+window.Tag);
                    output.AppendLine("FirstFrameMs "+(opening==null?0:opening.FirstFrameMilliseconds));
                    foreach(string name in new[]{"BeforeShowMs","LoadedMs","RenderMs"}) output.AppendLine(name+" "+window.Resources[name]);
                }
            }
            if(test) File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,args[0].Substring(2)+".log"),output.ToString());
            return 0;
        }
        catch(Exception error) {
            if(opening!=null) opening.Dispose();
            string log=Path.Combine(test?AppDomain.CurrentDomain.BaseDirectory:Path.GetTempPath(),"1nstall-startup-error.log");
            try { File.WriteAllText(log,error.ToString()); } catch { }
            if(!test) MessageBox.Show("Could not start 1nstall.\n\n"+error.Message+"\n\nLog: "+log,"1nstall",MessageBoxButton.OK,MessageBoxImage.Error);
            return 1;
        }
        finally {
            if(runspace!=null) runspace.Dispose();
            else if(prepare!=null) { try { prepare.GetAwaiter().GetResult().Dispose(); } catch { } }
            try { if(Directory.Exists(folder)) Directory.Delete(folder,true); } catch { }
        }
    }
}
