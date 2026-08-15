using System.Runtime.InteropServices;
using ToInfinity.Protocol;
using Microsoft.Extensions.Logging;

namespace ToInfinity.HostAgent.Services;

/// <summary>
/// Injects mouse/keyboard events received on the input channel (SPEC.md §4)
/// into Windows via user32.dll SendInput, translating normalized
/// 0-65535-per-axis coordinates (§4.1) into the virtual display's absolute
/// coordinate space.
/// </summary>
public sealed class InputInjector
{
    private readonly ILogger<InputInjector> _logger;
    private readonly HostAgentOptions _options;

    public InputInjector(ILogger<InputInjector> logger, HostAgentOptions options)
    {
        _logger = logger;
        _options = options;
    }

    public void Inject(InputEvent inputEvent)
    {
        switch (inputEvent)
        {
            case MouseMoveEvent move:
                SendMouseAbsolute(move.X, move.Y, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK);
                break;

            case MouseButtonDownEvent down:
                SendMouseButton(down.X, down.Y, (byte)down.Button, isDown: true);
                break;

            case MouseButtonUpEvent up:
                SendMouseButton(up.X, up.Y, (byte)up.Button, isDown: false);
                break;

            case MouseWheelEvent wheel:
                SendMouseWheel(wheel.X, wheel.Y, wheel.DeltaX, wheel.DeltaY);
                break;

            case KeyDownEvent keyDown:
                SendKey(keyDown.HidUsage, isDown: true);
                break;

            case KeyUpEvent keyUp:
                SendKey(keyUp.HidUsage, isDown: false);
                break;

            default:
                _logger.LogWarning("Unhandled input event type {Type}", inputEvent.GetType());
                break;
        }
    }

    private void SendMouseAbsolute(ushort normX, ushort normY, uint flags)
    {
        var input = new INPUT
        {
            type = INPUT_MOUSE,
            u = new InputUnion
            {
                mi = new MOUSEINPUT
                {
                    dx = normX, // already 0-65535 normalized, matches MOUSEEVENTF_ABSOLUTE + VIRTUALDESK semantics
                    dy = normY,
                    mouseData = 0,
                    dwFlags = flags,
                    time = 0,
                    dwExtraInfo = IntPtr.Zero,
                }
            }
        };

        SendInputChecked(input);
    }

    private void SendMouseButton(ushort normX, ushort normY, byte button, bool isDown)
    {
        uint moveFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
        SendMouseAbsolute(normX, normY, moveFlags);

        uint buttonFlag = button switch
        {
            0 => isDown ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP,
            1 => isDown ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP,
            2 => isDown ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP,
            3 or 4 => isDown ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP,
            _ => 0u,
        };

        if (buttonFlag == 0)
        {
            _logger.LogWarning("Unknown mouse button id {Button}", button);
            return;
        }

        uint xButtonData = button == 3 ? 1u : button == 4 ? 2u : 0u;

        var input = new INPUT
        {
            type = INPUT_MOUSE,
            u = new InputUnion
            {
                mi = new MOUSEINPUT
                {
                    dx = normX,
                    dy = normY,
                    mouseData = xButtonData,
                    dwFlags = buttonFlag | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK,
                    time = 0,
                    dwExtraInfo = IntPtr.Zero,
                }
            }
        };

        SendInputChecked(input);
    }

    private void SendMouseWheel(ushort normX, ushort normY, short deltaX, short deltaY)
    {
        SendMouseAbsolute(normX, normY, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK);

        if (deltaY != 0)
        {
            SendInputChecked(new INPUT
            {
                type = INPUT_MOUSE,
                u = new InputUnion
                {
                    mi = new MOUSEINPUT { dx = normX, dy = normY, mouseData = unchecked((uint)(int)deltaY), dwFlags = MOUSEEVENTF_WHEEL | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK, time = 0, dwExtraInfo = IntPtr.Zero }
                }
            });
        }

        if (deltaX != 0)
        {
            SendInputChecked(new INPUT
            {
                type = INPUT_MOUSE,
                u = new InputUnion
                {
                    mi = new MOUSEINPUT { dx = normX, dy = normY, mouseData = unchecked((uint)(int)deltaX), dwFlags = MOUSEEVENTF_HWHEEL | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK, time = 0, dwExtraInfo = IntPtr.Zero }
                }
            });
        }
    }

    private void SendKey(ushort hidUsage, bool isDown)
    {
        if (!HidUsageToVirtualKey.TryGetVirtualKey(hidUsage, out ushort vk))
        {
            _logger.LogWarning("No VK mapping for HID usage 0x{HidUsage:X4}", hidUsage);
            return;
        }

        ushort scanCode = (ushort)MapVirtualKey(vk, MAPVK_VK_TO_VSC);

        var input = new INPUT
        {
            type = INPUT_KEYBOARD,
            u = new InputUnion
            {
                ki = new KEYBDINPUT
                {
                    wVk = vk,
                    wScan = scanCode,
                    dwFlags = isDown ? 0u : KEYEVENTF_KEYUP,
                    time = 0,
                    dwExtraInfo = IntPtr.Zero,
                }
            }
        };

        SendInputChecked(input);
    }

    private void SendInputChecked(in INPUT input)
    {
        INPUT[] inputs = { input };
        uint sent = SendInput(1, inputs, Marshal.SizeOf<INPUT>());
        if (sent != 1)
        {
            _logger.LogWarning("SendInput reported {Sent}/1 events sent (GetLastError may have details)", sent);
        }
    }

    #region P/Invoke

    private const int INPUT_MOUSE = 0;
    private const int INPUT_KEYBOARD = 1;

    private const uint MOUSEEVENTF_MOVE = 0x0001;
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    private const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    private const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    private const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
    private const uint MOUSEEVENTF_XDOWN = 0x0080;
    private const uint MOUSEEVENTF_XUP = 0x0100;
    private const uint MOUSEEVENTF_WHEEL = 0x0800;
    private const uint MOUSEEVENTF_HWHEEL = 0x1000;
    private const uint MOUSEEVENTF_VIRTUALDESK = 0x4000;
    private const uint MOUSEEVENTF_ABSOLUTE = 0x8000;

    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint MAPVK_VK_TO_VSC = 0;

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public int type;
        public InputUnion u;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKey(uint uCode, uint uMapType);

    #endregion
}
