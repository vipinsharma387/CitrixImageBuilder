# ===================== VARIABLES =====================
# CHANGE THESE THREE VALUES TO MATCH YOUR ENVIRONMENT
$existingGalleryName     = "Citrix_Gallery"          # Exact gallery name (include space if present)
$existingImageDefName    = "Win11_Optimized_Fslogix" # Exact image definition name that contains version 1.2.0
$sourceImageVersion      = "1.2.0"                   # Source version (already has VDA)
$galleryResourceGroup    = "RG-Citrix-Images"        # Resource group that contains the gallery


$imageResourceGroup = "CitrixImageBuilderRG"
$location           = "CentralIndia"
$identityName       = "aibIdentityCitrix"
$imageTemplateName  = "CitrixWin11-ImageTemplate"
$subscriptionID     = (Get-AzContext).Subscription.Id

# Get identity resource ID
$identity = Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName
$identityNameResourceId = $identity.Id

Write-Host "Creating Image Builder template for Windows 11 multi-session..."
Write-Host "Source: $existingGalleryName / $existingImageDefName / $sourceImageVersion"
Write-Host ""

# ===================== SOURCE (existing gallery image) =====================
$srcParams = @{
    SharedImageVersionSource = $true
    ImageVersionId = "/subscriptions/$subscriptionID/resourceGroups/$galleryResourceGroup/providers/Microsoft.Compute/galleries/$existingGalleryName/images/$existingImageDefName/versions/$sourceImageVersion"
}
$source = New-AzImageBuilderTemplateSourceObject @srcParams

# ===================== CUSTOMIZER 1: Remove Google Chrome =====================
$removeChromeParams = @{
    PowerShellCustomizer = $true
    Name                 = "RemoveGoogleChrome"
    RunElevated          = $true
    Inline               = @(
        "Write-Host 'Removing Google Chrome...'"
        # Uninstall Chrome if present (both 32-bit and 64-bit paths)
        "Get-Package -Name 'Google Chrome' -ErrorAction SilentlyContinue | Uninstall-Package -Force -ErrorAction SilentlyContinue"
        "Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' | ForEach-Object { Get-ItemProperty $_.PSPath } | Where-Object { $_.DisplayName -like '*Google Chrome*' } | ForEach-Object { Start-Process -FilePath 'msiexec.exe' -ArgumentList '/x', `$_.PSChildName, '/qn', '/norestart' -Wait -ErrorAction SilentlyContinue }"
        "Remove-Item -Path 'C:\Program Files\Google\Chrome' -Recurse -Force -ErrorAction SilentlyContinue"
        "Remove-Item -Path 'C:\Program Files (x86)\Google\Chrome' -Recurse -Force -ErrorAction SilentlyContinue"
        "Write-Host 'Google Chrome removal completed.'"
    )
}
$customizerRemoveChrome = New-AzImageBuilderTemplateCustomizerObject @removeChromeParams

# ===================== CUSTOMIZER 2: Windows Update =====================
$winUpdateParams = @{
    WindowsUpdateCustomizer = $true
    Name                    = "InstallWindowsUpdates"
    SearchCriterion         = "BrowseOnly=0 and IsInstalled=0"
    UpdateLimit             = 100
}
$customizerWinUpdate = New-AzImageBuilderTemplateCustomizerObject @winUpdateParams

# ===================== CUSTOMIZER 3: Basic Hardening =====================
$hardeningParams = @{
    PowerShellCustomizer = $true
    Name                 = "ApplyHardeningRules"
    RunElevated          = $true
    Inline               = @(
        "Write-Host 'Applying basic hardening rules...'"
        # Disable SMBv1
        "Set-SmbServerConfiguration -EnableSMB1Protocol `$false -Force -ErrorAction SilentlyContinue"
        "Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue"
        # Ensure Windows Firewall is enabled for all profiles
        "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True"
        # Disable unnecessary services (example: Xbox services)
        "Stop-Service -Name XblAuthManager,XblGameSave,XboxNetApiSvc -Force -ErrorAction SilentlyContinue"
        "Set-Service -Name XblAuthManager,XblGameSave,XboxNetApiSvc -StartupType Disabled -ErrorAction SilentlyContinue"
        # Create a marker file
        "New-Item -Path C:\ -Name 'HardeningApplied.txt' -ItemType File -Force"
        "Set-Content -Path C:\HardeningApplied.txt -Value 'Hardening rules applied by Azure Image Builder on $(Get-Date)'"
        "Write-Host 'Hardening completed.'"
    )
}
$customizerHardening = New-AzImageBuilderTemplateCustomizerObject @hardeningParams

# ===================== DISTRIBUTOR (publish new version to same gallery) =====================
$distParams = @{
    SharedImageDistributor = $true
    GalleryImageId = "/subscriptions/$subscriptionID/resourceGroups/$galleryResourceGroup/providers/Microsoft.Compute/galleries/$existingGalleryName/images/$existingImageDefName"
    RunOutputName          = "Win11CitrixOutput"
    ReplicationRegion      = $location
    ArtifactTag            = @{ "sourceVersion" = $sourceImageVersion; "customizations" = "RemoveChrome-Updates-Hardening" }
}
$distributor = New-AzImageBuilderTemplateDistributorObject @distParams

# ===================== CREATE TEMPLATE =====================
$templateParams = @{
    ImageTemplateName      = $imageTemplateName
    ResourceGroupName      = $imageResourceGroup
    Source                 = $source
    Customize              = $customizerRemoveChrome, $customizerWinUpdate, $customizerHardening
    Distribute             = $distributor
    Location               = $location
    UserAssignedIdentityId = $identityNameResourceId
}
New-AzImageBuilderTemplate @templateParams

Write-Host ""
Write-Host "=================================================="
Write-Host "Image template '$imageTemplateName' created successfully."
Write-Host "Next step: Start the build."
Write-Host "=================================================="