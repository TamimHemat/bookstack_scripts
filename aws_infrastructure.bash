#!/bin/bash

### Infrastructure script for AWS CLI ###

### Define the database master username and password ###

DB_MASTER_USER="admin"
DB_MASTER_PASS="adminpass"

### Create VPC and store the vpc id in a variable ###

echo "Creating VPC"
echo""
VPC_ID=$(aws ec2 create-vpc \
--cidr-block 10.0.0.0/16 \
--tag-specification ResourceType=vpc,Tags=['{Key=Name,Value=as2-tamim-vpc}'] | yq '.Vpc.VpcId') 

### Create Subnets and store their IDs ###

echo "Creating public subnet 1"
echo""
SUBNET1=$(aws ec2 create-subnet \
--vpc-id $VPC_ID \
--cidr-block 10.0.1.0/24 \
--availability-zone us-west-2a \
--tag-specification ResourceType=subnet,Tags=['{Key=Name,Value=as2-rds-pub-ec2}'] | yq '.Subnet.SubnetId')

echo "Creating private subnet 2"
echo""
SUBNET2=$(aws ec2 create-subnet \
--vpc-id $VPC_ID \
--cidr-block 10.0.2.0/24 \
--availability-zone us-west-2a \
--tag-specification ResourceType=subnet,Tags=['{Key=Name,Value=as2-rds-pri-1}'] | yq '.Subnet.SubnetId')

echo "Creating private subnet 3"
echo""
SUBNET3=$(aws ec2 create-subnet \
--vpc-id $VPC_ID \
--cidr-block 10.0.3.0/24 \
--availability-zone us-west-2b \
--tag-specification ResourceType=subnet,Tags=['{Key=Name,Value=as2-rds-pri-2}'] | yq '.Subnet.SubnetId')

### Modify the first subnet to be public ###

aws ec2 modify-subnet-attribute \
--subnet-id $SUBNET1 \
--map-public-ip-on-launch

### Create Internet Gateway and store the id in a variable ###

echo "Creating Internet Gateway"
echo""
IGW_ID=$(aws ec2 create-internet-gateway \
--tag-specification ResourceType=internet-gateway,Tags=['{Key=Name,Value=as2-igw}'] | yq '.InternetGateway.InternetGatewayId')

### Attach the Internet Gateway to the VPC ###

echo "Attaching Internet Gateway to the VPC"
echo""
aws ec2 attach-internet-gateway \
--internet-gateway-id $IGW_ID \
--vpc-id $VPC_ID >/dev/null

### Create a route table and store the id in a variable ###

echo "Creating route table"
echo""
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
--vpc-id $VPC_ID \
--tag-specification ResourceType=route-table,Tags=['{Key=Name,Value=as2-rt}'] | yq '.RouteTable.RouteTableId')

### Create a route to the Internet Gateway ###

echo "Creating IGW route for the route table"
echo""
aws ec2 create-route \
--route-table-id $ROUTE_TABLE_ID \
--destination-cidr-block 0.0.0.0/0 \
--gateway-id $IGW_ID >/dev/null

### Associate the route table with the first subnet ###

echo "Associating the public subnet with the route table"
echo""
aws ec2 associate-route-table \
--subnet-id $SUBNET1 \
--route-table-id $ROUTE_TABLE_ID >/dev/null

### Create a security group and store the id in a variable ###

echo "Creating a security group for the EC2 instance"
echo""
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
--group-name rds-ec2-sg \
--description "Security group for EC2 in Assignment 2. Allows SSH and HTTP from anywhere." \
--vpc-id $VPC_ID | yq '.GroupId')

### Add a rule to the security group to allow SSH from anywhere ###

echo "Adding inbound rule for the EC2 SG for SSH access from anywhere"
echo""
aws ec2 authorize-security-group-ingress \
--group-id $SECURITY_GROUP_ID \
--protocol tcp --port 22 \
--cidr 0.0.0.0/0 >/dev/null

### Add a rule to the security group to allow HTTP from anywhere ###

echo "Adding inbound rule for the EC2 SG for HTTP access from anywhere"
echo""
aws ec2 authorize-security-group-ingress \
--group-id $SECURITY_GROUP_ID \
--protocol tcp --port 80 \
--cidr 0.0.0.0/0 >/dev/null

### Create a key pair and store the private key in a file ###

echo "Creating key pair for the EC2 instance"
echo""
aws ec2 create-key-pair \
--key-name as2-ec2-key \
--key-type ed25519 \
--query 'KeyMaterial' \
--output text > as2-key.pem

### Change the permissions of the private key file ###

echo "Changing the permissions of the private key to 400"
echo""
chmod 400 as2-key.pem

### Create an EC2 Ubuntu instance using the created key pair and security group and store its instance ID ###

