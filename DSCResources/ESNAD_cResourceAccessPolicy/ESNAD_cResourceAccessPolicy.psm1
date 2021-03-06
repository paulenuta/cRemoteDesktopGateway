# Load the Helper Module
Import-Module -Name "$PSScriptRoot\..\Helper.psm1" -Verbose:$false

data LocalizedData
{
    # culture="en-US"
    ConvertFrom-StringData -StringData @'
VerboseTestTargetSetting = RAP configuration item "{0}" does not match the desired state. 
VerboseTestTargetUsergroupAddAuthorization = Usergroup "{0}" not authorized.
VerboseTestTargetUsergroupRemoveAuthorization = Usergroup "{0}" autorization not specified in Configuration.
VerboseTestTargetTrueResult = The target resource is already in the desired state. No action is required. 
VerboseTestTargetFalseResult = The target resource is not in the desired state. 
VerboseSetTargetCapRuleCreated = Successfully created Connection Access Policy "{0}". 
VerboseSetTargetCapRuleRemoved = Successfully removed Connection Access Policy "{0}". 
VerboseSetTargetSetting = RAP configuration item "{0}" has been updated to "{1}".
VerboseSetTargetUsergroupRemoveAuthorization = Usergroup "{0}" removed from Usergroup container.
VerboseSetTargetUsergroupAddAuthorization = Usergroup "{0}" added to Usergroup container.
ErrorConnectionAccessPolicyFailure = Failure to get the requested resource access policy "{0}" information from the target machine.
'@

}

function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $RuleName
    )

    Assert-Module

    $itemPath = ("RDS:\GatewayServer\RAP\{0}" -f $RuleName)
    $rapItem = Get-Item -Path $itemPath

    if($rapItem -eq $null)
    {
        $EnsureResult = "Absent" 
    }
    elseif ($rapItem.count -eq 1)
    {
        $EnsureResult = "Present" 
        $rapSettings = Get-ChildItem $itemPath
        $userGroupPath = ('{0}\{1}' -f $itemPath, "UserGroups")
        $currentGroups = Get-ChildItem -Path $userGroupPath
    }
    else
    {
        $ErrorMessage = $LocalizedData.ErrorConnectionAccessPolicyFailure -f $RuleName 
        New-TerminatingError -ErrorId 'ConnectionAccessPolicyFailure' -ErrorMessage $ErrorMessage -ErrorCategory 'InvalidResult' 
    }
    
    $returnValue = @{
    Ensure = [System.String]$EnsureResult
    RuleName = [System.String]$rapItem.Name
    Usergroups = [System.String[]]$currentGroups
    PortNumbers = [System.String]($rapSettings | ?{$_.Name -eq 'PortNumbers'}).CurrentValue
    Status = [System.String]($rapSettings | ?{$_.Name -eq 'Status'}).CurrentValue
    ComputerGroupType = [System.String]($rapSettings | ?{$_.Name -eq 'ComputerGroupType'}).CurrentValue
    ComputerGroup = [System.String]($rapSettings | ?{$_.Name -eq 'ComputerGroup'}).CurrentValue
    }
    $returnValue
}


