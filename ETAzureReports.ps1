function Get-ETAzVMInfo
{
    Param(
        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [PSObject]
        $VM
    )

    # Create PSObject and print out VM Info.
    [PSCustomObject]@{
		VMName = $VM.Name
		ResourceGroup = $VM.ResourceGroupName
		Location = $VM.Location
		Size = $VM.HardwareProfile.VmSize
		OperatingSystem = $VM.StorageProfile.ImageReference.Sku
		ProvisioningState = $VM.ProvisioningState
	}
}

function Get-ETAzNIC
{
    Param(
        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [PSObject]
        $VM
    )

	# Create PSObject of NICs for VM.
	$VMNICPull = $VM.NetworkProfile.NetworkInterfaces | Select-Object ID
	foreach ($nic in $VMNICPull)
	{
        $NICResourceName = $nic.Id.Split('/')[8]
		$NICInfo = Get-AzNetworkInterface -Name $NICResourceName
		$NICIPInfo = $NICInfo | Get-AzNetworkInterfaceIpConfig | Select-Object ProvisioningState,PrivateIpAddress,PrivateIpAllocationMethod
		[PSCustomObject]@{
			Name = $NICResourceName
			IPAddress = $NICIPInfo.PrivateIPAddress
			IPAllocation = $NICIPInfo.PrivateIpAllocationMethod
			State = $NICInfo.ProvisioningState
		}
	}
}

function Get-ETAzPIP
{
    Param(
        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [PSObject]
        $VM
    )

    # Create PSObject of PIPs for VM.
    $PublicIPPull = Get-AzPublicIpAddress -ResourceGroupName $VM.ResourceGroupName | Where-Object { $_.IpConfiguration.Id -like "*$Resource*" }
    foreach ($pip in $PublicIPPull)
    {
    	[PSCustomObject]@{
		    Name = $pip.Name
		    IPAddress = $pip.IPAddress
		    IPAllocation = $pip.PublicIpAllocationMethod
		    State = $pip.ProvisioningState
	    }        
    }
}  

function Get-ETAzDisks
{
    Param(
        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [PSObject]
        $VM
    )

    # Create PSObject of Disks for VM.
	$VMDisks = @()
	$VMDisks += $VM.StorageProfile.OsDisk | Select-Object Name
	$VMDisks += $VM.StorageProfile.DataDisks | Select-Object Name
	foreach ($disk in $VMDisks)
	{
		$DiskInfo = Get-AzDisk -DiskName $disk.Name
		[PsCustomObject]@{
			Name = $disk.Name
			DiskSize = $Diskinfo.DiskSizeGB
            Tier = $DiskInfo.Sku.Name
            IOPS = $DiskInfo.DiskIOPSReadWrite
            MBPS = $DiskInfo.DiskMBpsReadWrite
		}
	}
}

function Get-ETAzDatabase
{
    Param(
        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [String]
        $ServerName,

        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [String]
        $ResourceGroup,

        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [String]
        $DatabaseName
    )

	# Create PSObject of SQL Database.
	$Database = (Get-AzSqlDatabase -ServerName $ServerName -ResourceGroupName $ResourceGroup).Where{ $_.DatabaseName -eq $DatabaseName }
    [PSCustomObject]@{
        DatabaseName = $Database.DatabaseName
        SQLServer = $Database.ServerName
        ResourceGroup = $Database.ResourceGroupName
        Location = $Database.Location
        SKU = $Database.SKUName + ' ' + $Database.CurrentServiceObjectiveName + ': ' + $Database.Capacity + ' DTUs'
        BackupRedundency = $Database.BackupStorageRedundancy
        EarliestBackup = $Database.EarliestRestoreDate
    }
}

function Get-ETAzBackup
{
    # Create PSObject of backups for VM.
    # ------Variables--------------#
    $retentionDays = 730
    $vaultName = "ET-Pihole-Vault"
    $vaultResourceGroup = "ET-Pihole-01"
    $friendlyName = "$VMName"
    #------------------------------#

    $vault = Get-AzRecoveryServicesVault -ResourceGroupName $vaultResourceGroup -Name $vaultName
    $Container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -Status Registered -FriendlyName $friendlyName -VaultId $vault.ID
    $BackupItem = Get-AzRecoveryServicesBackupItem -Container $Container -WorkloadType AzureVM -VaultId $vault.ID
 
    $startingPoint = -25
    $finishingPoint = 0
    $jobsArray = @()
 
    Do {
        $StartDate = (Get-Date).AddDays($startingPoint)
        $EndDate = (Get-Date).AddDays($finishingPoint)
        $RP = Get-AzRecoveryServicesBackupRecoveryPoint -Item $BackupItem -StartDate $Startdate.ToUniversalTime() -EndDate $Enddate.ToUniversalTime() -VaultId $vault.ID
        $jobsArray += $RP
        $startingPoint = $startingPoint - 25
        $finishingPoint = $finishingPoint -25
    } until ($startingPoint -le -($retentionDays))
    $jobsArray | Format-Table -AutoSize -Property RecoveryPointid, RecoveryPointTime, RecoveryPointType 
}

