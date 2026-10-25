using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace PigPendant.Windows;

internal static class Native
{
    private const int GwlExStyle = -20;
    private const nint Transparent = 0x20, ToolWindow = 0x80, NoActivate = 0x08000000;
    private const int SwpNoActivate = 0x0010, SwpShowWindow = 0x0040;
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern nint GetWindowLongPtr(nint hWnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern nint SetWindowLongPtr(nint hWnd, int index, nint value);
    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(nint hWnd, nint insertAfter, int x, int y, int width, int height, int flags);
    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out PixelPoint point);
    [StructLayout(LayoutKind.Sequential)]
    private struct PixelPoint { public int X, Y; }
    public static PigPendant.Core.Vec Cursor()
    {
        GetCursorPos(out var p);
        return new(p.X, -p.Y);
    }
    public static void ConfigureOverlay(Window window, System.Drawing.Rectangle bounds)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        var style = GetWindowLongPtr(hwnd, GwlExStyle);
        SetWindowLongPtr(hwnd, GwlExStyle, style | Transparent | ToolWindow | NoActivate);
        SetWindowPos(hwnd, (nint)(-1), bounds.X, bounds.Y, bounds.Width, bounds.Height, SwpNoActivate | SwpShowWindow);
    }
    #if TESTING
    public static bool HasOverlayStyles(Window window)
    {
        var style = GetWindowLongPtr(new WindowInteropHelper(window).Handle, GwlExStyle);
        return (style & (Transparent | ToolWindow | NoActivate)) == (Transparent | ToolWindow | NoActivate);
    }
    #endif
}
