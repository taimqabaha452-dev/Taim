param(
    [string]$Token,
    [string]$ChannelId,
    [string]$Webhook,
    [string]$BoreLog = "C:\bore\bore.log"
)

$botHeaders = @{
    Authorization  = "Bot $Token"
    "Content-Type" = "application/json"
}

function Log([string]$Level, [string]$Msg) {
    $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$t][$Level] $Msg"
}

function Send-ChannelMsg([string]$Content, $Embed = $null) {
    try {
        $body = @{ content = $Content }
        if ($Embed) { $body.embeds = @($Embed) }
        Invoke-RestMethod "https://discord.com/api/v10/channels/$ChannelId/messages" `
            -Method Post -Headers $botHeaders `
            -Body ($body | ConvertTo-Json -Depth 10) `
            -ContentType "application/json; charset=utf-8" -EA Stop | Out-Null
    } catch { Log "WARN" "Send-ChannelMsg: $_" }
}

function Send-DiscordFile([string]$FilePath, [string]$Caption = "") {
    try {
        if (-not (Test-Path $FilePath)) { return }
        $boundary = [System.Guid]::NewGuid().ToString()
        $LF = "`r`n"
        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        $fileName = [System.IO.Path]::GetFileName($FilePath)

        $bodyStart = "--$boundary$LF" +
                     "Content-Disposition: form-data; name=`"content`"$LF$LF" +
                     "$Caption$LF" +
                     "--$boundary$LF" +
                     "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"$LF" +
                     "Content-Type: image/png$LF$LF"
        $bodyEnd = "$LF--$boundary--$LF"

        $startBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyStart)
        $endBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyEnd)

        $req = [System.Net.HttpWebRequest]::Create("https://discord.com/api/v10/channels/$ChannelId/messages")
        $req.Method = "POST"
        $req.Headers["Authorization"] = "Bot $Token"
        $req.ContentType = "multipart/form-data; boundary=$boundary"
        $req.ContentLength = $startBytes.Length + $fileBytes.Length + $endBytes.Length

        $stream = $req.GetRequestStream()
        $stream.Write($startBytes, 0, $startBytes.Length)
        $stream.Write($fileBytes, 0, $fileBytes.Length)
        $stream.Write($endBytes, 0, $endBytes.Length)
        $stream.Flush()
        $stream.Close()

        $resp = $req.GetResponse()
        $resp.Close()
        Log "OK" "File sent to Discord: $fileName"
    } catch { Log "WARN" "Send-DiscordFile error: $_" }
}

function Capture-Screen {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $screenPath = "C:\screenshot.png"
        $bmp.Save($screenPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bmp.Dispose()
        return $screenPath
    } catch {
        Log "WARN" "Capture-Screen error: $_"
        return $null
    }
}

function Get-BorePort {
    $c = Get-Content $BoreLog -Raw -EA SilentlyContinue
    if ($c -match "listening at bore\.pub:(\d+)") { return $Matches[1] }
    if ($c -match "remote_port.*?(\d{4,5})") { return $Matches[1] }
    return "unknown"
}

function Get-PinggyEndpoint {
    $c = Get-Content "C:\pinggy.log" -Raw -EA SilentlyContinue
    if ($c -match "(?:tcp://)?([a-zA-Z0-9\.\-_]+\.pinggy\.io):(\d+)") {
        return "$($Matches[1]):$($Matches[2])"
    }
    return "inactive"
}

function Get-TailscaleIP {
    try {
        $tsExe = "$env:ProgramFiles\Tailscale\tailscale.exe"
        $raw = ((& $tsExe ip -4 2>&1) -join " ").Trim()
        if ($raw -match "(\d+\.\d+\.\d+\.\d+)") { return $Matches[1] }
    } catch {}
    return "N/A"
}

function Optimize-SystemMemory {
    try {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        Get-Process | ForEach-Object {
            try {
                $_.MinWorkingSet = [System.IntPtr]::Zero
                $_.MaxWorkingSet = [System.IntPtr]::Zero
            } catch {}
        }
        Remove-Item "$env:TEMP\*" -Recurse -Force -EA SilentlyContinue
        Remove-Item "C:\Windows\Temp\*" -Recurse -Force -EA SilentlyContinue
        return $true
    } catch { return $false }
}

