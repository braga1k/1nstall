// 1nstall 4.0: the WPF interface of 3.6, hosted by plain C# with no PowerShell,
// over the Rust engine. This file is the entry point, the test modes and the error path.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows;

[assembly: AssemblyTitle("1nstall")]
[assembly: AssemblyDescription("1nstall - Windows app manager")]
[assembly: AssemblyProduct("1nstall")]
// The 3.6 updater accepts a release only if this assembly is named "1nstall" and its
// version equals the release tag (update-helper.cs, "Release executable version mismatch").
[assembly: AssemblyVersion("4.0.0.0")]
[assembly: AssemblyFileVersion("4.0.0.0")]

// Milliseconds since Windows created the process, as the 3.6 launcher counts them.
sealed class StartupTimer {
    readonly double offset;
    readonly Stopwatch watch;
    public StartupTimer() {
        offset=(DateTime.UtcNow-Process.GetCurrentProcess().StartTime.ToUniversalTime()).TotalMilliseconds;
        watch=Stopwatch.StartNew();
    }
    public long ElapsedMilliseconds { get { return (long)offset+watch.ElapsedMilliseconds; } }
}

static class Program {
    static readonly string[] Tests={"--self-test","--startup-test"};

    // Test modes keep everything beside the executable; a normal start uses the user's profile.
    public static string RuntimeRoot(bool test) {
        return test?Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"runtime-cache"):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"1nstall","Runtime");
    }

    static void Check(StringBuilder log,ref bool passed,string name,bool condition) {
        log.AppendLine((condition?"PASS ":"FAIL ")+name); if(!condition) passed=false;
    }

    // Exercises the engine through the same boundary the interface uses. Shows no window.
    static bool SelfTest(StringBuilder log) {
        bool passed=true;
        var json=new JavaScriptSerializer { MaxJsonLength=16*1024*1024 };
        string version=Engine.Version();
        Check(log,ref passed,"engine version "+version,version.StartsWith("4.",StringComparison.Ordinal));
        var catalog=(object[])json.DeserializeObject(Engine.Catalog());
        Check(log,ref passed,"catalog has "+catalog.Length+" apps",catalog.Length>300);
        Check(log,ref passed,"profiles parse",((object[])json.DeserializeObject(Engine.Profiles())).Length>0);
        var locales=(Dictionary<string,object>)json.DeserializeObject(Engine.Locales());
        Check(log,ref passed,"locales has "+locales.Count+" languages",locales.ContainsKey("en") && locales.ContainsKey("pt-PT"));
        var plan=(Dictionary<string,object>)json.DeserializeObject(Engine.Plan("[\"peace\"]"));
        var order=new List<string>();
        foreach(Dictionary<string,object> row in (IEnumerable)plan["Rows"]) order.Add((string)row["Key"]);
        Check(log,ref passed,"plan installs a dependency first: "+String.Join(", ",order),order.Count==2 && order[0]=="apo" && order[1]=="peace");
        var unknown=(Dictionary<string,object>)json.DeserializeObject(Engine.Plan("[\"no-such-app\"]"));
        Check(log,ref passed,"plan refuses an unknown app",unknown["Error"] is string);
        var identity=Assembly.GetExecutingAssembly().GetName();
        Check(log,ref passed,"assembly identity "+identity.Name+" "+identity.Version,identity.Name=="1nstall" && identity.Version.Major==4);
        return passed;
    }

    [STAThread]
    static int Main(string[] args) {
        if(args.Length>0 && args[0]=="--apply-update") {
            try { return OneInstallUpdate.Apply(args); } catch { return 1; }
        }
        var clock=new StartupTimer();
        bool test=args.Length==1 && Array.IndexOf(Tests,args[0])>=0;
        try {
            if(args.Length>0 && !test) throw new ArgumentException("Unknown argument.");
            try {
                string root=RuntimeRoot(test);
                Directory.CreateDirectory(root);
                System.Runtime.ProfileOptimization.SetProfileRoot(root);
                System.Runtime.ProfileOptimization.StartProfile("startup.profile");
            } catch(IOException) { } catch(UnauthorizedAccessException) { }
            Engine.Load(test);
            var output=new StringBuilder();
            bool passed=true;
            if(test && args[0]=="--self-test") passed=SelfTest(output);
            else Shell.Run(test,clock,output);
            if(test) File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,args[0].Substring(2)+".log"),output.ToString());
            return passed?0:1;
        }
        catch(Exception error) {
            string log=Path.Combine(test?AppDomain.CurrentDomain.BaseDirectory:Path.GetTempPath(),"1nstall-startup-error.log");
            try { File.WriteAllText(log,error.ToString()); } catch { }
            if(!test) MessageBox.Show("Could not start 1nstall.\n\n"+error.Message+"\n\nLog: "+log,"1nstall",MessageBoxButton.OK,MessageBoxImage.Error);
            return 1;
        }
    }
}
