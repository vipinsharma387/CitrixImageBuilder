# ============================================================
# Citrix MCS Specialized Image Build Script (Simplified)
# Tasks: Windows Update + Temporary File Cleanup only
# ============================================================

# ------------------------------------------------------------
# BLOCK 1: Configuration (change these values)
# ------------------------------------------------------------
$SubscriptionId       = "d5a2bd94-cd2f-4df6-8755-35b5f6da3f17"

$GalleryResourceGroup = "RG-Citrix-Images"
$GalleryName          = "Citrix_Gallery"
$ImageDefinitionName  = "Win11_Optimized_Fslogix"
$SourceImageVersion   = "1.2.0"          # Source version
$NewImageVersion      = "1.3.0"          # New version to create

$TempResourceGroup    = "CitrixImageBuildRG"
$Location             = "CentralIndia"
$VmSize               = "Standard_B2ms"
$VmName               = "TempImageBuild-$(Get-Date -Format 'yyyyMMdd-HHmm')"

$NetworkResourceGroup = "RG-Hybrid-Lab"
$VNetName             = "vNet-HybridLab"    
$SubnetName           = "IdentitySubnet" 

$AdminUsername        = "ctxadmin"
$AdminPassword        = "Myhomelab@2026"

$LogFile              = "D:\Study\LAB2026\CitrixImageBuild\ImageBuild-$(Get-Date -Format 'yyyyMMdd-HHmm').log"

