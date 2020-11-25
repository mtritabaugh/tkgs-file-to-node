#!/bin/bash

while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do
  case $1 in
    -h | --help )
      print_help
      exit 1
      ;;

    -l | --local )
      shift; file=$1
      ;;

    -d| --destination )
      shift; destination=$1
      ;;

    -g| --gcname )
      shift; gcname=$1
      ;;

    -s| --gcnamespace )
      shift; gcnamespace=$1
      ;;

    -y )
      ytt=true
      ;;

    *)
      echo "Invalid option"
      print_help
      ;;

  esac; shift
done
if [[ "$1" == '--' ]]; then shift; fi

[ -z "$file" -o -z "$destination" -o -z "$gcname" -o -z "$gcnamespace" ] && echo "Error: file, desination, guest cluster name and guest cluster namespace must not be blank" && exit

workdir="/tmp/$gcnamespace-$gcname"
mkdir -p $workdir
sshkey=$workdir/gc-sshkey # path for gc private key
gckubeconfig=$workdir/kubeconfig # path for gc kubeconfig


# copyfile
# @param1: ip of node
# @param2: path to file
# @param3: destination
copyfile() {
node_ip=$1
filepath=$2
destination=$3
scp -q -i $sshkey -o StrictHostKeyChecking=no $filepath vmware-system-user@$node_ip:/tmp/copied_file
[ $? == 0 ] && ssh -q -i $sshkey -o StrictHostKeyChecking=no vmware-system-user@$node_ip sudo cp $destination $destination.bk
#[ $? == 0 ] && ssh -q -i $sshkey -o StrictHostKeyChecking=no vmware-system-user@$node_ip sudo mv /tmp/copied_file $destination
ssh -q -i $sshkey -o StrictHostKeyChecking=no vmware-system-user@$node_ip sudo mv /tmp/copied_file $destination

[ $? == 0 ] && ssh -q -i $sshkey -o StrictHostKeyChecking=no vmware-system-user@$node_ip sudo systemctl restart containerd
}


# get guest cluster private key for each node
kubectl get secret -n $gcnamespace $gcname"-ssh" -o jsonpath='{.data.ssh-privatekey}' | base64 --decode > $sshkey
[ $? != 0 ] && echo " please check existence of guest cluster private key secret" && exit
chmod 600 $sshkey

#get guest cluster kubeconfig
kubectl get secret -n $gcnamespace $gcname"-kubeconfig" -o jsonpath='{.data.value}' | base64 --decode > $gckubeconfig
[ $? != 0 ] && echo " please check existence of guest cluster private key secret" && exit

# get IPs of each guest cluster nodes
iplist=$(KUBECONFIG=$gckubeconfig kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
for ip in $iplist
do
echo "copying $file to node $ip:$destination (needs about 10 seconds)... "
copyfile $ip $file $destination && echo "Successfully copied $file to node $ip:$destination" || echo "Failed to copy $file to node $ip:$destination"
done
