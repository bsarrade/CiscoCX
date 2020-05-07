<#
                Copyright (c) 2020 Cisco and/or its affiliates.

    This software is licensed to you under the terms of the Cisco Sample
    Code License, Version 1.1 (the "License"). You may obtain a copy of the
    License at

                https://developer.cisco.com/docs/licenses

    All use of the material herein must be in accordance with the terms of
    the License. All rights not expressly granted by the License are
    reserved. Unless required by applicable law or agreed to separately in
    writing, software distributed under the License is distributed on an "AS
    IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
    or implied.

.Synopsis
    Check all local storage disks for PID listed in FN70545
.DESCRIPTION
    Script will loop through every comma seperated system provided, authenticate with the provided credentials,
    then collect every disk present and enabled in the system. It then gathers PID catalog information for each 
    disk device to compare with the list of affected PIDs defined in the folowing Cisco Field Notice:
    https://www.cisco.com/c/en/us/support/docs/field-notices/705/fn70545.html?emailclick=CNSemail
.PARAMETER  ucsm
    Specify the IPv4 address or FQDN of the UCS device you want to query.
.Example
    ./FN70545_IMC.ps1 10.10.10.11,10.10.20.11,myucs.company.com
.NOTES
    Author - Brandon Sarradet, Technical Leader Cisco Customer Experience
    Email - bsarrade@cisco.com
#>

Param(
    [Parameter(Mandatory=$True,Position=1)]
    $ucsm = @()
)

import-module Cisco.UCSManager
$PTversion = (Get-Module -Name Cisco.UCSManager).Version
if ($PTversion.Major -lt 2){
    Write-Verbose -Message "PowerTool Version $($PTversion.ToString()) is not supported. 
    Please update to latest release." -verbose
    break
}

#Clear any existing sessions
Disconnect-Ucs

#Create a time stamp with today's date
$timestamp = get-date -Format o | foreach {$_ -replace ":", "."}
$today = $timestamp.split(".")[0]
$fullfile = $(Get-Location).Path + "\FULL-UCS-Disk-Inventory-" + $today + ".csv"
$riskfile = $(Get-Location).Path + "\AT-RISK-UCS-Disk-Inventory-" + $today + ".csv"

$affectedDisks = @("UCS-SD400G12S4-EP","UCS-SD400G12S4-EP=","UCS-C3X60-12G240=","UCS-C3X60-12G2160=","UCS-C3X60-12G2160","UCS-C3X60-12G240","UCS-SD16TB12S4-EP","UCS-SD16TB12S4-EP=","VDS-SD400G12S4-EP","TA-SD400G12S4-EP","CSP-SD400G12S4-EP=","CSP-SD400G12S4-EP","UCS-SP-SD-1P6TB","UCS-SD16TG1KHY-EP","UCS-SD400G1KHY-EP","UCS-SD16TG1KHY-EP=","UCS-SD400G1KHY-EP=","CSP-SD16TB12S4-EP=","CSP-SD16TB12S4-EP","V2P-SD16TB12S4-EP","ULTM-SD16TB12S4EP","TA-SD400G12S4-EP=","TA-SD400G12S4-E-OP")

$cred = Get-Credential -Message "Cisco UCS Manager"

$DiskList = [System.Collections.ArrayList]@()
$RiskList = [System.Collections.ArrayList]@()

foreach ($ucs in $ucsm){
    $connect = Connect-Ucs $ucs -Credential $cred
    $UcsDisks = [System.Collections.ArrayList]@()
    Write-Verbose -Message "Collecting full disk inventory from $($connect.name)." -Verbose
    Get-UcsStorageLocalDisk -Presence equipped | %{$UcsDisks.Add($_)} | Out-Null
    $uniqueModels = $UcsDisks | sort Model -Unique | ?{$_.Model.length -gt 1}
    $catalog = @{}
    #Dealing with an odd suspected change in PT version 2.4 vs 2.5... 
    foreach ($m in $uniqueModels){
        if (($PTversion.Major -eq 2) -AND ($PTversion.Minor -lt 5)){
            $catalog[$m.Model] = (Get-UcsEquipmentLocalDiskCapProvider -Model $m.model -Vendor $m.Vendor -Revision $m.Revision | Get-UcsEquipmentFruVariant)
        }
        else {
            $catalog[$m.Model] = (Get-UcsEquipmentLocalDiskCapProvider -Model $m.model -Vendor $m.Vendor -Revision $m.Revision | Get-UcsEquipmentFruVariantStorage)
        }
    }
    $p = 0
    foreach ($disk in $UcsDisks){
        $p++
	    Write-Progress -Activity "Getting Disk PID/SKU" -status "Queried: $p of $($ucsdisks.count)"
        $sku = ($catalog[$disk.Model] | ?{$_.Type -eq $disk.VariantType}).Pid
        $disk | Add-Member NoteProperty -Name "SKU" -Value $sku
        $DiskList.Add($disk) | Out-Null
		if ($affectedDisks -contains $disk.SKU){
            $RiskList.Add($disk)
        }
    }
    $disconnect = Disconnect-ucs
}

$DiskList | select Ucs,Dn,SKU,Vendor,Model,Serial,DeviceVersion | Export-Csv -NoTypeInformation $fullfile
$RiskList | select Ucs,Dn,SKU,Vendor,Model,Serial,DeviceVersion | Export-Csv -NoTypeInformation $riskfile
