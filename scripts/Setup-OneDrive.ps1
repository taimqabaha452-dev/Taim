Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "        OneDrive Setup for GitHub         " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$rcloneUrl = "https://downloads.rclone.org/v1.65.2/rclone-v1.65.2-windows-amd64.zip"
$tempZip = "$env:TEMP\rclone_setup.zip"
$extractPath = "$env:TEMP\rclone_setup"
$rcloneExe = "$extractPath\rclone-v1.65.2-windows-amd64\rclone.exe"

Write-Host "[1] Downloading rclone..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $rcloneUrl -OutFile $tempZip -UseBasicParsing
Expand-Archive -Path $tempZip -DestinationPath $extractPath -Force

Write-Host "[2] Opening browser for login..." -ForegroundColor Yellow
Write-Host "Please login with your Microsoft account and accept the permissions." -ForegroundColor Yellow
Start-Sleep -Seconds 3

& $rcloneExe config create onedrive onedrive config_is_local true
$confPath = & $rcloneExe config file | Select-String "rclone.conf" | ForEach-Object { $_.Line.Split()[-1] }

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "SUCCESS! Please copy the code below:" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

Get-Content $confPath

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "Copy everything between [onedrive] and the end," -ForegroundColor Yellow
Write-Host "and put it in GitHub Secrets as RCLONE_CONF" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
pause
