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
.PARAMETER imc
    Specify the IPv4 address or FQDN of the UCS device you want to query.
.PARAMETER csv
    Provide a CSV file with comma separated list of CIMC IP/Hostnames
.Example
    ./FN70545_IMC.ps1 -imc 10.10.10.11,10.10.20.11,myucs.company.com
.Example
    ./FN70545_IMC.ps1 -csv <Path to your CSV file> (eg... ./FN70545_IMC.ps1 -csv "C:\temp\RackMounts.csv")
.NOTES
    Author - Brandon Sarradet, Technical Leader Cisco Customer Experience
    Email - bsarrade@cisco.com
#>

Param($imc, $csv)

import-module Cisco.IMC
$PTversion = (Get-Module -Name Cisco.IMC).Version
if ($PTversion.Major -lt 2){
    Write-Verbose -Message "PowerTool Version $($PTversion.ToString()) is not supported. 
    Please update to latest release." -verbose
    break
}
#Clear any existing sessions
Disconnect-IMC

#Create a time stamp with today's date
$timestamp = get-date -Format o | foreach {$_ -replace ":", "."}
$today = $timestamp.split(".")[0]
$fullfile = $(Get-Location).Path + "\FULL-UCS-Disk-Inventory-" + $today + ".csv"
$riskfile = $(Get-Location).Path + "\AT-RISK-UCS-Disk-Inventory-" + $today + ".csv"

$affectedDisks = @("UCS-SD400G12S4-EP","UCS-SD400G12S4-EP=","UCS-C3X60-12G240=","UCS-C3X60-12G2160=","UCS-C3X60-12G2160","UCS-C3X60-12G240","UCS-SD16TB12S4-EP","UCS-SD16TB12S4-EP=","VDS-SD400G12S4-EP","TA-SD400G12S4-EP","CSP-SD400G12S4-EP=","CSP-SD400G12S4-EP","UCS-SP-SD-1P6TB","UCS-SD16TG1KHY-EP","UCS-SD400G1KHY-EP","UCS-SD16TG1KHY-EP=","UCS-SD400G1KHY-EP=","CSP-SD16TB12S4-EP=","CSP-SD16TB12S4-EP","V2P-SD16TB12S4-EP","ULTM-SD16TB12S4EP","TA-SD400G12S4-EP=","TA-SD400G12S4-E-OP")

$cred = Get-Credential -Message "Cisco IMC"

if (!($null -eq $imc)){
    $cimc = $imc.split(",")
}
elseif (!($null -eq $csv)){
    $cimc = Get-Content -Path $csv
}
else {
    Write-Error -Message "You didn't provide either a list of IPs or a CSV file!"
}

$DiskArray = [System.Collections.ArrayList]@()

foreach ($ucs in $cimc){
    $connect = Connect-Imc $ucs -Credential $cred
    Write-Verbose -Message "Collecting full disk inventory from $($connect.name)." -Verbose
    $DiskList = Get-ImcStorageLocalDisk
    $catalog = @{}
    Get-ImcPidCatalogHdd | %{$catalog[$_.Disk]=$_}
    $p = 0
    Foreach ($disk in $disklist){
        $p++
        Write-Progress -Activity "Getting Disk PID/SKU" -status "Queried: $p of $($disklist.count)"
        $disk | Add-Member NoteProperty -Name "IMCName" -Value $connect.Name
        $disk | Add-Member NoteProperty -Name "IMCModel" -Value $connect.Model
        $disk | Add-Member NoteProperty -Name "IMCVersion" -Value $connect.Version
        $disk | Add-Member NoteProperty -Name "Pid" -Value $catalog[$disk.Id].Pid
        $disk | Add-Member NoteProperty -Name "Description" -Value $catalog[$disk.Id].Description
        $disk | Add-Member NoteProperty -Name "Controller" -Value $catalog[$disk.Id].Controller
        if ($affectedDisks -contains $disk.Pid){
            $disk | Add-Member NoteProperty -Name "Affected" -Value "Yes"
        }
        else {
            $disk | Add-Member NoteProperty -Name "Affected" -Value "no"
        }
        $DiskArray.Add($disk) | Out-Null
    }
    $disconnect = Disconnect-Imc
}

$DiskArray | Select `
@{Name='Server'; Expression={$_.IMCName}}, `
@{Name='Server Model'; Expression={$_.IMCModel}}, `
@{Name='Server Firmware'; Expression={$_.IMCVersion}}, `
@{Name='Disk Controller'; Expression={$_.Controller}}, `
@{Name='Cisco Product ID'; Expression={$_.Pid}}, `
@{Name='Vendor Drive Model'; Expression={$_.ProductId}}, `
@{Name='Drive#'; Expression={$_.Id}}, `
@{Name='Drive Vendor'; Expression={$_.Vendor}}, `
@{Name='Drive Serial#'; Expression={$_.DriveSerialNumber}}, `
@{Name='Drive Firmware'; Expression={$_.DriveFirmware}}, `
@{Name='Affected FN70545?'; Expression={$_.Affected}} `
| Export-Csv -NoTypeInformation $fullfile