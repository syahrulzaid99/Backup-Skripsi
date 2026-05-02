# Menjalankan Scrcpy jika belum terbuka
if (!(Get-Process scrcpy -ErrorAction SilentlyContinue)) {
    Write-Host "Memulai Scrcpy..." -ForegroundColor Cyan
    Start-Process "C:\Users\syahr\chocolatey\bin\scrcpy.exe"
} else {
    Write-Host "Scrcpy sudah berjalan." -ForegroundColor Green
}

# Menjalankan Flutter
Write-Host "Memulai Flutter Run..." -ForegroundColor Yellow
flutter run
