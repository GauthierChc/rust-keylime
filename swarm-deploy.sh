#!/bin/bash

# Set the IP addresses of the admin, managers, and workers nodes
admin=192.168.3.5
mainManagerNode=3.85.133.36
verifierNode=54.80.8.228
registrarNode=54.152.246.228
agent1Node=54.211.103.39

# Set the workers' hostnames
verifierHostname=verifier-node
registrarHostname=registrar-node
agent1Hostname=agent-node

# User of remote machines
user=ubuntu

# Interface used on remotes
interface=eth0

# Array of extra managers
additionnal_managers=false
extra_managers=()

# Array of workers
workers=($verifierNode $registrarNode $agent1Node)
workersHostnames=($verifierHostname $registrarHostname $agent1Hostname)
agentWorkers=($agent1Node)
agentsHostnames=($agent1Hostname)

# Array of all
all=($mainManagerNode $verifierNode $registrarNode $agent1Node)

#ssh certificate name variable
certName=omar-vm-priv-key.pem

#############################################
#            DO NOT EDIT BELOW              #
#############################################

# Move SSH certs to ~/.ssh and change permissions
cp /home/$user/{$certName,$certName.pub} /home/$user/.ssh
chmod 600 /home/$user/.ssh/$certName

# Create SSH Config file to ignore checking (don't use in production!)
echo "StrictHostKeyChecking no" > ~/.ssh/config

#add ssh keys for all nodes
# for node in "${all[@]}"; do
#   ssh-copy-id $user@$node
# done
# 
# Copy SSH keys to MN1 to copy tokens back later
scp -i /home/$user/.ssh/$certName /home/$user/$certName $user@$mainManagerNode:~/.ssh
# scp -i /home/$user/.ssh/$certName /home/$user/$certName.pub $user@$mainManagerNode:~/.ssh

# 
# Install dependencies for each node (Docker)
for newnode in "${all[@]}"; do
  ssh $user@$newnode -i ~/.ssh/$certName sudo su <<EOF
  iptables -F    
  iptables -P INPUT ACCEPT  
  # Add Docker's official GPG key:
  apt-get update
  NEEDRESTART_MODE=a apt install ca-certificates curl gnupg -y
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  # Add the repository to Apt sources:
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  NEEDRESTART_MODE=a apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
  # Install git:
  apt-get update
  apt-get install git
  exit
  EOF
  echo -e " \033[32;5m$newnode - Docker installed!\033[0m"
done

# Step 1: Create Swarm on first node
# Debug purpose : scp permet de copier de maniere securisee des fichier entre deux entites, ici les token sont copies
ssh -tt $user@$mainManagerNode -i ~/.ssh/$certName sudo su <<EOF
docker swarm init --advertise-addr $mainManagerNode --default-addr-pool 10.20.0.0/16 --default-addr-pool-mask-length 26
docker swarm join-token manager | grep -Po 'docker swarm join --token \K[^\s]*' > manager.txt
docker swarm join-token worker | grep -Po 'docker swarm join --token \K[^\s]*' > worker.txt
echo "StrictHostKeyChecking no" > ~/.ssh/config
ssh-copy-id -i /home/$user/.ssh/$certName $user@$admin
scp -i /home/$user/.ssh/$certName /home/$user/manager.txt $user@$admin:~/manager
scp -i /home/$user/.ssh/$certName /home/$user/worker.txt $user@$admin:~/worker
exit
EOF
echo -e " \033[32;5mmainManagerNode Completed\033[0m"

# Step 2: Set variables
managerToken=`cat manager`
workerToken=`cat worker`

# Step 3: Connect additional manager
if [[ $additionnal_managers == true ]]; then
  for newnode in "${extra_managers[@]}"; do
    ssh -tt -i ~/.ssh/$certName "$user@$newnode" sudo bash <<EOF
    docker swarm join --token $managerToken $mainManagerNode
    exit
    EOF
    echo -e " \033[32;5m$newnode - Manager node joined successfully!\033[0m"
  done
fi

# Step 4: Connect additional workers
for i in "${!workers[@]}"; do
  newnode=${workers[$i]}
  workerHostname=${workersHostnames[$i]}
  ssh -tt $user@$newnode -i ~/.ssh/$certName sudo su <<EOF
  sudo hostnamectl set-hostname $workerHostname
  docker swarm join --token $workerToken $mainManagerNode
  exit
  EOF
  echo -e " \033[32;5m$newnode - Worker node joined successfully with hostname $workerHostname!\033[0m"
done
