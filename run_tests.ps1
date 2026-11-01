$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$buildDirectory = Join-Path $env:TEMP "cmod-rv32imac-tests"
New-Item -ItemType Directory -Force -Path $buildDirectory | Out-Null

$commonSources = @(
    (Join-Path $PSScriptRoot "rv32imac_pkg.sv"),
    (Join-Path $PSScriptRoot "rv32c_decoder.sv"),
    (Join-Path $PSScriptRoot "rv32_muldiv.sv"),
    (Join-Path $PSScriptRoot "sv32_mmu.sv"),
    (Join-Path $PSScriptRoot "rv32imac_core.sv")
)

function Invoke-IcarusTest {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Top,
        [Parameter(Mandatory = $true)]
        [string[]] $Sources
    )

    $output = Join-Path $buildDirectory "$Top.vvp"
    & iverilog -g2012 -s $Top -o $output $Sources
    if ($LASTEXITCODE -ne 0) {
        throw "Icarus compilation failed for $Top"
    }

    & vvp $output
    if ($LASTEXITCODE -ne 0) {
        throw "Simulation failed for $Top"
    }
}

Invoke-IcarusTest "rv32_muldiv_tb" @(
    (Join-Path $PSScriptRoot "rv32_muldiv.sv"),
    (Join-Path $PSScriptRoot "rv32_muldiv_tb.sv")
)
Invoke-IcarusTest "rv32c_decoder_tb" @(
    (Join-Path $PSScriptRoot "rv32c_decoder.sv"),
    (Join-Path $PSScriptRoot "rv32c_decoder_tb.sv")
)
Invoke-IcarusTest "sv32_mmu_tb" @(
    (Join-Path $PSScriptRoot "rv32imac_pkg.sv"),
    (Join-Path $PSScriptRoot "sv32_mmu.sv"),
    (Join-Path $PSScriptRoot "sv32_mmu_tb.sv")
)
Invoke-IcarusTest "rv32imac_core_tb" (
    $commonSources + (Join-Path $PSScriptRoot "rv32imac_core_tb.sv")
)
Invoke-IcarusTest "rv32imac_privilege_tb" (
    $commonSources + (Join-Path $PSScriptRoot "rv32imac_privilege_tb.sv")
)

Invoke-IcarusTest "zulu_sdram_controller_tb" @(
    (Join-Path $PSScriptRoot "zulu_a7\rtl\zulu_sdram_controller.sv"),
    (Join-Path $PSScriptRoot "zulu_a7\rtl\zulu_sdram_controller_tb.sv")
)

Write-Host "All RV32IMAC tests passed."
