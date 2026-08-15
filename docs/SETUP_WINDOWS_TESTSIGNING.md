# Windows test-signing setup — toInfinity VirtualDisplayDriver

The `VirtualDisplayDriver` is an unsigned (dev-built) UMDF2 IddCx driver
(IddCx is a user-mode-only technology — there is no kernel-mode IddCx
variant — so the driver binary is a DLL hosted by `WUDFHost.exe`, not a
`.sys`). Windows only loads unsigned drivers when the machine is in
**test-signing mode**. This document is the exact, step-by-step procedure to
build (on a machine with WDK installed), install, verify, and later remove
the driver.

As of this revision the project has been verified to actually compile and
link cleanly (0 errors, 0 warnings) with MSBuild + Visual Studio 2022 + WDK
10.0.22621.0 — see `docs/ARCHITECTURE.md`. Everything below this point
(test-signing, install, Device Manager verification) still requires a real
Windows machine with a reboot and has not been exercised in that sandbox.

> Test-signing mode weakens the kernel driver signing requirement for the
> whole machine. Only enable it on a machine you control, and turn it back
> off (`bcdedit /set testsigning off`) when you're done testing.

## 0. Prerequisites

- Windows 10/11, administrator access, machine reboot allowed.
- Visual Studio 2022 with the "Desktop development with C++" workload.
- Windows Driver Kit (WDK) matching your Windows SDK version
  (https://learn.microsoft.com/windows-hardware/drivers/download-the-wdk).
- `devcon.exe` (ships with the WDK, under
  `%ProgramFiles(x86)%\Windows Kits\10\Tools\<arch>\devcon.exe`) or use
  `pnputil` (built into Windows, no extra install needed).

## 1. Build the driver

From a WDK-enabled Visual Studio Developer Command Prompt:

```
msbuild windows\VirtualDisplayDriver\VirtualDisplayDriver.vcxproj /p:Configuration=Release /p:Platform=x64
```

This produces `VirtualDisplayDriver.dll`, `VirtualDisplayDriver.inf`, and a
`.cat` catalog file under the build output directory
(`x64\Release\VirtualDisplayDriver\`).

Because this is unsigned, also generate a test certificate and sign the
catalog (or rely on test-signing mode alone — test-signing mode allows
completely unsigned kernel drivers to load, so a self-signed test cert is
optional but recommended for a cleaner `pnputil` install):

```
MakeCert -r -pe -ss PrivateCertStore -n "CN=toInfinity Test Cert" toInfinityTest.cer
signtool sign /v /s PrivateCertStore /n "toInfinity Test Cert" /t http://timestamp.digicert.com VirtualDisplayDriver.cat
certutil -addstore Root toInfinityTest.cer
certutil -addstore TrustedPublisher toInfinityTest.cer
```

## 2. Enable test-signing mode

Elevated Command Prompt or PowerShell:

```
bcdedit /set testsigning on
```

**Reboot the machine.** After reboot you should see a "Test Mode" watermark
in the bottom-right corner of the desktop — this confirms test-signing is
active.

## 3. Install the driver

Two supported paths — `pnputil` (simplest, no extra tools) or `devcon`
(gives more control and is the traditional IddCx-sample workflow).

### Option A: pnputil (recommended)

```
pnputil /add-driver "x64\Release\VirtualDisplayDriver\VirtualDisplayDriver.inf" /install
```

Since this is a root-enumerated software device (no physical PnP hardware
match), you then need to create the device node so Windows actually
instantiates it. Use `devcon` for this step (pnputil alone stages the
driver package but does not create a root-enumerated node):

```
devcon.exe install "x64\Release\VirtualDisplayDriver\VirtualDisplayDriver.inf" Root\ToInfinityIddDriver
```

### Option B: devcon end-to-end

```
devcon.exe install "x64\Release\VirtualDisplayDriver\VirtualDisplayDriver.inf" Root\ToInfinityIddDriver
```

`devcon install` both stages and creates the root-enumerated device node in
one step.

## 4. Verify it shows up as a monitor

1. Open **Settings → System → Display**. You should see a new display
   entry (labeled "toInfinity Virtual Display Adapter" or similar,
   numbered as your next display, e.g. "2") appear in the display layout
   diagram, alongside your physical monitor(s).
2. Confirm it reports 1920x1080 as its (only) available resolution:
   **Settings → System → Display →** select the new display **→ Display
   resolution**.
3. Optionally confirm via Device Manager: **Device Manager → Display
   adapters** — you should see the toInfinity virtual adapter listed
   with no yellow warning icon (a warning icon means the driver failed to
   load — check `Get-WinEvent -LogName System | Select-String IddCx` or
   the kernel debugger output for the failure).
4. From an elevated PowerShell you can also confirm via WMI:
   ```
   Get-CimInstance Win32_DesktopMonitor | Select-Object Name, DeviceID, Status
   ```
   or via `dxdiag` → Display tab (select the new display index).
5. The Windows desktop should now be extendable/draggable onto the new
   display exactly like a real second monitor (drag a window past the edge
   of your physical screen onto it, or use **Win+P → Extend**).

## 5. Uninstall / roll back

Remove the device node and driver package:

```
devcon.exe remove Root\ToInfinityIddDriver
pnputil /enum-drivers
pnputil /delete-driver <published-name-from-enum-drivers-matching-VirtualDisplayDriver.inf> /uninstall
```

(`pnputil /enum-drivers` lists published driver packages as `oem##.inf`;
find the one whose "Original Name" is `VirtualDisplayDriver.inf` and pass
that `oem##.inf` name to `/delete-driver`.)

Turn test-signing back off once you no longer need to load unsigned
drivers:

```
bcdedit /set testsigning off
```

**Reboot** — the "Test Mode" watermark should disappear, confirming the
machine is back to normal signature enforcement.

## Troubleshooting

- **Driver installs but display never appears**: check Device Manager for
  a warning icon on the adapter; open its Properties → Events tab for the
  most recent load failure code.
- **"This driver cannot be installed because it's not signed" even with
  test-signing on**: confirm the reboot after `bcdedit /set testsigning on`
  actually happened (`bcdedit /enum {current}` should show
  `testsigning Yes`), and confirm Secure Boot is disabled in firmware
  (Secure Boot blocks test-signing outright on many OEM configurations).
- **devcon not found**: it's not included by default in a plain WDK
  install location on PATH; locate it under
  `%ProgramFiles(x86)%\Windows Kits\10\Tools\<x86|x64>\devcon.exe` and
  either add that directory to PATH or invoke it by full path.
