# ===================== VARIABLES =====================
# CHANGE THESE THREE VALUES IF NEEDED
$existingGalleryName     = "Citrix_Gallery"          # Exact name of your existing gallery
$existingImageDefName    = "Win11_Optimized_Fslogix"    # Exact name of the image definition that has version 1.2.0
$sourceImageVersion      = "1.2.0"                   # The version you want to use as the base

$imageResourceGroup = "CitrixImageBuilderRG"
$location           = "CentralIndia"
$identityName       = "aibIdentityCitrix"
$imageRoleDefName   = "AIB-Citrix-Image-Creation-Role"
$subscriptionID     = (Get-AzContext).Subscription.Id

Write-Host "Subscription ID : $subscriptionID"
Write-Host "Resource Group  : $imageResourceGroup"
Write-Host "Location        : $location"
Write-Host "Using Gallery   : $existingGalleryName"
Write-Host "Source Version  : $sourceImageVersion"
Write-Host ""

# ===================== RESOURCE GROUP =====================
Write-Host "Creating resource group..."
New-AzResourceGroup -Name $imageResourceGroup -Location $location -Force | Out-Null

# ===================== MANAGED IDENTITY =====================
Write-Host "Creating user-assigned managed identity..."
New-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName -Location $location | Out-Null

$identity = Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName
$identityNameResourceId = $identity.Id
$identityNamePrincipalId = $identity.PrincipalId

Write-Host "Identity created."
Write-Host "Identity Resource ID : $identityNameResourceId"
Write-Host "Identity Principal ID: $identityNamePrincipalId"
Write-Host ""

# ===================== ROLE ASSIGNMENT (Contributor for learning) =====================
Write-Host "Assigning Contributor role to the managed identity..."
New-AzRoleAssignment -ObjectId $identityNamePrincipalId `
                     -RoleDefinitionName "Contributor" `
                     -Scope "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup"

Write-Host "Role assigned."