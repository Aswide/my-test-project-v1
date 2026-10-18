Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"' -f $PSCommandPath
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
    exit
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:HostsPath = Join-Path ([Environment]::GetFolderPath('System')) 'drivers\etc\hosts'
$script:StartMarker = '# >>> GitHub One-Click Helper >>>'
$script:EndMarker = '# <<< GitHub One-Click Helper <<<'
$script:Colors = @{
    Background = [System.Drawing.Color]::FromArgb(13, 17, 23)
    Panel = [System.Drawing.Color]::FromArgb(22, 27, 34)
    Border = [System.Drawing.Color]::FromArgb(48, 54, 61)
    Text = [System.Drawing.Color]::FromArgb(240, 246, 252)
    Muted = [System.Drawing.Color]::FromArgb(139, 148, 158)
    Green = [System.Drawing.Color]::FromArgb(46, 160, 67)
    Blue = [System.Drawing.Color]::FromArgb(56, 139, 253)
    Red = [System.Drawing.Color]::FromArgb(248, 81, 73)
}

function Get-GitHubAddresses {
    $hosts = [ordered]@{
        'github.com' = $null
        'github.global.ssl.fastly.net' = $null
        'assets-cdn.github.com' = $null
    }

    foreach ($hostName in @($hosts.Keys)) {
        $record = Resolve-DnsName -Name $hostName -Type A -DnsOnly -ErrorAction Stop |
            Where-Object { $_.IPAddress } |
            Select-Object -First 1
        if (-not $record) {
            throw "DNS 查询没有返回 $hostName 的 IPv4 地址。"
        }
        $hosts[$hostName] = $record.IPAddress
    }

    return $hosts
}

function Get-ManagedHostsContent {
    $content = [System.IO.File]::ReadAllText($script:HostsPath)
    $escapedStart = [regex]::Escape($script:StartMarker)
    $escapedEnd = [regex]::Escape($script:EndMarker)
    $pattern = "(?ms)^$escapedStart\r?\n.*?^$escapedEnd\r?\n?"
    return [regex]::Replace($content, $pattern, '').TrimEnd()
}

function Set-StatusText {
    param(
        [string]$Title,
        [string]$Detail,
        [System.Drawing.Color]$Color
    )
    $statusTitle.Text = $Title
    $statusTitle.ForeColor = $Color
    $statusDetail.Text = $Detail
}

function Add-Log {
    param([string]$Message)
    $time = Get-Date -Format 'HH:mm:ss'
    $logBox.AppendText("[$time] $Message`r`n")
}

function Invoke-FlushDns {
    $output = & ipconfig.exe /flushdns 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "刷新 DNS 缓存失败：$output"
    }
    Add-Log 'DNS 缓存已刷新。'
}

function New-UiLabel {
    param(
        [string]$Text,
        [int]$Size = 10,
        [System.Drawing.Color]$Color = $script:Colors.Text,
        [bool]$Bold = $false
    )
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.ForeColor = $Color
    $label.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', $Size, $(if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }))
    $label.AutoSize = $true
    return $label
}

