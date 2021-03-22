function Get-ETAzVMInfo
{
    Param(
        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [string]
        $Resource,

        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [string]
        $ResourceGroup,

        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [PSObject]
        $VM
    )

    Write-Host 'Virtual Machine Specs' -ForegroundColor Green

    # Create PSObject and print out VM Info.
    [PSCustomObject]@{
		VMName = $VM.Name
		ResourceGroup = $VM.ResourceGroupName
		Location = $VM.Location
		Size = $VM.HardwareProfile.VmSize
		OS = $VM.StorageProfile.ImageReference.Sku
		ProvisioningState = $VM.ProvisioningState
	}
}

function Get-ETAzNIC
{
    Param(
        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [string]
        $Resource,

        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [string]
        $ResourceGroup,

        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [PSObject]
        $VM
    )

    Write-Host 'Network Adapters' -ForegroundColor Green

	# Create PSObject of NICs for VM.
	$VMNICPull = $VM.NetworkProfile.NetworkInterfaces | Select-Object ID
	foreach ($nic in $VMNICPull)
	{
        $NICResourceName = $nic.Id.Split('/')[8]
		$NICInfo = Get-AzNetworkInterface -Name $NICResourceName
		$NICIPInfo = $NICInfo | Get-AzNetworkInterfaceIpConfig | Select-Object ProvisioningState,PrivateIpAddress,PrivateIpAllocationMethod
		[PSCustomObject]@{
			NIC = $NICResourceName
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
        [string]
        $Resource,

        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [string]
        $ResourceGroup,

        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [PSObject]
        $VM
    )

    Write-Host 'Public IP' -ForegroundColor Green

    $PublicIPPull = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroup | Where-Object { $_.IpConfiguration.Id -like "*$Resource*"}
    foreach ($pip in $PublicIPPull)
    {
    	[PSCustomObject]@{
		    PublicIP = $pip.Name
		    IPAddress = $pip.IPAddress
		    IPAllocation = $pip.PublicIpAllocationMethod
		    State = $pip.ProvisioningState
	    }        
    }
}  

function Get-ETAzStorage
{
    Param(
        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [string]
        $Resource,

        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [string]
        $ResourceGroup,

        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [PSObject]
        $VM
    )

    Write-Host 'VM Disks' -ForegroundColor Green

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
    $jobsArray | FT -AutoSize -Property RecoveryPointid, RecoveryPointTime, RecoveryPointType 
}

Function Get-ETAzReports
{
    Param(
        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [string]
        $Resource,

        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [string]
        $ResourceGroup,

        [parameter(Mandatory=$True)]
        [ValidateNotNullorEmpty()]
        [string]
        $Subscription
    )

    Clear-Host

    # Connect to the Azure account.
    try
    {
        Connect-AzAccount -Subscription $Subscription | Out-Null
    }
    catch
    {
        Write-Error 'Something bad2'       
    }

    # Gather Resource information for $Resource.
    try
    {
	    $ResourceType = (Get-AzResource -ResourceName $Resource ).ResourceType   
    }
    catch
    {
        Write-Error 'Something bad3'
    }

    # Run scripts appropriate for the type of resource found.
    switch ($ResourceType)
    {
        'Microsoft.Compute/virtualMachines'
        {
            $VM = Get-AzVM -Name $Resource -ResourceGroupName $ResourceGroup
            Get-ETAzVMInfo -Resource $Resource -ResourceGroup $ResourceGroup -VM $VM | Format-Table -AutoSize
            Get-ETAzNIC -Resource $Resource -ResourceGroup $ResourceGroup -VM $VM | Format-Table -AutoSize
            Get-ETAzPIP -Resource $Resource -ResourceGroup $ResourceGroup -VM $VM | Format-Table -AutoSize
            Get-ETAzStorage -Resource $Resource -ResourceGroup $ResourceGroup -VM $VM | Format-Table -AutoSize
        }
        Default
        {
            Write-Host "I don't know what a $ResourceType is..."
        }
    }
}
