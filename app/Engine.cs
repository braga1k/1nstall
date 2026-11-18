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
    [DllImport(Library)] static extern IntPtr oi_installed();
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
    public static string Installed() { return Take(oi_installed()); }

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