function New-UiButton {
    param(
        [string]$Text,
        [System.Drawing.Color]$BackColor,
        [int]$Width = 170
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Size = New-Object System.Drawing.Size($Width, 42)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $BackColor
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $button
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GitHub 一键助手'
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.ClientSize = New-Object System.Drawing.Size(900, 650)
$form.MinimumSize = New-Object System.Drawing.Size(820, 620)
$form.BackColor = $script:Colors.Background
$form.ForeColor = $script:Colors.Text
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$header = New-Object System.Windows.Forms.Panel
$header.Dock = [System.Windows.Forms.DockStyle]::Top
$header.Height = 122
$header.BackColor = $script:Colors.Panel
$form.Controls.Add($header)

$brand = New-UiLabel 'GITHUB  /  NETWORK TOOL' 9 $script:Colors.Green $true
$brand.Location = New-Object System.Drawing.Point(30, 20)
$header.Controls.Add($brand)
$title = New-UiLabel 'GitHub 一键助手' 22 $script:Colors.Text $true
$title.Location = New-Object System.Drawing.Point(28, 46)
$header.Controls.Add($title)
$subtitle = New-UiLabel '检测连接 · 更新 hosts · 刷新 DNS' 10 $script:Colors.Muted
$subtitle.Location = New-Object System.Drawing.Point(31, 86)
$header.Controls.Add($subtitle)

$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Location = New-Object System.Drawing.Point(30, 144)
$statusPanel.Size = New-Object System.Drawing.Size(840, 88)
$statusPanel.BackColor = $script:Colors.Panel
$form.Controls.Add($statusPanel)
$statusDot = New-Object System.Windows.Forms.Label
$statusDot.Text = '●'
$statusDot.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 18)
$statusDot.ForeColor = $script:Colors.Muted
$statusDot.AutoSize = $true
$statusDot.Location = New-Object System.Drawing.Point(19, 22)
$statusPanel.Controls.Add($statusDot)
$statusTitle = New-UiLabel '尚未检测' 12 $script:Colors.Text $true
$statusTitle.Location = New-Object System.Drawing.Point(53, 18)
$statusPanel.Controls.Add($statusTitle)
$statusDetail = New-UiLabel '点击“检测连接”查看 GitHub 域名解析及 HTTPS 端口状态。' 9 $script:Colors.Muted
$statusDetail.Location = New-Object System.Drawing.Point(54, 48)
$statusPanel.Controls.Add($statusDetail)

$sectionLabel = New-UiLabel '快速操作' 11 $script:Colors.Text $true
$sectionLabel.Location = New-Object System.Drawing.Point(31, 254)
$form.Controls.Add($sectionLabel)

$checkButton = New-UiButton '检测连接' $script:Colors.Blue 160
$checkButton.Location = New-Object System.Drawing.Point(30, 286)
$form.Controls.Add($checkButton)
$applyButton = New-UiButton '更新 hosts 并刷新' $script:Colors.Green 205
$applyButton.Location = New-Object System.Drawing.Point(202, 286)
$form.Controls.Add($applyButton)
$removeButton = New-UiButton '撤销本工具配置' ([System.Drawing.Color]::FromArgb(70, 76, 84)) 190
$removeButton.Location = New-Object System.Drawing.Point(417, 286)
$form.Controls.Add($removeButton)
$openButton = New-UiButton '打开 GitHub' ([System.Drawing.Color]::FromArgb(70, 76, 84)) 160
$openButton.Location = New-Object System.Drawing.Point(617, 286)
$form.Controls.Add($openButton)

$warning = New-UiLabel '提示：DNS 地址可能变化；本工具仅更新标记区块，修改前会备份 hosts。网络策略或运营商限制无法由 hosts 修改绕过。' 9 $script:Colors.Muted
$warning.Location = New-Object System.Drawing.Point(31, 346)
$warning.MaximumSize = New-Object System.Drawing.Size(830, 0)
$form.Controls.Add($warning)

$logTitle = New-UiLabel '运行记录' 10 $script:Colors.Text $true
$logTitle.Location = New-Object System.Drawing.Point(31, 385)
$form.Controls.Add($logTitle)
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(30, 411)
$logBox.Size = New-Object System.Drawing.Size(840, 185)
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$logBox.BackColor = $script:Colors.Panel
$logBox.ForeColor = $script:Colors.Text
$logBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($logBox)

$footer = New-UiLabel '需要管理员权限 · 数据来源：当前 DNS 查询' 8 $script:Colors.Muted
$footer.Location = New-Object System.Drawing.Point(31, 610)
$form.Controls.Add($footer)

$checkButton.Add_Click({
    $form.UseWaitCursor = $true
    $checkButton.Enabled = $false
    try {
        Add-Log '开始查询 GitHub DNS 记录…'
        $addresses = Get-GitHubAddresses
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $connect = $client.BeginConnect('github.com', 443, $null, $null)
            if (-not $connect.AsyncWaitHandle.WaitOne(3000, $false)) {
                throw '连接 github.com:443 超时。'
            }
            $client.EndConnect($connect)
        }
        finally {
            $client.Close()
        }

        foreach ($hostName in $addresses.Keys) {
            Add-Log ("{0,-34} {1}" -f $hostName, $addresses[$hostName])
        }
        $statusDot.ForeColor = $script:Colors.Green
        Set-StatusText 'HTTPS 端口可连接' 'DNS 查询正常，github.com 的 443 端口可连接。' $script:Colors.Green
        Add-Log '连接检测完成：github.com:443 可连接。'
    }
    catch {
        $statusDot.ForeColor = $script:Colors.Red
        Set-StatusText '连接检测未通过' $_.Exception.Message $script:Colors.Red
        Add-Log ("检测失败：{0}" -f $_.Exception.Message)
    }
    finally {
        $form.UseWaitCursor = $false
        $checkButton.Enabled = $true
    }
})

