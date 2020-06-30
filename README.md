# Migration Script (ezlo test)

This is a simple script that ssh to Proxmox node and generate the raw image from VM and migrates that VM to AWS uploading the raw file to S3

# Prerequisites 

For run this script you need to be able to reach the Proxmox node from your workstation aditionally you need to install the following packages.

```
sshpass
aws-cli
```
Additonally you need to configure your aws parameters with:
```
aws configure
```
Your AWS User needs to have permissions to S3 and EC2, you will need to implement a service role "vmimport" that allows EC2 to grab files from S3.

# Usage

This is an interactive script so you need to execute it and proviede some information
```
./ezlo-migrate.sh 
##### MIGRATION SCRIPT - PROXMOX TO AWS #######
# Author: Juan Pablo Rivera V                 #
# Version: 1.0                                #
###############################################
Please enter PVE IP: [192.168.28.20]
...
Please enter the root password for PVE:
...
Please enter the volume to be migrated: [/dev/zvol/srv-pool/ezlo/vm-102-disk-0]
Please enter the output directory for RAW image: [/var/lib/vz/dump]
...
Please enter the S3 Bucket destination name: [ezlo-test]
...
```
## Results

A the end of the script execution you will get a running instance based in your RAW image. You will get access to port 22 and 80 too.
output example:
```
...
Waiting for instance gets ready
Cleaning Up ...
Migration DONE you can SSH to 33.134.23.71 or browse http://33.134.23.71
```


