$ErrorActionPreference = 'Stop'

$GATEWAY_NETWORK_BASE = "172.25.192.0"
$GATEWAY_SUBNET_PREFIX = "24"
$GATEWAY_IP = "172.25.192.1"

$GATEWAY_NETWORK_CIDR = $GATEWAY_NETWORK_BASE + "/" + $GATEWAY_SUBNET_PREFIX

$hypervSwitch = $null
try {
    $hypervSwitch = Get-VMSwitch -Name "VagrantHyperVSwitch"
    Write-Output "VagrantHyperVSwitch already exists."
}
catch [Microsoft.HyperV.PowerShell.VirtualizationException] {
    Write-Output "Creating new HyperVSwitch..."
    $hypervSwitch = New-VMSwitch -SwitchName "VagrantHyperVSwitch" -SwitchType Internal
}

$hypervAdapter = Get-NetAdapter -Name "vEthernet ($($hypervSwitch.Name))"

$ipinfo = Get-NetIPAddress -InterfaceIndex $hypervAdapter.ifIndex -AddressFamily IPv4

if (($ipinfo.PrefixOrigin -eq 'WellKnown') -and ($ipinfo.SuffixOrigin -eq 'Link')) {
    Write-Output "Setting gateway IP..."
    try {
        $ipinfo = New-NetIPAddress -IPAddress $GATEWAY_IP -PrefixLength $GATEWAY_SUBNET_PREFIX -InterfaceIndex $hypervAdapter.ifIndex
    }
    catch {
        Write-Error "IP Address in use, choose different one (lines 3-5 of powershell script). Update vagrantfile to match."
        Exit 1
    }
}
else {
    Write-Output "Adapter already has its gateway IP set to $($ipinfo.IPv4Address)"
}

try {
    $nat = Get-NetNat -Name "VagrantHyperVNAT"
    Write-Output "VagrantHyperVNAT already exists."
}
catch [Microsoft.PowerShell.Cmdletization.Cim.CimJobException] {
    Write-Output "Creating new NAT network..."
    $nat = New-NetNat -Name VagrantHyperVNAT -InternalIPInterfaceAddressPrefix $GATEWAY_NETWORK_CIDR
}

Write-Output "All done!"