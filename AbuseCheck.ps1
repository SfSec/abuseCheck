# AbuseIPDB Lookup Tool - Resident global hotkey (Shift+Alt+A)
# Launch this once (e.g. at startup); it stays in the background listening.
# Requires: AbuseIPDB API key. Get one free at https://www.abuseipdb.com/account/api

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==== CONFIG ====
$ApiKey       = $env:ABUSEIPDB_KEY   # set with: setx ABUSEIPDB_KEY "your_key"
$MaxAgeInDays = 90
# ================

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    [System.Windows.Forms.MessageBox]::Show(
        "ABUSEIPDB_KEY environment variable is not set.`r`nSet it with:  setx ABUSEIPDB_KEY `"your_key`"  then reopen.",
        "Config Error", "OK", "Error") | Out-Null
    return
}

# ---------- UI: IP input box ----------
function Show-IpInputBox {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "AbuseIPDB Lookup"
    $form.Size = New-Object System.Drawing.Size(420, 360)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Enter IP address(es) - one per line, comma, or space separated:"
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(10, 10)
    $form.Controls.Add($label)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Multiline = $true
    $textBox.ScrollBars = "Vertical"
    $textBox.AcceptsReturn = $true
    $textBox.Location = New-Object System.Drawing.Point(10, 40)
    $textBox.Size = New-Object System.Drawing.Size(385, 230)
    $form.Controls.Add($textBox)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Location = New-Object System.Drawing.Point(230, 285)
    $okButton.Size = New-Object System.Drawing.Size(75, 28)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)
    $form.AcceptButton = $okButton

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point(315, 285)
    $cancelButton.Size = New-Object System.Drawing.Size(80, 28)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    # Ctrl+Enter submits (plain Enter makes a new line in the multiline box)
    $textBox.Add_KeyDown({
        if ($_.KeyCode -eq "Return" -and $_.Control) { $okButton.PerformClick() }
    })

    $form.Add_Shown({ $form.Activate(); $textBox.Focus() })
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return $textBox.Text }
    return $null
}

# ---------- AbuseIPDB API check ----------
function Invoke-AbuseCheck {
    param([string[]]$IpList)

    $results = @()
    foreach ($ip in $IpList) {
        $ip = $ip.Trim()
        if ([string]::IsNullOrWhiteSpace($ip)) { continue }
        try {
            $headers = @{ "Key" = $ApiKey; "Accept" = "application/json" }
            $uri = "https://api.abuseipdb.com/api/v2/check?ipAddress=$ip&maxAgeInDays=$MaxAgeInDays&verbose"
            $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
            $d = $resp.data
            $results += [PSCustomObject]@{
                Address              = $d.ipAddress
                AbuseConfidenceScore = $d.abuseConfidenceScore
                IpVersion            = $d.ipVersion
                IsPublic             = $d.isPublic
                IsTor                = $d.isTor
                IsWhitelisted        = $d.isWhitelisted
                TotalReports         = $d.totalReports
                NumDistinctUsers     = $d.numDistinctUsers
                Domain               = $d.domain
                ISP                  = $d.isp
                UsageType            = $d.usageType
                Geo                  = ("{0} ({1})" -f $d.countryName, $d.countryCode)
                LastReported         = $d.lastReportedAt
            }
        }
        catch {
            $results += [PSCustomObject]@{
                Address = $ip; AbuseConfidenceScore = "ERROR"; IpVersion = ""; IsPublic = ""
                IsTor = ""; IsWhitelisted = ""; TotalReports = ""; NumDistinctUsers = ""
                Domain = ""; ISP = ""; UsageType = ""; Geo = $_.Exception.Message; LastReported = ""
            }
        }
    }
    return $results
}

# ---------- Results grid ----------
function Show-ResultsGrid {
    param([object[]]$Data)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "AbuseIPDB Results"
    $form.Size = New-Object System.Drawing.Size(1200, 500)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = "Fill"
    $grid.AutoSizeColumnsMode = "AllCells"
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.SelectionMode = "FullRowSelect"

    $dt = New-Object System.Data.DataTable
    $cols = "Address","AbuseConfidenceScore","IpVersion","IsPublic","IsTor","IsWhitelisted","TotalReports","NumDistinctUsers","Domain","ISP","UsageType","Geo","LastReported"
    foreach ($c in $cols) { [void]$dt.Columns.Add($c) }
    foreach ($row in $Data) {
        $r = $dt.NewRow()
        foreach ($c in $cols) { $r[$c] = [string]$row.$c }
        [void]$dt.Rows.Add($r)
    }
    $grid.DataSource = $dt

    $grid.Add_DataBindingComplete({
        foreach ($gr in $grid.Rows) {
            $score = $gr.Cells["AbuseConfidenceScore"].Value
            if ($score -match '^\d+$' -and [int]$score -ge 50) {
                $gr.DefaultCellStyle.BackColor = [System.Drawing.Color]::MistyRose
            } elseif ($score -match '^\d+$' -and [int]$score -gt 0) {
                $gr.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightYellow
            }
        }
    })

    $form.Controls.Add($grid)
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
}

# ---------- The lookup action fired by the hotkey ----------
function Invoke-Lookup {
    $ipInput = Show-IpInputBox
    if ($ipInput) {
        $ips = $ipInput -split "[\r\n,; ]+" | Where-Object { $_ -ne "" }
        if ($ips.Count -gt 0) {
            $data = Invoke-AbuseCheck -IpList $ips
            Show-ResultsGrid -Data $data
        }
    }
}

# ---------- C#-backed hidden message window that catches WM_HOTKEY ----------
# This is the piece that makes the hotkey truly global and resident.
Add-Type -ReferencedAssemblies System.Windows.Forms @"
using System;
using System.Windows.Forms;
using System.Runtime.InteropServices;

public class HotKeyWindow : NativeWindow, IDisposable
{
    [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private const int WM_HOTKEY = 0x0312;
    private const int HOTKEY_ID = 0xA1B2;

    // MOD_ALT = 0x0001, MOD_SHIFT = 0x0004, MOD_NOREPEAT = 0x4000
    private const uint MODS = 0x0001 | 0x0004 | 0x4000;
    private const uint VK_A = 0x41;

    public event Action HotKeyPressed;

    public HotKeyWindow()
    {
        CreateHandle(new CreateParams());
        RegisterHotKey(this.Handle, HOTKEY_ID, MODS, VK_A);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY && (int)m.WParam == HOTKEY_ID)
        {
            if (HotKeyPressed != null) HotKeyPressed();
        }
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        UnregisterHotKey(this.Handle, HOTKEY_ID);
        this.DestroyHandle();
    }
}
"@

# ---------- Tray icon so you can see it's running / quit it ----------
$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = [System.Drawing.SystemIcons]::Shield
$trayIcon.Text = "AbuseIPDB Lookup (Shift+Alt+A)"
$trayIcon.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miLookup = $menu.Items.Add("Lookup IPs now")
$miExit   = $menu.Items.Add("Exit")
$trayIcon.ContextMenuStrip = $menu

# ---------- Wire it all up ----------
$hotkey = New-Object HotKeyWindow

# Use a SynchronizationContext-safe invoke: marshal the action onto the UI thread.
$syncForm = New-Object System.Windows.Forms.Form
$syncForm.ShowInTaskbar = $false
$syncForm.WindowState = 'Minimized'
$syncForm.FormBorderStyle = 'FixedToolWindow'
$syncForm.Opacity = 0
$syncForm.Load.Add({ $syncForm.Hide() }) | Out-Null
$null = $syncForm.Handle  # force handle creation so BeginInvoke works

$hotkey.add_HotKeyPressed({
    $syncForm.BeginInvoke([Action]{ Invoke-Lookup }) | Out-Null
})

$miLookup.add_Click({ $syncForm.BeginInvoke([Action]{ Invoke-Lookup }) | Out-Null })
$miExit.add_Click({
    $trayIcon.Visible = $false
    $hotkey.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$trayIcon.add_DoubleClick({ $syncForm.BeginInvoke([Action]{ Invoke-Lookup }) | Out-Null })

# Balloon hint on first launch
$trayIcon.ShowBalloonTip(3000, "AbuseIPDB Lookup running", "Press Shift+Alt+A anytime to look up IPs.", "Info")

# ---------- Message loop: keeps the script resident ----------
[System.Windows.Forms.Application]::Run()

# Cleanup if the loop ever exits
$hotkey.Dispose()
$trayIcon.Dispose()
