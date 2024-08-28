#!/bin/bash

# Set the IP addresses of the admin, managers, and workers nodes
admin=172.31.45.82
mainManagerNode=54.80.8.228
verifierNode=54.152.246.228

# Set the workers' hostnames
managerHostname=manager-node
verifierHostname=verifier-node

# User of remote machines
localUser=damien
distUser=ubuntu

# Array of extra managers
additionnal_managers=false
extra_managers=()

# Array of workers
workers=($verifierNode)

# Array of all
all=($mainManagerNode $verifierNode)
declare -A allHostnames
allHostnames=([$mainManagerNode]=$managerHostname [$verifierHostname]=$verifierHostname)

#ssh certificate name variable
certName=omar-vm-priv-key.pem

#############################################
#            DO NOT EDIT BELOW              #
#############################################

# Change permissions of SSH keys
chmod 600 /home/$localUser/.ssh/$certName

# Create SSH Config file to ignore checking (don't use in production!)
echo "StrictHostKeyChecking no" > ~/.ssh/config

#add ssh keys for all nodes
# for node in "${all[@]}"; do
#   ssh-copy-id $distUser@$node
# done
# 
# Copy SSH keys to MN1 to copy tokens back later
scp -i /home/$localUser/.ssh/$certName /home/$localUser/.ssh/$certName  $distUser@$mainManagerNode:~/.ssh
# scp -i /home/$distUser/.ssh/$certName /home/$distUser/.ssh/$certName.pub $distUser@$mainManagerNode:~/.ssh

# 
# Install dependencies for each node (Docker)
for newnode in "${all[@]}"; do
  nodeHostname=${allHostnames[$newnode]}
  ssh $distUser@$newnode -i ~/.ssh/$certName sudo su <<EOF
    iptables -F    
    iptables -P INPUT ACCEPT
    # Change Hostname
    hostnamectl set-hostname $nodeHostname
    if [ $? -ne 0 ]; then
      echo "Failed to set hostname on $newnode"
      exit 1
    fi
    # Remove potential residual files
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd
    # Add Docker's official GPG key:
    apt-get update
    if [ $? -ne 0 ]; then
      echo "Failed to update package list on $newnode"
      exit 1
    fi
    NEEDRESTART_MODE=a apt install ca-certificates curl gnupg -y
    if [ $? -ne 0 ]; then
      echo "Failed to install dependencies on $newnode"
      exit 1
    fi
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    if [ $? -ne 0 ]; then
      echo "Failed to add Docker GPG key on $newnode"
      exit 1
    fi
    chmod a+r /etc/apt/keyrings/docker.gpg
  
    # Add the repository to Apt sources:
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    if [ $? -ne 0 ]; then
      echo "Failed to update package list again on $newnode"
      exit 1
    fi
    NEEDRESTART_MODE=a apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
    if [ $? -ne 0 ]; then
      echo "Failed to install Docker on $newnode"
      exit 1
    fi
    docker swarm leave --force
    # Install git:
    apt-get install git -y
    if [ $? -ne 0 ]; then
      echo "Failed to install git on $newnode"
      exit 1
    fi
    exit
EOF
  if [ $? -ne 0 ]; then
    echo "Error during SSH operation on $newnode."
    exit 1
  fi
  echo -e " \033[32;5m$newnode - Docker installed!\033[0m"
done

# Step 1: Create Swarm on the main manager node
ssh -tt $distUser@$mainManagerNode -i ~/.ssh/$certName sudo su <<EOF
  docker swarm init --advertise-addr $mainManagerNode --default-addr-pool 10.20.0.0/16 --default-addr-pool-mask-length 26
  if [ $? -ne 0 ]; then
    echo "Failed to initialize Docker Swarm on $mainManagerNode"
    exit 1
  fi
  docker swarm join-token manager | grep -Po 'docker swarm join --token \K[^\s]*' > manager.txt
  if [ $? -ne 0 ]; then
    echo "Failed to get manager join token on $mainManagerNode"
    exit 1
  fi
  docker swarm join-token worker | grep -Po 'docker swarm join --token \K[^\s]*' > worker.txt
  if [ $? -ne 0 ]; then
    echo "Failed to get worker join token on $mainManagerNode"
    exit 1
  fi
  echo "StrictHostKeyChecking no" > ~/.ssh/config
  ssh-copy-id -i /home/$distUser/.ssh/$certName $localUser@$admin
  if [ $? -ne 0 ]; then
    echo "Error copying SSH key to admin node."
    exit 1
  fi
  scp -i /home/$distUser/.ssh/$certName /home/$distUser/manager.txt $localUser@$admin:~/manager
  if [ $? -ne 0 ]; then
    echo "Error copying manager join token to admin node."
    exit 1
  fi
  scp -i /home/$distUser/.ssh/$certName /home/$distUser/worker.txt $localUser@$admin:~/worker
  if [ $? -ne 0 ]; then
    echo "Error copying worker join token to admin node."
    exit 1
  fi
  exit
EOF
if [ $? -ne 0 ]; then
  echo "Error during SSH operation on $mainManagerNode."
  exit 1
fi
echo -e " \033[32;5mmainManagerNode Completed\033[0m"

# Step 2: Set variables
managerToken=`cat manager`
workerToken=`cat worker`

# Step 3: Connect additional manager
if [[ $additionnal_managers == true ]]; then
  for newnode in "${extra_managers[@]}"; do
    ssh -tt $distUser@$newnode -i ~/.ssh/$certName sudo su <<EOF
      docker swarm join --token $managerToken $mainManagerNode
      if [ $? -ne 0 ]; then
        echo "Failed to join Docker Swarm as manager on $newnode"
        exit 1
      fi
      exit
EOF
    if [ $? -ne 0 ]; then
      echo "Error during SSH operation on $newnode."
      exit 1
    fi
    echo -e " \033[32;5m$newnode - Manager node joined successfully!\033[0m"
  done
fi

# Step 4: Connect additional workers
for workernode in "${workers[@]}"; do
  ssh -tt $distUser@$workernode -i ~/.ssh/$certName sudo su <<EOF
    docker swarm join --token $workerToken $mainManagerNode
    if [ $? -ne 0 ]; then
      echo "Failed to join Docker Swarm as worker on $workernode"
      exit 1
    fi
    exit
EOF
  if [ $? -ne 0 ]; then
    echo "Error during SSH operation on $workernode."
    exit 1
  fi
  echo -e " \033[32;5m$workernode - Worker node joined successfully with hostname $workerHostname!\033[0m"
done