# Create log folder if needed
$logFolder = Split-Path $LogFile -Parent
if (-not (Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
}

Write-Host "Starting simplified image build process..."
"Starting image build - $(Get-Date)" | Out-File $LogFile

# ------------------------------------------------------------
# BLOCK 2: Connect to Azure
# ------------------------------------------------------------
Write-Host "Connecting to Azure..."
$currentContext = Get-AzContext
if (-not $currentContext -or $currentContext.Subscription.Id -ne $SubscriptionId) {
    Connect-AzAccount -Subscription $SubscriptionId
}
Set-AzContext -SubscriptionId $SubscriptionId
Write-Host "Connected."
"Connected to Azure" | Out-File $LogFile -Append

# ------------------------------------------------------------
# BLOCK 3: Validate source image
# ------------------------------------------------------------
Write-Host "Checking source image version $SourceImageVersion..."
$sourceVersion = Get-AzGalleryImageVersion -ResourceGroupName $GalleryResourceGroup `
                                           -GalleryName $GalleryName `
                                           -GalleryImageDefinitionName $ImageDefinitionName `
                                           -Name $SourceImageVersion
$sourceImageId = $sourceVersion.Id
Write-Host "Source image found."
"Source image validated" | Out-File $LogFile -Append

# ------------------------------------------------------------
# BLOCK 4: Get VNet and Subnet
# ------------------------------------------------------------
Write-Host "Getting network from $NetworkResourceGroup..."
$vnet = Get-AzVirtualNetwork -ResourceGroupName $NetworkResourceGroup -Name $VNetName
$subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName
Write-Host "Network ready."
"Network ready" | Out-File $LogFile -Append

# ------------------------------------------------------------
# BLOCK 5: Create temporary VM (compatible method)
# ------------------------------------------------------------
Write-Host "Creating temporary VM: $VmName"

$securePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($AdminUsername, $securePassword)

# Step 1: Create the Network Interface first
Write-Host "Creating network interface..."
$nic = New-AzNetworkInterface -Name "$VmName-nic" `
                              -ResourceGroupName $TempResourceGroup `
                              -Location $Location `
                              -SubnetId $subnet.Id `
                              -Force

# Step 2: Build VM configuration and attach the NIC
Write-Host "Building VM configuration..."
$vmConfig = New-AzVMConfig -VMName $VmName -VMSize $VmSize
$vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $VmName -Credential $credential -ProvisionVMAgent
$vmConfig = Set-AzVMSourceImage -VM $vmConfig -Id $sourceImageId
$vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
$vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable

# Step 3: Create the VM
Write-Host "Creating the VM..."
New-AzVM -ResourceGroupName $TempResourceGroup -Location $Location -VM $vmConfig -ErrorAction Stop

Write-Host "Temporary VM created."
"VM created" | Out-File $LogFile -Append

# ------------------------------------------------------------
# BLOCK 6: Wait until VM is running
# ------------------------------------------------------------
Write-Host "Waiting for VM to start..."
$timeout = 15
$startTime = Get-Date
do {
    Start-Sleep -Seconds 20
    $vmStatus = Get-AzVM -ResourceGroupName $TempResourceGroup -Name $VmName -Status
    $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus
    Write-Host "Current state: $powerState"
} while ($powerState -ne "VM running" -and ((Get-Date) - $startTime).TotalMinutes -lt $timeout)

if ($powerState -ne "VM running") {
    Write-Host "ERROR: VM did not start." -ForegroundColor Red
    exit
}
Write-Host "VM is running."
"VM running" | Out-File $LogFile -Append

# ------------------------------------------------------------
# BLOCK 7: Windows Update + Temporary File Cleanup
# ------------------------------------------------------------
Write-Host "Running Windows Update and temp file cleanup..."

$customizeScript = @'
Write-Output "Starting Windows Update and cleanup..."

# Install PSWindowsUpdate if missing
if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {
    Install-PackageProvider -Name NuGet -Force | Out-Null
    Install-Module PSWindowsUpdate -Force -Scope AllUsers
}
Import-Module PSWindowsUpdate

# Install Windows updates
Write-Output "Installing Windows updates..."
Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot

# Clean temporary files
Write-Output "Cleaning temporary files..."
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

Write-Output "Finished updates and cleanup."
'@

$tempScriptFile = "$env:TEMP\Customize.ps1"
$customizeScript | Out-File $tempScriptFile -Encoding UTF8

$result = Invoke-AzVMRunCommand -ResourceGroupName $TempResourceGroup `
                                -Name $VmName `
                                -CommandId "RunPowerShellScript" `
                                -ScriptPath $tempScriptFile

Write-Host "Customization result:"
$result.Value[0].Message
"Updates and cleanup done" | Out-File $LogFile -Append

# ------------------------------------------------------------
# BLOCK 8: Shut down the VM
# ------------------------------------------------------------
Write-Host "Shutting down the VM..."
Stop-AzVM -ResourceGroupName $TempResourceGroup -Name $VmName -Force
Write-Host "VM stopped."
"VM stopped" | Out-File $LogFile -Append

# ------------------------------------------------------------
# BLOCK 9: Capture new specialized image version
# ------------------------------------------------------------
Write-Host "Saving new image version $NewImageVersion to gallery..."
$vm = Get-AzVM -ResourceGroupName $TempResourceGroup -Name $VmName

New-AzGalleryImageVersion -ResourceGroupName $GalleryResourceGroup `
                          -GalleryName $GalleryName `
                          -GalleryImageDefinitionName $ImageDefinitionName `
                          -GalleryImageVersionName $NewImageVersion `
                          -Location $Location `
                          -SourceImageVMId $vm.Id

Write-Host "New image version created."
"New version created: $NewImageVersion" | Out-File $LogFile -Append

# ------------------------------------------------------------
# BLOCK 10: Cleanup temporary resources
# ------------------------------------------------------------
Write-Host "Cleaning up temporary VM..."
Remove-AzVM -ResourceGroupName $TempResourceGroup -Name $VmName -Force -ErrorAction SilentlyContinue
Remove-AzNetworkInterface -ResourceGroupName $TempResourceGroup -Name "$VmName-nic" -Force -ErrorAction SilentlyContinue
Get-AzDisk -ResourceGroupName $TempResourceGroup | Where-Object { $_.Name -like "*$VmName*" } | Remove-AzDisk -Force -ErrorAction SilentlyContinue

Write-Host "Cleanup finished."
"Cleanup finished" | Out-File $LogFile -Append

# ------------------------------------------------------------
# BLOCK 11: Finish
# ------------------------------------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Done! New specialized image version: $NewImageVersion" -ForegroundColor Green
Write-Host "Log file: $LogFile" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green