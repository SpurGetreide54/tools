#requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    [System.Windows.Forms.MessageBox]::Show(
        "This tool must be run as Administrator (it manages netsh portproxy and firewall rules).`n`nRight-click the shortcut and choose 'Run as administrator'.",
        'SSH Relay Manager - Elevation Required',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

$script:RulesPath = Join-Path $PSScriptRoot 'rules.json'
$script:MinPort = 2201
$script:CurrentRules = @()
$script:EditingName = $null
$script:SortColumn = 0
$script:SortDescending = $false

function Load-Rules {
    if (-not (Test-Path $script:RulesPath)) {
        '[]' | Set-Content -Path $script:RulesPath -Encoding UTF8
    }
    $json = Get-Content -Path $script:RulesPath -Raw
    if ([string]::IsNullOrWhiteSpace($json)) { return @() }
    $parsed = $json | ConvertFrom-Json
    if ($null -eq $parsed) { return @() }
    return @($parsed)
}

function Save-Rules {
    param($Rules)
    @($Rules) | ConvertTo-Json -Depth 3 | Set-Content -Path $script:RulesPath -Encoding UTF8
}

function Get-LiveProxyRules {
    $output = netsh interface portproxy show v4tov6 2>$null
    $results = @()
    foreach ($line in $output) {
        # Header/separator lines never satisfy \d+ in both port groups, so they're skipped naturally.
        if ($line -match '^\s*(?<lip>\S+)\s+(?<lport>\d+)\s+(?<cip>\S+)\s+(?<cport>\d+)\s*$') {
            $results += [PSCustomObject]@{
                listenPort  = [int]$Matches['lport']
                ipv6        = $Matches['cip']
                connectPort = [int]$Matches['cport']
            }
        }
    }
    return $results
}

function Sync-Rules {
    $rules = @(Load-Rules)
    $live = Get-LiveProxyRules
    $livePorts = @($live | ForEach-Object { $_.listenPort })

    foreach ($l in $live) {
        $existing = $rules | Where-Object { [int]$_.listenPort -eq $l.listenPort }
        if (-not $existing) {
            $rules += [PSCustomObject]@{
                name        = "Imported-$($l.listenPort)"
                ipv6        = $l.ipv6
                listenPort  = $l.listenPort
                connectPort = $l.connectPort
            }
        }
    }

    $rules = @($rules | Where-Object { $livePorts -contains [int]$_.listenPort })

    Save-Rules $rules
    return $rules
}

