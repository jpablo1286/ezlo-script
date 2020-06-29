#bin/bash
echo "##### MIGRATION SCRIPT - PROXMOX TO AWS #######"
echo "# Author: Juan Pablo Rivera V                 #"
echo "# Version: 1.0                                #"
echo "###############################################"

#DEFAULT VALUES
SDATE=`date +"%d%m%y%H%M"`
PVEIP="192.168.28.20"
RPASS=""
VMVOL="/dev/zvol/srv-pool/ezlo/vm-102-disk-0"
DUMPDIR="/var/lib/vz/dump"
BNAME="ezloAlpine"
INPUT=""
S3BUCKET="ezlo-test"
echo "Please enter PVE IP: [$PVEIP]"
read INPUT
if [ "$INPUT" != "" ];then
	PVEIP=$INPUT
fi
echo "... connecting as root to $PVEIP"
echo "Please enter the root password for PVE:"
read -s INPUT
if [ "$INPUT" != "" ];then
        RPASS=$INPUT
else
	echo "No password provided ... exiting."
	exit 0
fi
sshpass -p "$RPASS" ssh root@$PVEIP 'ls'
if [ "$?" != 0 ];then
        echo "Invalid password ... exiting."
        exit 0
fi
echo "Please enter the volume to be migrated: [$VMVOL]"
read INPUT
if [ "$INPUT" != "" ];then
        VMVOL=$INPUT
fi
echo "Please enter the output directory for RAW image: [$DUMPDIR]"
read INPUT
if [ "$INPUT" != "" ];then
        DUMPDIR=$INPUT
fi
echo "Generating the RAW image ..."
sshpass -p "$RPASS" ssh root@$PVEIP "dd if=$VMVOL of=$DUMPDIR/$SDATE-ezlo-test.raw bs=1M"
if [ "$?" != 0 ];then
        echo "Something fail ... exiting."
        exit 0
fi
echo "Coping RAW file to controller machine ..."
sshpass -p "$RPASS" scp root@$PVEIP:$DUMPDIR/$SDATE-ezlo-test.raw ./
if [ "$?" != 0 ];then
        echo "Something fail ... exiting."
        exit 0
fi
echo "Please enter the S3 Bucket destination name: [$S3BUCKET]"
read INPUT
if [ "$INPUT" != "" ];then
        S3BUCKET=$INPUT
fi
echo "Sending RAW file to S3 ..."
aws s3 cp $SDATE-ezlo-test.raw s3://$S3BUCKET/
if [ "$?" != 0 ];then
        echo "Something fail ... exiting."
        exit 0
fi
SIZEF=`aws s3 ls s3://ezlo-test/2906202145-ezlo-test.raw --human-readable --summarize | grep "Total Size:" | awk '{print $3}'`
SIZEI=${FLOAT%.*}

echo "EC2 - Generationg json for import snapshot"
cat <<EOF > $SDATE-$BNAME.json
{
    "Description": "$SDATE-$BNAME",
    "Format": "raw",
    "UserBucket": {
        "S3Bucket": "$S3BUCKET",
        "S3Key": "$SDATE-ezlo-test.raw"
    }
}
EOF
echo "EC2 - Importing as snapshot ..."
IMPORTCMD=`aws ec2 import-snapshot --description "$SDATE-$BNAME" --disk-container file://$SDATE-$BNAME.json`
IMPORTID=`echo $IMPORTCMD | grep -oP '(?<="ImportTaskId": ")[^"]*'`
echo "Importing snapshot with id $IMPORTID ..."
STATUS="active"
while [ "$STATUS" != "completed" ]
do
        RESULT=`aws ec2 describe-import-snapshot-tasks --import-task-ids $IMPORTID`
        STATUS=`echo $RESULT | grep -oP '(?<="Status": ")[^"]*'`
        STATUSMSG=`echo $RESULT | grep -oP '(?<="StatusMessage": ")[^"]*'`
        PROGRESS=`echo $RESULT | grep -oP '(?<="Progress": ")[^"]*'`

        echo "Status: $STATUS($STATUSMSG) - Progress: $PROGRESS"

        if [ "$STATUS" == "deleted" ];then
                echo "Import Failed, exiting ..."
                exit 0
        fi
	if [ "$STATUS" == "completed" ];then
                SNAPID=`echo $RESULT | grep -oP '(?<="SnapshotId": ")[^"]*'`
                echo "Imported Sucessfully with snashot id: $SNAPID"
                
        fi
        sleep 10s
done
echo "Registring snapshot as AMI ..."
REGISTERCMD=`aws ec2 register-image --name $SDATE-$BNAME --virtualization-type hvm --root-device-name /dev/sda1 --block-device-mappings "[{\"DeviceName\": \"/dev/sda1\",\"Ebs\": {\"SnapshotId\": \"$SNAPID\",\"VolumeSize\": $SIZEI,\"DeleteOnTermination\": true,\"VolumeType\": \"gp2\"}}]"`
AMIID=`echo $REGISTERCMD | grep -oP '(?<="ImageId": ")[^"]*'`
echo "Creating Security Group ..."
aws ec2 create-security-group --group-name $SDATE-$BNAME-SG --description "Security Group for smokeping"
sleep 3s
echo "Adding rules to SG"
aws ec2 authorize-security-group-ingress \
    --group-name $SDATE-$BNAME-SG \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress \
    --group-name $SDATE-$BNAME-SG \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

echo "Launching EC2 instance ..."
EC2LAUNCHCMD=`aws ec2 run-instances --image-id $AMIID --instance-type t2.micro --key-name ezlo-test --security-groups $SDATE-$BNAME-SG`
INSTANCEID=`echo $EC2LAUNCHCMD | grep -oP '(?<="InstanceId": ")[^"]*'`
echo "Instance Launched with ID $INSTANCEID"
echo "Waiting for instance gets ready"
PUBLICIP=""
while [ "$PUBLICIP" == "" ]
do
        PUBLICIP=`aws ec2 describe-instances --filters Name=instance-state-name,Values=running Name=instance-id,Values=$INSTANCEID --query "Reservations[*].Instances[*].NetworkInterfaces[*].Association.PublicIp" | grep -v "\[" | grep -v "\]" | tr -d '[:blank:]' | tr -d '"'`
        sleep 5s
done

echo "Migration DONE you can SSH to $PUBLICIP or browse http://$PUBLICIP"


