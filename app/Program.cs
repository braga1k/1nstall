// 1nstall 4.0: the WPF interface of 3.6, hosted by plain C# with no PowerShell,
// over the Rust engine. This file is the entry point, the test modes and the error path.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
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
    // --ui-test is the normal window with the fixed preferences of the test modes: nothing in
    // the user's profile is read or written, so interface tests can drive it freely. Installing
    // is refused there, unless ONEINSTALL_TEST_WINGET names a stand-in program to run instead.
    static readonly string[] Tests={"--self-test","--startup-test","--ui-test"};
    public const string Version="4.0.0";
    static StartupTimer timer;
    static readonly StringBuilder marks=new StringBuilder();

    // One line per start-up step, written to startup-test.log after the 3.6 marks.
    public static void Mark(string step) {
        if(timer!=null) marks.AppendLine("Mark "+step+" "+timer.ElapsedMilliseconds+" ms, heap "+(GC.GetTotalMemory(false)>>20)+" MB, working set "+(Environment.WorkingSet>>20)+" MB");
    }

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
        var cards=OneInstall.CatalogCard.Parse(Engine.Cards());
        Check(log,ref passed,"card records match the catalog: "+cards.Length,cards.Length==catalog.Length);
        var order=new List<string>();
        foreach(string record in Engine.Plan("peace").Split('\u001E')) order.Add(record.Split('\u001F')[0]);
        Check(log,ref passed,"plan installs a dependency first: "+String.Join(", ",order),order.Count==2 && order[0]=="apo" && order[1]=="peace");
        Check(log,ref passed,"plan refuses an unknown app",Engine.Plan("no-such-app").StartsWith("!",StringComparison.Ordinal));
        Check(log,ref passed,"an empty selection plans nothing",Engine.Plan("").Length==0);
        Check(log,ref passed,"selecting an app brings what it requires",Engine.SelectionAdd("","peace")=="apo\u001Fpeace");
        Check(log,ref passed,"removing a requirement drops what needed it",Engine.SelectionRemove("apo\u001Fpeace","apo").Length==0);
        Check(log,ref passed,"details name the dependency",Engine.Details("peace").Contains("Dependencies\u001FEqualizer APO"));
        Check(log,ref passed,"states cover every app before any inventory",Engine.States().Split('\u001E').Length==catalog.Length);
        Check(log,ref passed,"built-in profiles are listed",Engine.ProfilesMenu().Split('\u001E').Length==((object[])json.DeserializeObject(Engine.Profiles())).Length);
        Check(log,ref passed,"the test modes use the default library view",Engine.LibraryView(true)=="All apps");
        Check(log,ref passed,"the test modes refuse to install",Engine.QueueStart("extra_7zip",Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"test-logs")).StartsWith("!",StringComparison.Ordinal));
        Check(log,ref passed,"an idle queue reports nothing",Engine.QueueEvents().Length==0);
        Check(log,ref passed,"test preferences are fixed: "+Engine.Settings(true).Replace('\u001F',' '),Engine.Settings(true)=="Dark\u001F1\u001Fen\u001F0");
        Check(log,ref passed,"every language is listed",Engine.Languages().Split('\u001E').Length==locales.Count);
        I18n.Load(Engine.Language("System","pt-BR"));
        Check(log,ref passed,"a Portuguese system resolves to "+I18n.Language+" and translates",I18n.Language=="pt-PT" && I18n.Convert("Install")=="Instalar" && I18n.Convert("3 apps selected")=="3 apps selecionadas");
        I18n.Load(Engine.Language("ar","en-US"));
        Check(log,ref passed,"Arabic is right-to-left",I18n.Rtl && I18n.Language=="ar");
        I18n.Load(Engine.Language("System","af-ZA"));
        Check(log,ref passed,"an unsupported system language falls back to English",I18n.Language=="en" && I18n.Convert("Install")=="Install");
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
            var output=new StringBuilder();
            bool passed=true;
            // Every test mode keeps the operation history beside the executable and never runs WinGet to install.
            Action isolate=delegate {
                if(!test) return;
                string standIn=args[0]=="--ui-test"?Environment.GetEnvironmentVariable("ONEINSTALL_TEST_WINGET") ?? "":"";
                Engine.TestEnvironment(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"test-data"),standIn);
            };
            if(test && args[0]=="--self-test") { Engine.Load(test); isolate(); passed=SelfTest(output); }
            else {
                string mode=test?args[0]:"";
                if(mode=="--startup-test") { timer=clock; Mark("main"); }
                // The engine is loaded and the catalog read on another thread while WPF starts on this one.
                var loading=Task.Factory.StartNew(delegate {
                    Engine.Load(test); isolate();
                    var data=new StartupData { Cards=OneInstall.CatalogCard.Parse(Engine.Cards()), Settings=Engine.Settings(test), View=Engine.LibraryView(test) };
                    data.Language=Engine.Language(data.Settings.Split('\u001F')[2],I18n.UiCulture);
                    return data;
                });
                Shell.Run(mode,clock,output,loading);
            }
            if(marks.Length>0) { using(var process=Process.GetCurrentProcess()) marks.AppendLine("Mark peak working set "+(process.PeakWorkingSet64>>20)+" MB"); output.Append(marks); }
            if(test && output.Length>0) File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,args[0].Substring(2)+".log"),output.ToString());
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