echo "Creating an EC2 Ubuntu instance"
echo""
EC2_ID=$(aws ec2 run-instances \
--image-id ami-0735c191cf914754d \
--count 1 \
--instance-type t2.micro \
--key-name as2-ec2-key \
--security-group-ids $SECURITY_GROUP_ID \
--subnet-id $SUBNET1 \
--associate-public-ip-address \
--tag-specification ResourceType=instance,Tags=['{Key=Name,Value=as2-rds-ec2}'] | yq '.Instances[0].InstanceId')

### Wait for the instance to be running ###

aws ec2 wait instance-running \
--instance-ids $EC2_ID

echo "EC2 instance is up and running"
echo""
### Create an RDS subnet group and store the subnet group name in a variable ###

echo "Creating RDS Subnet Group"
echo""
RDS_SUBNET_GROUP_NAME=$(aws rds create-db-subnet-group \
--db-subnet-group-name as2-rds-subnet-group \
--db-subnet-group-description "Subnet group for RDS in Assignment 2." \
--subnet-ids $SUBNET2 $SUBNET3 | yq '.DBSubnetGroup.DBSubnetGroupName')

### Create a security group for the database and store the id in a variable ###

echo "Creating a security group for the RDS database"
echo""
RDS_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
--group-name rds-sg \
--description "Security group for RDS in Assignment 2. Allows MySQL access from the VPC only." \
--vpc-id $VPC_ID | yq '.GroupId')

### Add a rule to the security group to allow MySQL access from the VPC CIDR only ###

echo "Adding an inbound rule to the RDS DB SG for MySQL access from the VPC"
echo""
aws ec2 authorize-security-group-ingress \
--group-id $RDS_SECURITY_GROUP_ID \
--protocol tcp --port 3306 \
--cidr 10.0.0.0/16 >/dev/null

### Create an RDS MySQL instance using the created subnet group and security group. Store the instance identifier ###

echo "Creating an RDS MySQL database"
echo""
echo "This step takes the longest time to complete"
echo "You will be notified when the database is up and running"
echo""
RDS_ID=$(aws rds create-db-instance \
--db-name as2_rds \
--db-instance-identifier as2-rds \
--db-instance-class db.t3.micro \
--engine mysql \
--master-username "$DB_MASTER_USER" \
--master-user-password "$DB_MASTER_PASS" \
--allocated-storage 20 \
--vpc-security-group-ids $RDS_SECURITY_GROUP_ID \
--db-subnet-group-name $RDS_SUBNET_GROUP_NAME \
--no-publicly-accessible \
--engine-version 8.0.28 \
--storage-type gp2 \
--availability-zone us-west-2a | yq '.DBInstance.DBInstanceIdentifier')

### Wait for the instance to be available ###

aws rds wait db-instance-available \
--db-instance-identifier $RDS_ID

echo "RDS database is up and running"
echo""

### Get the RDS endpoint and store it in a variable ###

echo "Getting the RDS endpoint and storing it in a variable"

RDS_ENDPOINT=$(aws rds describe-db-instances \
--db-instance-identifier $RDS_ID | yq '.DBInstances[0].Endpoint.Address')

echo""
echo "The infrastructure has been successfully created"

### Update the database username, password and endpoint variables in the application script ###

echo""
echo "Updating the database username, password and endpoint variables in the application script"

sed -i "s/DB_MASTER_USER=.*$/DB_MASTER_USER=$DB_MASTER_USER/" application_script.bash
sed -i "s/DB_MASTER_PASS=.*$/DB_MASTER_PASS=$DB_MASTER_PASS/" application_script.bash
sed -i "s/RDS_ENDPOINT=.*$/RDS_ENDPOINT=$RDS_ENDPOINT/" application_script.bash

echo""
echo "The application script has been updated"

### Copy the application script to the EC2 instance using SFTP ###
### Get the public IP of the EC2 instance and store it in a variable ###

echo""
echo "Getting the public IP of the EC2 instance"

EC2_IP=$(aws ec2 describe-instances \
--instance-ids $EC2_ID | yq '.Reservations[0].Instances[0].PublicIpAddress')

echo""
echo "Copying the application script to the EC2 instance"
echo "You will be prompted to type in 'yes' to continue connecting to the EC2 instance"
echo "This is only needed the first time you connect to the EC2 instance. It is a security measure"
echo "Type in 'yes' and press enter to continue"
echo""
echo""

sftp -i as2-key.pem ubuntu@$EC2_IP <<EOL
put application_script.bash
EOL
echo""

### Run the application script on the EC2 instance ###

echo "Running the application script on the EC2 instance"
echo""
echo""

ssh -i as2-key.pem -T ubuntu@$EC2_IP << "EOL"
chmod +x application_script.bash
echo "Application script will begin executing in 5 seconds"
echo""
sleep 5
echo""
sudo ./application_script.bash $(curl -s https://checkip.amazonaws.com)
EOL

echo""
echo "The application has been successfully executed"

echo""
echo "You can check the application at http://$EC2_IP"

echo""
echo "Congratulations! You have successfully completed Assignment 2!"
### Completed ###