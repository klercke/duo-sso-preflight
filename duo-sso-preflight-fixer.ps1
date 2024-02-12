# File: duo-sso-preflight-fixer.ps1
# Version: v0.2.1
# Author: Konnor Klercke
# Description: Tool to automatically fix errors found by duo-sso-preflight-checker

# Script options
[cmdletbinding()]
param(
    [Parameter(HelpMessage="Filename of user data CSV to import", Mandatory=$true)]
    [string]$UserCsv,

    [Parameter(HelpMessage="Do not make any real changes")]
    [bool]$WhatIfPreference = $true,

    [Parameter(HelpMessage="Disconnect from Graph after running")]
    [bool]$DisconnectFromGraph = $true
)

# Definitions from main preflight file
# TODO: Add a module/"library" script for these

# User errors enum
# Note that the binary representations are not necessarily correct.
# For example, Powershell (as of v7.4.0) will interpret 0b1000000000000000 as -32768
# https://github.com/PowerShell/PowerShell/issues/19218
[Flags()] enum UserError {
    NoError = 0

    # Email errors
    EmailDomainIncorrectError     = 1    # 0b0001
    EmailAttributeEmptyError      = 2    # 0b0010
    EmailAttributeIncorrectError  = 4    # 0b0100
    # Reserved                    = 8    # 0b1000

    # AD lookup errors
    ADSearchAccountNameError  = 16    # 0b00010000
    ADSearchRealNameError     = 32    # 0b00100000
    # Reserved                = 64    # 0b01000000
    # Reserved                = 128   # 0b10000000

    # Entra connect errors
    ConnectConsistencyGuidMissingErorr = 256   # 0b000100000000
    # Reserved                         = 512   # 0b001000000000
    # Reserved                         = 1024  # 0b010000000000
    # Reserved                         = 2048  # 0b100000000000

    # Entra account errors
    EntraSearchImmutableIdError  = 4096  # 0b0001000000000000
    EntraSearchEmailError        = 8192  # 0b0010000000000000
    EntraSearchRealNameError     = 16384 # 0b0100000000000000
    # Reserved                   = 32769 # 0b1000000000000000
}


# Define User class
class User {
    [string]        $LastName
    [string]        $FirstName
    [mailaddress]   $EmailAddress
    [string]        $OnPremUPN
    [string]        $EntraUPN
    [array]         $ConsistencyGUID
    [UserError]     $ErrorCode

    User (
        [string]$LastName,
        [string]$FirstName,
        [mailaddress]$EmailAddress,
        [string]$OnPremUPN,
        [string]$EntraUPN,
        [array]$ConsistencyGUID,
        [UserError]$ErrorCode
    ) {
        $this.LastName = $LastName
        $this.FirstName = $FirstName
        $this.EmailAddress = $EmailAddress
        $this.OnPremUPN = $OnPremUPN
        $this.EntraUPN = $EntraUPN
        $this.ConsistencyGUID = $ConsistencyGUID
        $this.ErrorCode = $ErrorCode
    }

		# User error "localizations"
		# UserErrorDescriptions[UserError] = String
		$UserErrorDescriptions = @{
				# Email errors
				[UserError]::EmailDomainIncorrectError      = "Email domain does not match"
				[UserError]::EmailAttributeEmptyError       = "AD email attribute empty"
				[UserError]::EmailAttributeIncorrectError   = "AD email attribute does not match provided email"
				
				# AD lookup errors
				[UserError]::ADSearchAccountNameError  = "Could not find user in AD when searching by username"
				[UserError]::ADSearchRealNameError     = "Could not find user in AD when searching by real name"

				# Entra connect errors
				[UserError]::ConnectConsistencyGuidMissingErorr    = "AD mS-DS-ConsistencyGUID attribute empty"

				# Entra account errors
				[UserError]::EntraSearchImmutableIdError = "Could not find user in Entra when searching by ImmutableId"
				[UserError]::EntraSearchEmailError       = "Could not find user in Entra when searching by email address"
				[UserError]::EntraSearchRealNameError    = "Could not find user in Entra when searching by real name"
		}

		# Update note to include reasons why this user may not be compliant
    [void] UpdateNote([string] $TextToAdd) {
        if ($this.Note -eq "") {
            $this.Note = $TextToAdd
        }
        else {
            $this.Note += (', ' + $TextToAdd)
        }
    }

    [void] UpdateError([UserError] $ErrorToAdd) {
        $this.ErrorCode += $ErrorToAdd

        $this.UpdateNote($Global:UserErrorDescriptions[$ErrorToAdd])
    }
}

# Import users into an array of Users
Write-Output "Importing users from CSV..."
$UsersFromCsv = Import-Csv -Path $UserCsv
$Users = @()
ForEach ($User in $UsersFromCsv) {
    $UserObject = @([User]::new($User."LastName", $User."FirstName", $User."EmailAddress", $User.'OnPremUPN', $User.'EntraUPN', $User.'ConsistencyGUID', $User.'ErrorCode'))
    $Users += $UserObject
}
$UserCount = $Users.Length
$Users = $Users | Sort-Object -Property LastName
Write-Output "Imported $UserCount users." 

# AD fixes
Write-Output "Checking AD..."
$ADDomain = Get-ADDomain
ForEach ($User in $Users) {
	# Skip AD lookup for users without any AD errors
	if ($User.ErrorCode -band 0b000100110110) {
		Write-Output "Performing AD fixes for $($User.EmailAddress)"
    $p = @{ 
        'SearchBase' = $ADDomain.DistinguishedName;
        'Server' = $ADDomain.PDCEmulator;
        'Property' = "mS-DS-ConsistencyGUID", 'Mail';
        'Filter' = "SamAccountName -eq '$(([mailaddress]$User.EmailAddress).User)'"
		}
    [Microsoft.ActiveDirectory.Management.ADAccount] $OnPremUser = Get-ADUser @p
	
	}
}
