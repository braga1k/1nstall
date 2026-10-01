using System;
using System.Runtime.InteropServices;

public static class FirstInstallWindow
{
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out int value, int size);
    [StructLayout(LayoutKind.Sequential)]
    private struct Margins { public int Left, Right, Top, Bottom; }
    [DllImport("dwmapi.dll")]
    private static extern int DwmExtendFrameIntoClientArea(IntPtr window, ref Margins margins);

    // Desktop Acrylic is supported by DWM on Windows 11 22H2+.
    // Failure keeps the existing opaque WPF surface on older Windows.
    public static int SetBackdrop(IntPtr window, bool enabled)
    {
        int material = enabled ? 3 : 1;
        int result = DwmSetWindowAttribute(window, 38, ref material, 4);
        int extent = enabled && result == 0 ? -1 : 0;
        var margins = new Margins { Left = extent, Right = extent, Top = extent, Bottom = extent };
        int frame = DwmExtendFrameIntoClientArea(window, ref margins);
        if (enabled && result == 0 && frame != 0)
        {
            material = 1; DwmSetWindowAttribute(window, 38, ref material, 4);
            return frame;
        }
        return result;
    }
    public static int ReadBackdrop(IntPtr window)
    {
        int value;
        return DwmGetWindowAttribute(window, 38, out value, 4) == 0 ? value : -1;
    }

    public static int Apply(IntPtr window)
    {
        // Custom WindowChrome owns the whole frame, including activation painting.
        // Border colour alone does not disable DWM's non-client accent surface.
        int nonClient = 1; // DWMNCRP_DISABLED
        DwmSetWindowAttribute(window, 2, ref nonClient, 4);
        int dark = 1;
        DwmSetWindowAttribute(window, 20, ref dark, 4);
        int border = unchecked((int)0xFFFFFFFE);
        DwmSetWindowAttribute(window, 34, ref border, 4);
        int round = 2;
        return DwmSetWindowAttribute(window, 33, ref round, 4);
    }

    public static int ReadCornerPreference(IntPtr window)
    {
        int value;
        return DwmGetWindowAttribute(window, 33, out value, 4) == 0 ? value : -1;
    }

    public static int ReadNativeFrameEnabled(IntPtr window)
    {
        int value;
        return DwmGetWindowAttribute(window, 1, out value, 4) == 0 ? value : -1;
    }
}