function Get-StatusEmbed {
    $bp     = Get-BorePort
    $pinggy = Get-PinggyEndpoint
    $ti     = Get-TailscaleIP
    $rdpOk  = try { (Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server').fDenyTSConnections -eq 0 } catch { $false }

    $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    $os  = Get-CimInstance Win32_OperatingSystem
    $freeRamMB = [math]::Round($os.FreePhysicalMemory / 1024, 0)
    $totalRamMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)

    return @{
        title  = "🚀 High-Performance RDP Server - Status"
        color  = if ($rdpOk) { 3066993 } else { 15158332 }
        fields = @(
            @{ name = "🌐 bore.pub"        ; value = "``mstsc /v:bore.pub:$bp``"       ; inline = $true  }
            @{ name = "⚡ Pinggy (مجاني)" ; value = "``mstsc /v:$pinggy``"            ; inline = $true  }
            @{ name = "🔗 Tailscale IP"    ; value = "``${ti}:3389``"                   ; inline = $true  }
            @{ name = "👤 User / Pass"     ; value = "``rdpuser`` / ``king2011``"      ; inline = $true  }
            @{ name = "💻 CPU Load"        ; value = "$cpu%"                           ; inline = $true  }
            @{ name = "🧠 RAM Free"        ; value = "$freeRamMB MB / $totalRamMB MB"  ; inline = $true  }
            @{ name = "🖥️ RDP Service"    ; value = if ($rdpOk) { "✅ Online" } else { "❌ Offline" }; inline = $true }
            @{ name = "🛡️ Optimization"    ; value = "Ultra Gaming Low-Latency Mode"   ; inline = $true }
        )
        footer    = @{ text = "Auto-refreshes | Turbo RDP Engine" }
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    }
}

Log "INFO" "Sending control panel..."
Start-Sleep -Seconds 5

$panel = @{
    title       = "⚡ Turbo RDP Node Control Panel"
    description = "الخادم يعمل بأقصى أداء مع مسارات اتصال مجانية 100% وبدون انقطاع"
    color       = 5763719
    fields      = @(
        @{ name = "🌐 bore.pub"        ; value = "``mstsc /v:bore.pub:$(Get-BorePort)``"      ; inline = $false }
        @{ name = "⚡ Pinggy (مجاني)" ; value = "``mstsc /v:$(Get-PinggyEndpoint)``"         ; inline = $false }
        @{ name = "🔗 Tailscale"       ; value = "``$(Get-TailscaleIP):3389``"                ; inline = $true  }
        @{ name = "👤 بيانات الدخول"    ; value = "User: ``rdpuser`` | Pass: ``king2011``"     ; inline = $false }
        @{ name = "📋 الأوامر المدعومة" ; value = "``!status`` حالة الخادم والذاكرة`n``!screen`` لقطة شاشة حية للشاشة`n``!clean`` تحرير الرام وتسريع النظام`n``!bore`` إعادة تشغيل نفق bore`n``!pinggy`` إعادة تشغيل نفق pinggy`n``!restart`` إعادة تشغيل RDP`n``!cmd <امر>`` تنفيذ أمر PowerShell"; inline = $false }
    )
    footer    = @{ text = "TaimKing Ultra RDP" }
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
}
Send-ChannelMsg "" $panel
Log "INFO" "Control panel sent!"

$lastId = $null
try {
    $init = Invoke-RestMethod "https://discord.com/api/v10/channels/$ChannelId/messages?limit=1" `
        -Headers $botHeaders -EA Stop
    if ($init) { $lastId = $init[0].id }
} catch {}

Log "INFO" "Bot listening for commands on channel $ChannelId..."

while ($true) {
    try {
        $params   = if ($lastId) { "?after=$lastId&limit=10" } else { "?limit=1" }
        $messages = Invoke-RestMethod "https://discord.com/api/v10/channels/$ChannelId/messages$params" `
            -Headers $botHeaders -EA Stop

        foreach ($msg in ($messages | Sort-Object { [long]$_.id })) {
            if ($msg.author.bot -eq $true) { continue }
            $lastId = $msg.id
            $rawCmd = $msg.content.Trim()
            $cmd    = $rawCmd.ToLower()
            Log "EVENT" "Command from $($msg.author.username): $rawCmd"

            if ($cmd -eq "!status") {
                Send-ChannelMsg "" (Get-StatusEmbed)
            }
            elseif ($cmd -eq "!screen" -or $cmd -eq "!screenshot") {
                Send-ChannelMsg "📸 جاري التقاط شاشة الخادم..."
                $sImg = Capture-Screen
                if ($sImg) {
                    Send-DiscordFile $sImg "🖥️ لقطة شاشة حية لخادم RDP"
                } else {
                    Send-ChannelMsg "❌ تعذر التقاط لقطة الشاشة (ربما لا توجد جلسة سطح مكتب نشطة)."
                }
            }
            elseif ($cmd -eq "!clean") {
                Send-ChannelMsg "🧹 جاري تفريغ الذاكرة المؤقتة وتنظيف النظام..."
                Optimize-SystemMemory | Out-Null
                Send-ChannelMsg "✅ تم تفريغ الرام ومسح الملفات المؤقتة بنجاح!"
            }
            elseif ($cmd -eq "!info" -or $cmd -eq "!tunnels") {
                $bp     = Get-BorePort
                $pinggy = Get-PinggyEndpoint
                $ti     = Get-TailscaleIP
                Send-ChannelMsg "**📡 مسارات الاتصال النشطة المجانية:**`n🌐 bore.pub: ``mstsc /v:bore.pub:$bp```n⚡ Pinggy: ``mstsc /v:$pinggy```n🔗 Tailscale: ``${ti}:3389```n👤 User: ``rdpuser`` | 🔑 Pass: ``king2011``"
            }
            elseif ($cmd -eq "!restart") {
                Send-ChannelMsg "🔄 جاري إعادة تشغيل خدمة RDP..."
                try {
                    Restart-Service TermService -Force -EA Stop
                    Send-ChannelMsg "✅ تم إعادة تشغيل خدمة RDP بنجاح!"
                } catch {
                    Send-ChannelMsg "❌ فشل إعادة التشغيل: $_"
                }
            }
            elseif ($cmd -eq "!bore") {
                Send-ChannelMsg "🔄 جاري إعادة تشغيل نفق bore.pub..."
                Stop-Process -Name "bore" -Force -EA SilentlyContinue
                Start-Sleep -Seconds 2
                Remove-Item $BoreLog -EA SilentlyContinue
                Start-Process "C:\bore\bore.exe" -ArgumentList "local","3389","--to","bore.pub" `
                    -RedirectStandardOutput $BoreLog -NoNewWindow
                Start-Sleep -Seconds 8
                $newPort = Get-BorePort
                Send-ChannelMsg "✅ bore.pub restarted! New: ``mstsc /v:bore.pub:$newPort``"
            }
            elseif ($cmd -eq "!pinggy") {
                Send-ChannelMsg "🔄 جاري إعادة تشغيل نفق Pinggy..."
                Stop-Process -Name "ssh" -Force -EA SilentlyContinue
                Start-Sleep -Seconds 2
                Remove-Item "C:\pinggy.log" -EA SilentlyContinue
                Start-Process "ssh.exe" `
                    -ArgumentList "-p","443","-o","StrictHostKeyChecking=no","-o","ServerAliveInterval=15","-R","0:localhost:3389","-N","tcp@a.pinggy.io" `
                    -RedirectStandardOutput "C:\pinggy.log" -RedirectStandardError "C:\pinggy-err.log" -NoNewWindow
                Start-Sleep -Seconds 8
                $newPinggy = Get-PinggyEndpoint
                Send-ChannelMsg "✅ Pinggy restarted! New: ``mstsc /v:$newPinggy``"
            }
            elseif ($cmd.StartsWith("!cmd ")) {
                $toExec = $rawCmd.Substring(5).Trim()
                Send-ChannelMsg "⚙️ جاري تنفيذ: ``$toExec``..."
                try {
                    $out = powershell.exe -NoProfile -Command $toExec 2>&1 | Out-String
                    if ($out.Length -gt 1900) { $out = $out.Substring(0, 1900) + "... [Truncated]" }
                    if ([string]::IsNullOrWhiteSpace($out)) { $out = "No output" }
                    Send-ChannelMsg "```$out```"
                } catch {
                    Send-ChannelMsg "❌ خطأ أثناء التنفيذ: $_"
                }
            }
            elseif ($cmd -eq "!help") {
                Send-ChannelMsg "**📋 قائمة الأوامر المطورة:**`n``!status`` - فحص الأداء والرام والحالة`n``!screen`` - التقاط لقطة شاشة حية للديسكتوب`n``!clean`` - تفريغ الرام وتسريع الخادم`n``!tunnels`` - فحص كل مسارات الاتصال المجانية`n``!bore`` - إعادة تشغيل نفق bore`n``!pinggy`` - إعادة تشغيل نفق Pinggy`n``!restart`` - إعادة تشغيل خدمة RDP`n``!cmd <command>`` - تنفيذ كود PowerShell عن بعد"
            }
        }
    } catch { }

    Start-Sleep -Seconds 4
}
