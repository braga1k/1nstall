// The Rust engine, embedded in this executable as a resource and loaded from an immutable cache.
using System;
using System.ComponentModel;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

static class Engine {
    const string Library="oneinstall_engine.dll";
    [DllImport("kernel32",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr LoadLibraryW(string path);
    [DllImport(Library)] static extern IntPtr oi_version();
    [DllImport(Library)] static extern IntPtr oi_catalog();
    [DllImport(Library)] static extern IntPtr oi_profiles();
    [DllImport(Library)] static extern IntPtr oi_locales();
    [DllImport(Library)] static extern IntPtr oi_cards();
    [DllImport(Library,CharSet=CharSet.Unicode)] static extern IntPtr oi_plan(string keys);
    [DllImport(Library)] static extern IntPtr oi_settings(int test);
    [DllImport(Library,CharSet=CharSet.Unicode)] static extern IntPtr oi_save_settings(string record);
    [DllImport(Library)] static extern IntPtr oi_languages();
    [DllImport(Library,CharSet=CharSet.Unicode)] static extern IntPtr oi_language(string choice,string uiCulture);
    [DllImport(Library)] static extern IntPtr oi_system_appearance();
    [DllImport(Library,CharSet=CharSet.Unicode)] static extern IntPtr oi_selection_add(string selected,string key);
    [DllImport(Library,CharSet=CharSet.Unicode)] static extern IntPtr oi_selection_remove(string selected,string key);
    [DllImport(Library)] static extern IntPtr oi_refresh_inventory();
    [DllImport(Library)] static extern IntPtr oi_states();
    [DllImport(Library,CharSet=CharSet.Unicode)] static extern IntPtr oi_details(string key);
    [DllImport(Library)] static extern IntPtr oi_profiles_menu();
    [DllImport(Library)] static extern IntPtr oi_winget();
    [DllImport(Library)] static extern IntPtr oi_library_view(int test);
    [DllImport(Library,CharSet=CharSet.Unicode)] static extern IntPtr oi_save_library_view(string view);
    [DllImport(Library,CharSet=CharSet.Unicode)] static extern IntPtr oi_save_selection(string path,string keys);
    [DllImport(Library,CharSet=CharSet.Unicode)] static extern IntPtr oi_read_setup(string path);
    [DllImport(Library)] static extern IntPtr oi_snapshot_rows();
    [DllImport(Library,CharSet=CharSet.Unicode)] static extern IntPtr oi_save_snapshot(string path,string keys);
    [DllImport(Library,CharSet=CharSet.Unicode)] static extern void oi_test_environment(string dataRoot,string installProgram);
    [DllImport(Library,CharSet=CharSet.Unicode)] static extern IntPtr oi_queue_start(string keys,string logs);
    [DllImport(Library)] static extern void oi_queue_stop();
    [DllImport(Library)] static extern IntPtr oi_queue_events();
    [DllImport(Library,CharSet=CharSet.Unicode)] static extern IntPtr oi_uninstall_start(string operation,string arguments,string log);
    [DllImport(Library)] static extern void oi_uninstall_stop();
    [DllImport(Library)] static extern IntPtr oi_uninstall_events();
    [DllImport(Library)] static extern int oi_uninstall_targets();
    [DllImport(Library)] static extern void oi_free(IntPtr text);

    static string Take(IntPtr text) { try { return Marshal.PtrToStringUni(text); } finally { oi_free(text); } }
    public static string Version() { return Take(oi_version()); }
    public static string Catalog() { return Take(oi_catalog()); }
    public static string Profiles() { return Take(oi_profiles()); }
    public static string Locales() { return Take(oi_locales()); }
    // Records: fields end with U+001F, records with U+001E, list items with U+001D.
    public static string Cards() { return Take(oi_cards()); }
    // Keys separated by U+001F in; one record per planned app out, or "!" and a reason.
    public static string Plan(string keys) { return Take(oi_plan(keys)); }
    // One record: theme, Windows accent, language, automatic updates. Test modes read no file.
    public static string Settings(bool test) { return Take(oi_settings(test?1:0)); }
    // Empty when saved, or "!" and a reason.
    public static string SaveSettings(string record) { return Take(oi_save_settings(record)); }
    // One record per language: code, own name, right-to-left.
    public static string Languages() { return Take(oi_languages()); }
    // First record: resolved code and direction. Then one record per English text and its translation.
    public static string Language(string choice,string uiCulture) { return Take(oi_language(choice,uiCulture)); }
    // One record: accent "RRGGBB", transparency effects, light app theme. Call on the interface thread.
    public static string SystemAppearance() { return Take(oi_system_appearance()); }
    // The library. Keys travel separated by U+001F; a refusal comes back as "!" and a reason.
    // See engine/ffi/src/library.rs for the records each call returns.
    public static string SelectionAdd(string selected,string key) { return Take(oi_selection_add(selected,key)); }
    public static string SelectionRemove(string selected,string key) { return Take(oi_selection_remove(selected,key)); }
    // Slow: runs WinGet. Call it off the interface thread.
    public static string RefreshInventory() { return Take(oi_refresh_inventory()); }
    public static string States() { return Take(oi_states()); }
    public static string Details(string key) { return Take(oi_details(key)); }
    public static string ProfilesMenu() { return Take(oi_profiles_menu()); }
    public static string Winget() { return Take(oi_winget()); }
    public static string LibraryView(bool test) { return Take(oi_library_view(test?1:0)); }
    public static string SaveLibraryView(string view) { return Take(oi_save_library_view(view)); }
    public static string SaveSelection(string path,string keys) { return Take(oi_save_selection(path,keys)); }
    public static string ReadSetup(string path) { return Take(oi_read_setup(path)); }
    public static string SnapshotRows() { return Take(oi_snapshot_rows()); }
    public static string SaveSnapshot(string path,string keys) { return Take(oi_save_snapshot(path,keys)); }
    // The test modes: history and remembered view go to dataRoot, and installing uses
    // installProgram in place of WinGet, or is refused when that is empty.
    public static void TestEnvironment(string dataRoot,string installProgram) { oi_test_environment(dataRoot,installProgram); }
    // The install queue runs inside the engine. Start is empty when started, or "!" and a reason.
    public static string QueueStart(string keys,string logs) { return Take(oi_queue_start(keys,logs)); }
    public static void QueueStop() { oi_queue_stop(); }
    // What happened since the last call: one record per event, as kind, app key and text.
    public static string QueueEvents() { return Take(oi_queue_events()); }
    // Uninstalling: Inventory, Remove (app ids), Scan, or Clean (positions of leftovers), one at a
    // time inside the engine. In the test modes only Inventory is allowed. See engine/ffi/src/uninstall.rs.
    public static string UninstallStart(string operation,string arguments,string log) { return Take(oi_uninstall_start(operation,arguments,log)); }
    public static void UninstallStop() { oi_uninstall_stop(); }
    public static string UninstallEvents() { return Take(oi_uninstall_events()); }
    // How many removed apps are on record for a leftover check.
    public static int UninstallTargets() { return oi_uninstall_targets(); }

    static string Hash(Stream stream) {
        using(var sha=SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","").ToLowerInvariant();
    }
    static string HashFile(string path) { using(var file=File.OpenRead(path)) return Hash(file); }
    static Stream Resource(string name) { return Assembly.GetExecutingAssembly().GetManifestResourceStream(name); }

    // The 3.6 cache (Launcher.CacheAssembly): one immutable directory per revision, named by
    // the SHA-256 of the file, which is checked again before the file is trusted.
    static string Extract(string resourceName,string fileName,bool test) {
        string hash;
        using(var resource=Resource(resourceName)) hash=Hash(resource);
        string directory=Path.Combine(Program.RuntimeRoot(test),hash);
        Directory.CreateDirectory(directory);
        string path=Path.Combine(directory,fileName);
        if(File.Exists(path) && HashFile(path)==hash) return path;
        string temporary=Path.Combine(directory,Guid.NewGuid().ToString("N")+".tmp");
        try {
            using(var resource=Resource(resourceName)) using(var copy=File.Create(temporary)) resource.CopyTo(copy);
            if(File.Exists(path)) File.Replace(temporary,path,null);
            else {
                try { File.Move(temporary,path); }
                catch(IOException) { if(!File.Exists(path) || HashFile(path)!=hash) throw; }
            }
        } finally { if(File.Exists(temporary)) File.Delete(temporary); }
        return path;
    }

    // Loaded by full path first; the imports above then resolve to the module already in memory,
    // so no directory is ever searched for the engine.
    public static void Load(bool test) {
        string path=Extract("1nstall.Engine",Library,test);
        if(LoadLibraryW(path)==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"Could not load the 1nstall engine.");
    }
}
