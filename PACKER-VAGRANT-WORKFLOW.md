# Automated Hyper-V VM Creation Workflow

These should be ran from powershell with admin privileges.

Packer building:
```
cd packer
packer init .
packer build ./base-k8s.pkr.hcl
cd ../
```
This produces a vagrant box file with a name like `packer_ubuntujammy_hyperv_amd64.box`. Move this to the vagrant folder (or where ever, I'm not your boss).

Vagrant provisioning:
```
cd vagrant
vagrant box add --name my-base-k8s-box ./packer_ubuntujammy_hyperv_amd64.box
vagrant init my-base-k8s-box
vagrant up --provider=hyperv
```