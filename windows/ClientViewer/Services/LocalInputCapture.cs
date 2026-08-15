using System.Windows;
using System.Windows.Input;
using ToInfinity.Protocol;
using ProtoMouseButton = ToInfinity.Protocol.MouseButton;

namespace ToInfinity.ClientViewer.Services;

/// <summary>
/// Captures local mouse/keyboard input from a WPF element while it has
/// focus and forwards it as SPEC.md §4 input events, normalized to the
/// 0-65535 coordinate space (§4.1) relative to the element's bounds
/// (which display the full remote virtual-display frame at 1:1 aspect).
/// </summary>
public sealed class LocalInputCapture
{
    private readonly FrameworkElement _captureElement;
    private readonly Func<InputEvent, Task> _sendAsync;

    public bool IsEnabled { get; set; }

    public LocalInputCapture(FrameworkElement captureElement, Func<InputEvent, Task> sendAsync)
    {
        _captureElement = captureElement;
        _sendAsync = sendAsync;

        _captureElement.MouseMove += OnMouseMove;
        _captureElement.MouseDown += OnMouseDown;
        _captureElement.MouseUp += OnMouseUp;
        _captureElement.MouseWheel += OnMouseWheel;
        _captureElement.KeyDown += OnKeyDown;
        _captureElement.KeyUp += OnKeyUp;
    }

    private (ushort x, ushort y)? Normalize(Point p)
    {
        double width = _captureElement.ActualWidth;
        double height = _captureElement.ActualHeight;
        if (width <= 0 || height <= 0)
        {
            return null;
        }

        double nx = Math.Clamp(p.X / width, 0.0, 1.0);
        double ny = Math.Clamp(p.Y / height, 0.0, 1.0);
        return ((ushort)(nx * 65535), (ushort)(ny * 65535));
    }

    private void OnMouseMove(object sender, MouseEventArgs e)
    {
        if (!IsEnabled) return;
        var norm = Normalize(e.GetPosition(_captureElement));
        if (norm is null) return;
        _ = _sendAsync(new MouseMoveEvent(norm.Value.x, norm.Value.y));
    }

    private void OnMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (!IsEnabled) return;
        var norm = Normalize(e.GetPosition(_captureElement));
        if (norm is null) return;
        ProtoMouseButton? button = MapButton(e.ChangedButton);
        if (button is null) return;
        _ = _sendAsync(new MouseButtonDownEvent(norm.Value.x, norm.Value.y, button.Value));
    }

    private void OnMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (!IsEnabled) return;
        var norm = Normalize(e.GetPosition(_captureElement));
        if (norm is null) return;
        ProtoMouseButton? button = MapButton(e.ChangedButton);
        if (button is null) return;
        _ = _sendAsync(new MouseButtonUpEvent(norm.Value.x, norm.Value.y, button.Value));
    }

    private void OnMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (!IsEnabled) return;
        var norm = Normalize(e.GetPosition(_captureElement));
        if (norm is null) return;
        short delta = (short)Math.Clamp(e.Delta, short.MinValue, short.MaxValue);
        _ = _sendAsync(new MouseWheelEvent(norm.Value.x, norm.Value.y, 0, delta));
    }

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        if (!IsEnabled) return;
        if (HidKeyMap.TryGetHidUsage(e.Key, out ushort hidUsage))
        {
            _ = _sendAsync(new KeyDownEvent(hidUsage));
        }
        e.Handled = true;
    }

    private void OnKeyUp(object sender, KeyEventArgs e)
    {
        if (!IsEnabled) return;
        if (HidKeyMap.TryGetHidUsage(e.Key, out ushort hidUsage))
        {
            _ = _sendAsync(new KeyUpEvent(hidUsage));
        }
        e.Handled = true;
    }

    private static ProtoMouseButton? MapButton(System.Windows.Input.MouseButton wpfButton) => wpfButton switch
    {
        System.Windows.Input.MouseButton.Left => ProtoMouseButton.Left,
        System.Windows.Input.MouseButton.Right => ProtoMouseButton.Right,
        System.Windows.Input.MouseButton.Middle => ProtoMouseButton.Middle,
        System.Windows.Input.MouseButton.XButton1 => ProtoMouseButton.X1,
        System.Windows.Input.MouseButton.XButton2 => ProtoMouseButton.X2,
        _ => null,
    };
}
