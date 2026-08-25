param([string]$Hook)

if ([string]::IsNullOrWhiteSpace($Hook)) { exit 0 }

$lastId = [long]0

function Notify([string]$Title, [string]$Desc, [int]$Color) {
    try {
        $payload = @{
            embeds = @(@{
                title       = $Title
                description = $Desc
                color       = $Color
                timestamp   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
                footer      = @{ text = "RDP Connection Engine" }
            })
        } | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Uri $Hook -Method Post -Body $payload `
            -ContentType "application/json; charset=utf-8" -EA Stop | Out-Null
    } catch {}
}

while ($true) {
    try {
        $evts = Get-WinEvent `
            -LogName "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational" `
            -MaxEvents 8 -EA SilentlyContinue |
            Where-Object { $_.Id -in 21, 22, 23, 24 }

        foreach ($ev in $evts) {
            if ($ev.RecordId -le $lastId) { continue }
            $lastId = $ev.RecordId
            $user = try { $ev.Properties[0].Value } catch { "Unknown" }
            $cip  = try { $ev.Properties[2].Value } catch { "N/A" }
            $t    = $ev.TimeCreated.ToString("HH:mm:ss")

            switch ($ev.Id) {
                21 { Notify "🟢 RDP Connected"    "User: $user`nClient IP: $cip`nTime: $t" 3066993  }
                22 { Notify "🔄 RDP Reconnected"  "User: $user`nClient IP: $cip`nTime: $t" 5793266  }
                23 { Notify "🟡 RDP Disconnected" "User: $user`nTime: $t"                 16744272 }
                24 { Notify "🔴 RDP Session Reset" "User: $user`nTime: $t"                15158332 }
            }
        }
    } catch {}
    Start-Sleep -Seconds 12
}
