param(
    [Parameter(Mandatory = $true)]
    [string]$OpenSbiRoot,

    [string]$CrossCompile = "riscv-none-elf-",
    [switch]$UseLlvm,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "build")
)

$ErrorActionPreference = "Stop"

$makeCommand = Get-Command make -ErrorAction SilentlyContinue
if (-not $makeCommand) {
    throw "GNU make was not found. Install GNU make and add it to PATH."
}

$dtcCommand = Get-Command dtc -ErrorAction SilentlyContinue
if (-not $dtcCommand) {
    throw "Device Tree Compiler (dtc) was not found. Add Vivado's bin directory or another dtc installation to PATH."
}

$openSbiPath = (Resolve-Path $OpenSbiRoot).Path
$dtsPath = (Resolve-Path (Join-Path $PSScriptRoot "..\dts\zulu_a7_rv32imac.dts")).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$outputPath = (Resolve-Path $OutputDirectory).Path
$dtbPath = Join-Path $outputPath "zulu_a7_rv32imac.dtb"
$openSbiBuildPath = Join-Path $outputPath "opensbi"
$makeDtbPath = $dtbPath.Replace("\", "/")
$makeOpenSbiBuildPath = $openSbiBuildPath.Replace("\", "/")
$windowsMakePath = (Join-Path $PSScriptRoot "windows-opensbi.mk").Replace("\", "/")
$openSbiMakePath = (Join-Path $openSbiPath "Makefile").Replace("\", "/")

& $dtcCommand.Source -I dts -O dtb -o $dtbPath $dtsPath
if ($LASTEXITCODE -ne 0) {
    throw "dtc failed with exit code $LASTEXITCODE."
}

$makeArguments = @("-C", $openSbiPath)
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    $makeArguments += @("-f", $openSbiMakePath, "-f", $windowsMakePath)
}
$makeArguments += @(
    "O=$makeOpenSbiBuildPath",
    "PLATFORM=generic",
    "PLATFORM_RISCV_XLEN=32",
    "PLATFORM_RISCV_ISA=rv32imac_zicsr_zifencei",
    "PLATFORM_RISCV_ABI=ilp32",
    "FW_TEXT_START=0x80000000",
    "FW_JUMP_ADDR=0x80400000",
    "FW_JUMP_FDT_ADDR=0x83e00000",
    "FW_FDT_PATH=$makeDtbPath"
)

if ($UseLlvm) {
    $makeArguments += "LLVM=1"
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        # OpenSBI's /dev/null probe is not valid for native Windows LLVM.
        $makeArguments += "OPENSBI_LD_PIE=y"
        $makeArguments += "platform-cflags-y=-Wno-error=sometimes-uninitialized"
    }
} else {
    $makeArguments += "CROSS_COMPILE=$CrossCompile"
}

& $makeCommand.Source @makeArguments
if ($LASTEXITCODE -ne 0) {
    throw "OpenSBI build failed with exit code $LASTEXITCODE."
}

$firmwareDirectory = Join-Path $openSbiBuildPath "platform\generic\firmware"
foreach ($fileName in @("fw_jump.bin", "fw_jump.elf")) {
    $sourcePath = Join-Path $firmwareDirectory $fileName
    if (-not (Test-Path $sourcePath)) {
        throw "Expected OpenSBI output was not produced: $sourcePath"
    }
    Copy-Item -Force $sourcePath (Join-Path $outputPath $fileName)
}

Write-Host "OpenSBI RV32IMAC firmware and DTB are in $outputPath"
