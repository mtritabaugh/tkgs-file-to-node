#!/bin/bash

print_help() {
  echo " "
  echo "Help:"
  echo "Only one of either -c or -l can be supplied"
  echo "  -l FULL_PATH_TO_LOCALFILE"
  echo "  -d FULL_DESTINATION_PATH"
  echo "  -g GUEST_CLUSTER_NAME"
  echo "  -s SUPERVISOR_NAMESPACE_OF_GUEST_CLUSTER"
  echo "  -c FULL_PATH_TO_CERT"
  echo "  -r SYSTEMCTL_SERVICE_TO_RESTART"
  exit 1
}


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

    -s| --svnamespace )
      shift; svnamespace=$1
      ;;

    -c| --capath )
      shift; capath=$1
      ;;

    -r| --restart )
      shift; service=$1
      ;;

    *)
      echo "Invalid option"
      print_help
      ;;

  esac; shift
done
if [[ "$1" == '--' ]]; then shift; fi


if [[ -n "${capath}" ]]; then
  if [[ -n "${file}" -o -n "${destination}" -o -n "${gcname}" -o -n "${svnamespace}" ]]; then
    echo "-c can only be used with -r option."
    exit
  fi
else
  if [[ -z "${file}" -o -z "${destination}" -o -z "${gcname}" -o -z "${svnamespace}" ]]; then
    echo "If copying a file, destination, guest cluster name and supervisor namespace must not be blank"
    exit
  fi
fi


workdir="/tmp/${svnamespace}-${gcname}"
mkdir -p $workdir
sshkey=$workdir/gc-sshkey # path for gc private key
gckubeconfig=$workdir/kubeconfig # path for gc kubeconfig
timestamp=$(date +%F_%R)

pre_check() {
  if [[ ! -d $(dirname ${destination}) ]]; then
    echo "creating $(dirname ${destination})"; ssh -q -i ${sshkey} -o StrictHostKeyChecking=no vmware-system-user@${node_ip} sudo mkdir -p $(dirname ${destination})
  fi 

  if [[ -e ${destination} ]]; then
    echo "creating backup"; ssh -q -i ${sshkey} -o StrictHostKeyChecking=no vmware-system-user@${node_ip} sudo cp ${destination} ${destination}.bk-$(date +%F_%R)
  else
    echo "no pre-existing file at ${destination}"
  fi
}


copyfile() {
  node_ip=$1
  filepath=$2
  destination=$3

  pre_check()
  [[ $? == 0 ]] scp -q -i ${sshkey} -o StrictHostKeyChecking=no ${filepath} vmware-system-user@${node_ip}:/tmp/copied_file
  [[ $? == 0 ]] ssh -q -i ${sshkey} -o StrictHostKeyChecking=no vmware-system-user@${node_ip} sudo mv /tmp/copied_file ${destination}
}


installCA() {
  node_ip=$1
  capath=$2
  scp -q -i ${sshkey} -o StrictHostKeyChecking=no ${capath} vmware-system-user@${node_ip}:/tmp/ca.crt
  [[ $? == 0 ]] && ssh -q -i ${sshkey} -o StrictHostKeyChecking=no vmware-system-user@${node_ip} sudo cp /etc/pki/tls/certs/ca-bundle.crt /etc/pki/tls/certs/ca-bundle.crt_bk.${timestamp}

  [[ $? == 0 ]] && ssh -q -i ${sshkey} -o StrictHostKeyChecking=no vmware-system-user@${node_ip} 'sudo cat /etc/pki/tls/certs/ca-bundle.crt /tmp/ca.crt > /tmp/ca-bundle.crt'
  [[ $? == 0 ]] && ssh -q -i ${sshkey} -o StrictHostKeyChecking=no vmware-system-user@${node_ip} sudo mv /tmp/ca-bundle.crt /etc/pki/tls/certs/ca-bundle.crt
}


restart_service() {
  ssh -q -i ${sshkey} -o StrictHostKeyChecking=no vmware-system-user@${node_ip} sudo systemctl daemon-reload ${service}
  ssh -q -i ${sshkey} -o StrictHostKeyChecking=no vmware-system-user@${node_ip} sudo systemctl restart ${service}
}


### Main
# get guest cluster private key for each node
kubectl get secret -n ${svnamespace} ${gcname}"-ssh" -o jsonpath='{.data.ssh-privatekey}' | base64 --decode > ${sshkey}
[ $? != 0 ] && echo " please check existence of guest cluster private key secret" && exit
chmod 600 ${sshkey}

#get guest cluster kubeconfig
kubectl get secret -n ${svnamespace} ${gcname}"-kubeconfig" -o jsonpath='{.data.value}' | base64 --decode > ${gckubeconfig}
[ $? != 0 ] && echo " please check existence of guest cluster private key secret" && exit

# get IPs of each guest cluster nodes
iplist=$(KUBECONFIG=${gckubeconfig} kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')

for ip in ${ip}list; do

  if [[ -n "${file}" ]]; then
    echo "copying $file to node ${ip}:${destination} (needs about 10 seconds)... "
    copyfile ${ip} $file ${destination} && echo "Successfully copied $file to node ${ip}:${destination}" || echo "Failed to copy $file to node ${ip}:${destination}"
  fi

  if [[ -n "${capath}" ]]; then
    echo "installing root ca into node ${ip} (needs about 10 seconds)... "
    installCA ${ip} ${capath} && echo "Successfully installed root ca into node ${ip}" || echo "Failed to install root ca into node ${ip}"
  fi

  if [[ -n "${service}" ]]; then
    echo "restarting ${service}"
    restart_service && echo "${service} restarted" || echo "Failed to restart ${service}"
  fi

done

# End
