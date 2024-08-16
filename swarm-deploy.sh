#!/bin/bash

# Set the IP addresses of the admin, managers, and workers nodes
admin=192.168.3.5
manager1=3.85.133.36
worker1=54.80.8.228
worker2=54.152.246.228
worker3=54.211.103.39

# Set the workers' hostnames
workerHostname1=verifier-node
workerHostname2=registrar-node
workerHostname3=agent-1-node

# User of remote machines
user=ubuntu

# Interface used on remotes
interface=eth0

# Array of extra managers
extra_managers=()

# Array of workers
workers=($worker1 $worker2 $worker3)
agentWorkers=($worker3)
workerHostnames=($workerHostname1 $workerHostname2 $workerHostname3)

# Array of all
all=($manager1 $worker1 $worker2 $worker3)

#ssh certificate name variable
certName=omar-vm-priv-key.pem

#############################################
#            DO NOT EDIT BELOW              #
#############################################

# Move SSH certs to ~/.ssh and change permissions
cp /home/$user/{$certName,$certName.pub} /home/$user/.ssh
chmod 600 /home/$user/.ssh/$certName 
# chmod 644 /home/$user/.ssh/$certName.pub

# Create SSH Config file to ignore checking (don't use in production!)
echo "StrictHostKeyChecking no" > ~/.ssh/config

#add ssh keys for all nodes
# for node in "${all[@]}"; do
#   ssh-copy-id $user@$node
# done
# 
# Copy SSH keys to MN1 to copy tokens back later
scp -i /home/$user/.ssh/$certName /home/$user/$certName $user@$manager1:~/.ssh
# scp -i /home/$user/.ssh/$certName /home/$user/$certName.pub $user@$manager1:~/.ssh

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
  echo -e " \033[32;5m$newnode - Docker & GlusterFS installed!\033[0m"
done

# Step 1: Create Swarm on first node
# Debug purpose : scp permet de copier de maniere securisee des fichier entre deux entites, ici les token sont copies
ssh -tt $user@$manager1 -i ~/.ssh/$certName sudo su <<EOF
docker swarm init --advertise-addr $manager1 --default-addr-pool 10.20.0.0/16 --default-addr-pool-mask-length 26
docker swarm join-token manager | grep -Po 'docker swarm join --token \K[^\s]*' > manager.txt
docker swarm join-token worker | grep -Po 'docker swarm join --token \K[^\s]*' > worker.txt
echo "StrictHostKeyChecking no" > ~/.ssh/config
ssh-copy-id -i /home/$user/.ssh/$certName $user@$admin
scp -i /home/$user/.ssh/$certName /home/$user/manager.txt $user@$admin:~/manager
scp -i /home/$user/.ssh/$certName /home/$user/worker.txt $user@$admin:~/worker
exit
EOF
echo -e " \033[32;5mManager1 Completed\033[0m"

# Step 2: Set variables
managerToken=`cat manager`
workerToken=`cat worker`

# Step 3: Connect additional manager
for newnode in "${extra_managers[@]}"; do
  ssh -tt $user@$newnode -i ~/.ssh/$certName sudo su <<EOF
  docker swarm join \
  --token  $managerToken \
  $manager1
  exit
EOF
  echo -e " \033[32;5m$newnode - Manager node joined successfully!\033[0m"
done

# Step 4: Connect additional worker
for newnode in "${workers[@]}"; do
  ssh -tt $user@$newnode -i ~/.ssh/$certName sudo su <<EOF
  docker swarm join \
  --token  $workerToken \
  $manager1
  docker node update --label-add worker=true ${workerHostname[@]}
  exit
EOF
  echo -e " \033[32;5m$newnode - Worker node joined successfully!\033[0m"
done

# Step 5: Label workers from the manager node
ssh -tt $user@$manager1 -i $pathToCert/$certName sudo su <<EOF
for hostname in ${workerHostnames[@]}; do
  docker node update --label-add worker=true \$hostname
done
exit
EOF


# Step 6 : Connect to all machines
# TO COMPLETE
# for newnode in "${all[@]}"; do
#   ssh $user@$newnode -i ~/.ssh/$certName sudo su <<EOF
  
# EOF
# done
