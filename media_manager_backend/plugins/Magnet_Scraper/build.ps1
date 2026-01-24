# Magnet_Scraper Plugin Build Script

Write-Host "Building Magnet_Scraper plugin..." -ForegroundColor Cyan

# Build
cargo build --release

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful!" -ForegroundColor Green
    
    # Copy to plugin directory
    Write-Host "Copying executable..." -ForegroundColor Cyan
    
    # Try different possible locations for the executable
    $possiblePaths = @(
        "target\release\Magnet_Scraper.exe",
        "target\x86_64-pc-windows-msvc\release\Magnet_Scraper.exe"
    )
    
    $found = $false
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Copy-Item $path "Magnet_Scraper.exe" -Force
            Write-Host "Copied from $path" -ForegroundColor Green
            $found = $true
            break
        }
    }
    
    if (-not $found) {
        Write-Host "Error: Could not find Magnet_Scraper.exe in expected locations" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Plugin build complete!" -ForegroundColor Green
} else {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}