function Get-NextFreePort {
    param($Rules)
    $used = @($Rules | ForEach-Object { [int]$_.listenPort })
    $port = $script:MinPort
    while ($used -contains $port) { $port++ }
    return $port
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'SSH Relay Manager'
$form.Size = New-Object System.Drawing.Size(640, 520)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(12, 12)
$listView.Size = New-Object System.Drawing.Size(600, 220)
$listView.View = 'Details'
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.MultiSelect = $false
$listView.Columns.Add('Name', 140) | Out-Null
$listView.Columns.Add('IPv6', 220) | Out-Null
$listView.Columns.Add('Listen Port', 110) | Out-Null
$listView.Columns.Add('Connect Port', 110) | Out-Null
$form.Controls.Add($listView)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refresh'
$btnRefresh.Location = New-Object System.Drawing.Point(12, 240)
$btnRefresh.Size = New-Object System.Drawing.Size(90, 28)
$form.Controls.Add($btnRefresh)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = 'Delete Selected'
$btnDelete.Location = New-Object System.Drawing.Point(110, 240)
$btnDelete.Size = New-Object System.Drawing.Size(120, 28)
$form.Controls.Add($btnDelete)

$btnEdit = New-Object System.Windows.Forms.Button
$btnEdit.Text = 'Edit Selected'
$btnEdit.Location = New-Object System.Drawing.Point(240, 240)
$btnEdit.Size = New-Object System.Drawing.Size(120, 28)
$form.Controls.Add($btnEdit)

$groupBox = New-Object System.Windows.Forms.GroupBox
$groupBox.Text = 'Add Rule'
$groupBox.Location = New-Object System.Drawing.Point(12, 280)
$groupBox.Size = New-Object System.Drawing.Size(600, 150)
$form.Controls.Add($groupBox)

$lblName = New-Object System.Windows.Forms.Label
$lblName.Text = 'Name:'
$lblName.Location = New-Object System.Drawing.Point(10, 25)
$lblName.Size = New-Object System.Drawing.Size(95, 20)
$groupBox.Controls.Add($lblName)

$txtName = New-Object System.Windows.Forms.TextBox
$txtName.Location = New-Object System.Drawing.Point(110, 22)
$txtName.Size = New-Object System.Drawing.Size(200, 20)
$groupBox.Controls.Add($txtName)

$lblIpv6 = New-Object System.Windows.Forms.Label
$lblIpv6.Text = 'VM IPv6 address:'
$lblIpv6.Location = New-Object System.Drawing.Point(10, 55)
$lblIpv6.Size = New-Object System.Drawing.Size(95, 20)
$groupBox.Controls.Add($lblIpv6)

$txtIpv6 = New-Object System.Windows.Forms.TextBox
$txtIpv6.Location = New-Object System.Drawing.Point(110, 52)
$txtIpv6.Size = New-Object System.Drawing.Size(320, 20)
$groupBox.Controls.Add($txtIpv6)

$lblListen = New-Object System.Windows.Forms.Label
$lblListen.Text = 'Listen port (host):'
$lblListen.Location = New-Object System.Drawing.Point(10, 85)
$lblListen.Size = New-Object System.Drawing.Size(145, 20)
$groupBox.Controls.Add($lblListen)

$numListen = New-Object System.Windows.Forms.NumericUpDown
$numListen.Location = New-Object System.Drawing.Point(160, 83)
$numListen.Size = New-Object System.Drawing.Size(80, 20)
$numListen.Minimum = 1
$numListen.Maximum = 65535
$groupBox.Controls.Add($numListen)

$lblConnect = New-Object System.Windows.Forms.Label
$lblConnect.Text = 'Connect port (VM):'
$lblConnect.Location = New-Object System.Drawing.Point(260, 85)
$lblConnect.Size = New-Object System.Drawing.Size(125, 20)
$groupBox.Controls.Add($lblConnect)

$numConnect = New-Object System.Windows.Forms.NumericUpDown
$numConnect.Location = New-Object System.Drawing.Point(390, 83)
$numConnect.Size = New-Object System.Drawing.Size(80, 20)
$numConnect.Minimum = 1
$numConnect.Maximum = 65535
$numConnect.Value = 22
$groupBox.Controls.Add($numConnect)

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = 'Add Rule'
$btnAdd.Location = New-Object System.Drawing.Point(10, 115)
$btnAdd.Size = New-Object System.Drawing.Size(100, 28)
$groupBox.Controls.Add($btnAdd)

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = 'Clear'
$btnClear.Location = New-Object System.Drawing.Point(120, 115)
$btnClear.Size = New-Object System.Drawing.Size(80, 28)
$groupBox.Controls.Add($btnClear)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(12, 440)
$lblStatus.Size = New-Object System.Drawing.Size(600, 40)
$form.Controls.Add($lblStatus)

function Set-Status {
    param([string]$Text, [switch]$IsError)
    $lblStatus.Text = $Text
    $lblStatus.ForeColor = if ($IsError) { [System.Drawing.Color]::DarkRed } else { [System.Drawing.Color]::DarkGreen }
}

function Render-RuleList {
    $sorted = switch ($script:SortColumn) {
        2 { $script:CurrentRules | Sort-Object -Property { [int]$_.listenPort } -Descending:$script:SortDescending }
        3 { $script:CurrentRules | Sort-Object -Property { [int]$_.connectPort } -Descending:$script:SortDescending }
        1 { $script:CurrentRules | Sort-Object -Property ipv6 -Descending:$script:SortDescending }
        default { $script:CurrentRules | Sort-Object -Property name -Descending:$script:SortDescending }
    }
    $listView.Items.Clear()
    foreach ($r in @($sorted)) {
        $item = New-Object System.Windows.Forms.ListViewItem($r.name)
        $item.SubItems.Add($r.ipv6) | Out-Null
        $item.SubItems.Add([string]$r.listenPort) | Out-Null
        $item.SubItems.Add([string]$r.connectPort) | Out-Null
        $listView.Items.Add($item) | Out-Null
    }
}

function Refresh-ListView {
    $rules = Sync-Rules
    $script:CurrentRules = $rules
    $numListen.Value = Get-NextFreePort -Rules $rules
    Render-RuleList
}

function Reset-EditState {
    $script:EditingName = $null
    $txtName.Clear()
    $txtIpv6.Clear()
    $numConnect.Value = 22
    $numListen.Value = Get-NextFreePort -Rules $script:CurrentRules
    $groupBox.Text = 'Add Rule'
    $btnAdd.Text = 'Add Rule'
}

$btnAdd.Add_Click({
    try {
        $name = $txtName.Text.Trim()
        $ipv6Text = $txtIpv6.Text.Trim()
        $listenPort = [int]$numListen.Value
        $connectPort = [int]$numConnect.Value
        $wasEditing = [bool]$script:EditingName

        if ([string]::IsNullOrWhiteSpace($name)) {
            Set-Status 'Name cannot be empty.' -IsError
            return
        }
        if ($script:CurrentRules | Where-Object { $_.name -eq $name -and $_.name -ne $script:EditingName }) {
            Set-Status "Name '$name' is already in use." -IsError
            return
        }

        $parsedIp = $null
        if (-not [System.Net.IPAddress]::TryParse($ipv6Text, [ref]$parsedIp) -or
            $parsedIp.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
            Set-Status "'$ipv6Text' is not a valid IPv6 address." -IsError
            return
        }

        if ($script:CurrentRules | Where-Object { [int]$_.listenPort -eq $listenPort -and $_.name -ne $script:EditingName }) {
            Set-Status "Listen port $listenPort is already in use by another rule." -IsError
            return
        }

        if ($wasEditing) {
            $oldRule = $script:CurrentRules | Where-Object { $_.name -eq $script:EditingName } | Select-Object -First 1
            netsh interface portproxy delete v4tov6 listenport=$($oldRule.listenPort) listenaddress=0.0.0.0 | Out-Null
            Remove-NetFirewallRule -DisplayName "SSHRelay-$($oldRule.name)" -ErrorAction SilentlyContinue | Out-Null
        }

        netsh interface portproxy add v4tov6 listenport=$listenPort listenaddress=0.0.0.0 connectport=$connectPort connectaddress=$ipv6Text | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Set-Status "netsh failed to add the portproxy rule (exit code $LASTEXITCODE)." -IsError
            return
        }

        New-NetFirewallRule -DisplayName "SSHRelay-$name" -Direction Inbound -Protocol TCP -LocalPort $listenPort -RemoteAddress Any -Action Allow -ErrorAction Stop | Out-Null

        $rules = @(Load-Rules | Where-Object { $_.name -ne $script:EditingName })
        $rules += [PSCustomObject]@{
            name        = $name
            ipv6        = $ipv6Text
            listenPort  = $listenPort
            connectPort = $connectPort
        }
        Save-Rules $rules

        Reset-EditState
        Refresh-ListView
        Set-Status $(if ($wasEditing) { "Rule '$name' updated." } else { "Rule '$name' added." })
    } catch {
        Set-Status "Error: $($_.Exception.Message)" -IsError
    }
})