function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure,

        [parameter(Mandatory = $true)]
        [System.String]
        $RuleName,

        [System.String[]]
        $Usergroups,

        [ValidateSet("*","3389")]
        [System.String]
        $PortNumbers,

        [ValidateSet("1","0")]
        [System.String]
        $Status,

        [ValidateSet("0","1","2")]
        [System.String]
        $ComputerGroupType,

        [System.String]
        $ComputerGroup
    )

    Assert-Module

    $rapItem = Get-ChildItem -Path RDS:\GatewayServer\RAP\ | ?{$_.Name -eq $RuleName}

    if($rapItem -ne $null -and $Ensure -eq "Absent")
    {
        $rapItem | Remove-Item -Confirm:$false
        Write-Verbose -Message ($LocalizedData.VerboseSetTargetCapRuleRemoved -f $RuleName)
    }
    if($rapItem -eq $null -and $Ensure -eq "Present")
    {
        $rapItem = New-Item -Path RDS:\GatewayServer\RAP -Name $RuleName -UserGroups $Usergroups -ComputerGroupType $ComputerGroupType
        Write-Verbose -Message ($LocalizedData.VerboseSetTargetCapRuleCreated -f $RuleName)
    }
    
    if($rapItem -and $Ensure -eq "Present")
    {

        $rapSettings = Get-childItem $rapItem.PSPath
        $itemPath = $rapSettings[0].ParentPath
        foreach ($setting in ($rapSettings | Where Type -eq Integer))
        {
            if($PSBoundParameters.ContainsKey($setting.Name))
            {
                $param = (Get-Variable -Name $setting.Name)
                if($setting.CurrentValue -ne $param.Value)
                {
                    Set-Item -Path ('{0}\{1}' -f $itemPath, $setting.Name) -Value $param.Value
                    Write-Verbose -Message ($LocalizedData.VerboseSetTargetSetting -f $setting.Name, $param.Value)
                }
            }
        }
        
       if($PSBoundParameters.ContainsKey('Usergroups'))
        {
            $userGroupPath = ('{0}\{1}' -f $itemPath, "UserGroups")
            $currentGroups = Get-ChildItem -Path $userGroupPath
            $compareGroups = Compare-Object -ReferenceObject $userGroups -DifferenceObject $currentGroups
            if($compareGroups -ne $null)
            {
                $compareGroups | where SideIndicator -eq '<=' | ForEach {
                    New-Item -Path $userGroupPath -Name $_.InputObject
                    Write-Verbose -Message ($LocalizedData.VerboseSetTargetUsergroupAddAuthorization -f $_.InputObject)
                }
                $compareGroups | where SideIndicator -eq '=>' | ForEach {
                    Remove-Item -Path ($userGroupPath + '\' + $_.InputObject)
                    Write-Verbose -Message ($LocalizedData.VerboseSetTargetUsergroupRemoveAuthorization -f $_.InputObject)
                }
            }
        } 
    }
}


function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure,

        [parameter(Mandatory = $true)]
        [System.String]
        $RuleName,

        [System.String[]]
        $Usergroups,

        [ValidateSet("*","3389")]
        [System.String]
        $PortNumbers = "3389",

        [ValidateSet("1","0")]
        [System.String]
        $Status = "1",

        [ValidateSet("0","1","2")]
        [System.String]
        $ComputerGroupType,

        [System.String]
        $ComputerGroup
    )

    Assert-Module

    $InDesiredState = $true

    $rapItem = Get-ChildItem -Path RDS:\GatewayServer\RAP\ | ?{$_.Name -eq $RuleName}

    if(($rapItem -eq $null -and $Ensure -eq "Present") -or ($rapItem -ne $null -and $Ensure -eq "Absent"))
    {
        $InDesiredState = $false
    }

    if($rapItem -ne $null -and $Ensure -eq "Present")
    {
        $rapSettings = Get-childItem $rapItem.PSPath
        $itemPath = $rapSettings[0].ParentPath

        foreach ($setting in ($rapSettings | Where Type -eq Integer))
        {
            if($PSBoundParameters.ContainsKey($setting.Name))
            {
                $param = (Get-Variable -Name $setting.Name)
                if($setting.CurrentValue -ne $param.Value)
                {
                    $InDesiredState = $false
                    Write-Verbose -Message ($LocalizedData.VerboseTestTargetSetting -f $setting.Name )
                }
            }
        }
       
        if($PSBoundParameters.ContainsKey('Usergroups'))
        {
            $userGroupPath = ('{0}\{1}' -f $itemPath, "UserGroups")
            $currentGroups = Get-ChildItem -Path $userGroupPath
            $compareGroups = Compare-Object -ReferenceObject $userGroups -DifferenceObject $currentGroups
            if($compareGroups -ne $null)
            {
                $InDesiredState = $false
                $compareGroups | where SideIndicator -eq '=>' | ForEach {
                    Write-Verbose -Message ($LocalizedData.VerboseTestTargetUsergroupRemoveAuthorization -f $_.InputObject)
                }
                $compareGroups | where SideIndicator -eq '<=' | ForEach {
                    Write-Verbose -Message ($LocalizedData.VerboseTestTargetUsergroupAddAuthorization -f $_.InputObject)
                }
            }
        } 
    
    }
    if ($InDesiredState -eq $true) 
    { 
        Write-Verbose -Message ($LocalizedData.VerboseTestTargetTrueResult) 
    } 
    else 
    { 
        Write-Verbose -Message ($LocalizedData.VerboseTestTargetFalseResult) 
    } 
    return $InDesiredState 
}


Export-ModuleMember -Function *-TargetResource

