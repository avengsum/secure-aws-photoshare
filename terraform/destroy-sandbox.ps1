$ErrorActionPreference = "Stop"

$TerraformDir = $PSScriptRoot
$DisposableVars = Join-Path $TerraformDir "terraform.disposable.tfvars"

if (-not (Test-Path -LiteralPath $DisposableVars)) {
    throw "Missing terraform.disposable.tfvars. Copy terraform.disposable.tfvars.example to terraform.disposable.tfvars first."
}

Push-Location $TerraformDir
try {
    Write-Host "This removes the disposable PhotoShare environment, including database data, photos, ECR images, and audit objects." -ForegroundColor Yellow
    $confirmation = Read-Host "Type DESTROY-PHOTOSHARE to continue"
    if ($confirmation -ne "DESTROY-PHOTOSHARE") {
        throw "Teardown cancelled."
    }

    Write-Host "Applying disposable-mode changes so deletion protection is explicitly disabled..." -ForegroundColor Cyan
    terraform apply "-var-file=$DisposableVars"
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform apply failed. Destroy was not started."
    }

    Write-Host "Destroying the environment..." -ForegroundColor Cyan
    terraform destroy "-var-file=$DisposableVars"
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform destroy failed. Check the Terraform error above and rerun after fixing it."
    }
}
finally {
    Pop-Location
}
