using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;
using ToInfinity.ClientViewer.Services;

namespace ToInfinity.ClientViewer.Views;

public partial class MainWindow : Window
{
    private readonly DiscoveryClient _discoveryClient = new();
    private readonly DeviceIdentity _identity = DeviceIdentity.LoadOrCreate();
    private readonly List<DiscoveredHost> _discoveredHosts = new();

    private HostSession? _session;
    private LocalInputCapture? _inputCapture;

    public MainWindow()
    {
        InitializeComponent();

        _discoveryClient.HostDiscovered += OnHostDiscovered;
        _discoveryClient.Start();

        Closed += (_, _) =>
        {
            _discoveryClient.Dispose();
            _session?.Dispose();
        };
    }

    private void OnHostDiscovered(DiscoveredHost host)
    {
        Dispatcher.Invoke(() =>
        {
            int existingIndex = _discoveredHosts.FindIndex(h => h.DeviceId == host.DeviceId);
            if (existingIndex >= 0)
            {
                _discoveredHosts[existingIndex] = host;
            }
            else
            {
                _discoveredHosts.Add(host);
            }

            HostListBox.ItemsSource = null;
            HostListBox.ItemsSource = _discoveredHosts;
        });
    }

    private async void OnRefreshClick(object sender, RoutedEventArgs e)
    {
        await _discoveryClient.SendQueryOnceAsync();
    }

    private async void OnConnectClick(object sender, RoutedEventArgs e)
    {
        if (HostListBox.SelectedItem is not DiscoveredHost host)
        {
            StatusText.Text = "Select a host first.";
            return;
        }

        string pin = PinTextBox.Text.Trim();
        if (pin.Length != 6 || !pin.All(char.IsDigit))
        {
            StatusText.Text = "PIN must be 6 digits.";
            return;
        }

        ConnectButton.IsEnabled = false;
        StatusText.Text = "Connecting...";

        _session?.Dispose();
        _session = new HostSession(host, _identity.DeviceId, _identity.Name);
        _session.StatusChanged += status => Dispatcher.Invoke(() => StatusText.Text = status);
        _session.FrameReceived += OnFrameReceived;

        bool ok = await _session.ConnectAndPairAsync(pin, CancellationToken.None);
        ConnectButton.IsEnabled = true;

        if (ok)
        {
            _inputCapture = new LocalInputCapture(RemoteFrameImage, evt => _session.SendInputAsync(evt));
            _inputCapture.IsEnabled = true;
            RemoteFrameImage.Focusable = true;
            RemoteFrameImage.Focus();
        }
    }

    private void OnFrameReceived(byte[] jpegBytes, int width, int height)
    {
        Dispatcher.Invoke(() =>
        {
            using var stream = new MemoryStream(jpegBytes);
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.StreamSource = stream;
            bitmap.EndInit();
            bitmap.Freeze();
            RemoteFrameImage.Source = bitmap;
        });
    }
}