$applyButton.Add_Click({
    $form.UseWaitCursor = $true
    $applyButton.Enabled = $false
    try {
        Add-Log '正在从当前 DNS 获取最新 IPv4 地址…'
        $addresses = Get-GitHubAddresses
        $rows = foreach ($hostName in $addresses.Keys) {
            '{0} {1}' -f $addresses[$hostName], $hostName
        }
        $block = @($script:StartMarker) + $rows + @($script:EndMarker) -join [Environment]::NewLine
        $baseContent = Get-ManagedHostsContent
        $backupPath = '{0}.github-helper-backup-{1}' -f $script:HostsPath, (Get-Date -Format 'yyyyMMdd-HHmmss')
        Copy-Item -LiteralPath $script:HostsPath -Destination $backupPath -ErrorAction Stop
        $newContent = if ($baseContent) { $baseContent + [Environment]::NewLine + $block + [Environment]::NewLine } else { $block + [Environment]::NewLine }
        [System.IO.File]::WriteAllText($script:HostsPath, $newContent, [System.Text.Encoding]::Default)
        Invoke-FlushDns
        foreach ($hostName in $addresses.Keys) {
            Add-Log ("已配置 {0} -> {1}" -f $hostName, $addresses[$hostName])
        }
        Add-Log "原始 hosts 已备份至：$backupPath"
        $statusDot.ForeColor = $script:Colors.Green
        Set-StatusText 'hosts 已更新' '已写入工具专属区块并刷新 DNS；现在可以重新打开 GitHub。' $script:Colors.Green
    }
    catch {
        $statusDot.ForeColor = $script:Colors.Red
        Set-StatusText '更新失败' $_.Exception.Message $script:Colors.Red
        Add-Log ("更新失败：{0}" -f $_.Exception.Message)
    }
    finally {
        $form.UseWaitCursor = $false
        $applyButton.Enabled = $true
    }
})

$removeButton.Add_Click({
    $form.UseWaitCursor = $true
    $removeButton.Enabled = $false
    try {
        $baseContent = Get-ManagedHostsContent
        $content = [System.IO.File]::ReadAllText($script:HostsPath)
        if (-not $content.Contains($script:StartMarker)) {
            Add-Log '未发现本工具写入的 hosts 区块。'
            Set-StatusText '没有需要撤销的配置' 'hosts 中不存在本工具的标记区块。' $script:Colors.Muted
        }
        else {
            $backupPath = '{0}.github-helper-backup-{1}' -f $script:HostsPath, (Get-Date -Format 'yyyyMMdd-HHmmss')
            Copy-Item -LiteralPath $script:HostsPath -Destination $backupPath -ErrorAction Stop
            $cleanContent = if ($baseContent) { $baseContent + [Environment]::NewLine } else { '' }
            [System.IO.File]::WriteAllText($script:HostsPath, $cleanContent, [System.Text.Encoding]::Default)
            Invoke-FlushDns
            Add-Log "已移除工具区块；修改前备份：$backupPath"
            Set-StatusText '工具配置已撤销' '其他 hosts 内容已保留，DNS 缓存已刷新。' $script:Colors.Green
        }
        $statusDot.ForeColor = $statusTitle.ForeColor
    }
    catch {
        $statusDot.ForeColor = $script:Colors.Red
        Set-StatusText '撤销失败' $_.Exception.Message $script:Colors.Red
        Add-Log ("撤销失败：{0}" -f $_.Exception.Message)
    }
    finally {
        $form.UseWaitCursor = $false
        $removeButton.Enabled = $true
    }
})

$openButton.Add_Click({ Start-Process 'https://github.com' })
$form.Add_Shown({ Add-Log '助手已启动。所有 hosts 修改都会先生成备份文件。' })
[void]$form.ShowDialog()