Function Get-ETAzReports
{
    Param
    (
        [parameter(Mandatory=$False)]
        [string]
        $Resource,

        [parameter(Mandatory=$False)]
        [string]
        $ResourceGroup,

        [parameter(Mandatory=$False)]
        [string]
        $Subscription,

        [parameter(Mandatory=$False)]
        [string]
        $ResourceID
    )

    $ErrorActionPreference = Stop

    Clear-Host

    # Validate what input user gave us and then create the PSObject we will use to pull information on the resource.
    if($Resource -and $ResourceGroup -and $Subscription)
    {
        $AccountInfo = [PSCustomObject]@{
            Subscription = $Subscription
            ResourceGroup = $ResourceGroup
            Resource = $Resource
        }
    }
    elseif($ResourceID)
    {
        if($ResourceID.Split('/')[9].Trim('"') -eq 'DATABASES')
        {
            $AccountInfo = [PSCustomObject]@{
                Subscription = $ResourceID.Split('/')[2]
                ResourceGroup = $ResourceID.Split('/')[4]
                Resource = $ResourceID.Split('/')[8].Trim('"')
                Database = $ResourceID.Split('/')[10].Trim('"')
            }  
        }
        else
        {
            $AccountInfo = [PSCustomObject]@{
                Subscription = $ResourceID.Split('/')[2]
                ResourceGroup = $ResourceID.Split('/')[4]
                Resource = $ResourceID.Split('/')[8].Trim('"')
            }    
        }
    }
    else
    {
        Write-Host 'Invalid Input. Try either -Resource -ResourceGroup and -Subscription together or just the -ResourceID' -ForegroundColor Red    
    }

    # Connect to the Azure account.
    try
    {
        Connect-AzAccount -Subscription $AccountInfo.Subscription | Out-Null
    }
    catch
    {
        Write-Error 'Could not connect to Azure!'       
    }

    # Gather Resource information for $Resource.
    try
    {
	    $ResourceType = (Get-AzResource -ResourceName $AccountInfo.Resource).ResourceType
    }
    catch
    {
        Write-Error 'Could not find resource!'
    }

    # Run scripts appropriate for the type of resource found.
    switch ($ResourceType)
    {
        'Microsoft.Compute/virtualMachines'
        {
            $VM = Get-AzVM -Name $AccountInfo.Resource -ResourceGroupName $AccountInfo.ResourceGroup
            Write-Host 'Virtual Machine Specs' -ForegroundColor Green
            Write-Host '--------------------------------------------------------------------------------------' -ForegroundColor Green -NoNewline
            $VMSpecs = Get-ETAzVMInfo -VM $VM
            Write-Output $VMSpecs | Format-Table -AutoSize
            
            Write-Host 'Network Adapters' -ForegroundColor Green
            Write-Host '--------------------------------------------------------------------------------------' -ForegroundColor Green -NoNewline
            $VMNics = Get-ETAzNIC -VM $VM
            Write-Output $VMNics | Format-Table -AutoSize
            
            Write-Host 'Public IP' -ForegroundColor Green
            Write-Host '--------------------------------------------------------------------------------------' -ForegroundColor Green -NoNewline
            $VMPIP = Get-ETAzPIP -VM $VM
            Write-Output $VMPIP | Format-Table -AutoSize
            
            Write-Host 'VM Disks' -ForegroundColor Green
            Write-Host '--------------------------------------------------------------------------------------' -ForegroundColor Green -NoNewline
            $Disks = Get-ETAzDisks -VM $VM
            Write-Output $Disks | Format-Table -AutoSize
        }
        'Microsoft.Sql/servers'
        {
            Write-Host 'SQL Database' -ForegroundColor Green
            Write-Host '--------------------------------------------------------------------------------------' -ForegroundColor Green -NoNewline
            $Database = Get-ETAzDatabase -ServerName $AccountInfo.Resource -ResourceGroup $AccountInfo.ResourceGroup -Database $AccountInfo.Database
            Write-Output $Database 
        }
        'Microsoft.Web/serverFarms'
        {
            Write-Host 'Nothing yet for App Service Plans. :('
        }
        'Microsoft.Web/sites'
        {
            Write-Host 'Nothing yet for App services. Insert sad face.'
        }
        'Microsoft.Storage/storageAccounts'
        {
            Write-Host 'Nothing yet for Storage accounts.'
        }
        Default
        {
            Write-Host "I don't know what a $ResourceType is..."
        }
    }
}