$btnDelete.Add_Click({
    try {
        if ($listView.SelectedItems.Count -eq 0) {
            Set-Status 'Select a rule to delete first.' -IsError
            return
        }
        $name = $listView.SelectedItems[0].Text
        $rule = $script:CurrentRules | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if (-not $rule) {
            Set-Status "Could not find rule '$name'." -IsError
            return
        }

        netsh interface portproxy delete v4tov6 listenport=$($rule.listenPort) listenaddress=0.0.0.0 | Out-Null
        # Imported rules (created before this tool existed) never had a matching firewall rule to begin with.
        Remove-NetFirewallRule -DisplayName "SSHRelay-$name" -ErrorAction SilentlyContinue | Out-Null

        $rules = @(Load-Rules | Where-Object { $_.name -ne $name })
        Save-Rules $rules

        if ($script:EditingName -eq $name) {
            Reset-EditState
        }

        Refresh-ListView
        Set-Status "Rule '$name' deleted."
    } catch {
        Set-Status "Error: $($_.Exception.Message)" -IsError
    }
})

$btnEdit.Add_Click({
    try {
        if ($listView.SelectedItems.Count -eq 0) {
            Set-Status 'Select a rule to edit first.' -IsError
            return
        }
        $name = $listView.SelectedItems[0].Text
        $rule = $script:CurrentRules | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if (-not $rule) {
            Set-Status "Could not find rule '$name'." -IsError
            return
        }

        $script:EditingName = $rule.name
        $txtName.Text = $rule.name
        $txtIpv6.Text = $rule.ipv6
        $numListen.Value = [int]$rule.listenPort
        $numConnect.Value = [int]$rule.connectPort
        $groupBox.Text = "Edit Rule: $($rule.name)"
        $btnAdd.Text = 'Save Changes'
        Set-Status "Editing '$($rule.name)'. Update the fields and click Save Changes, or Clear to cancel."
    } catch {
        Set-Status "Error: $($_.Exception.Message)" -IsError
    }
})

$btnClear.Add_Click({
    Reset-EditState
    Set-Status 'Cleared.'
})

$btnRefresh.Add_Click({ Refresh-ListView; Set-Status 'Refreshed.' })

$listView.Add_ColumnClick({
    param($sender, $e)
    if ($script:SortColumn -eq $e.Column) {
        $script:SortDescending = -not $script:SortDescending
    } else {
        $script:SortColumn = $e.Column
        $script:SortDescending = $false
    }
    Render-RuleList
})

[System.Windows.Forms.Application]::EnableVisualStyles()
$form.Add_Shown({ Refresh-ListView })
[void]$form.ShowDialog()
