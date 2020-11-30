
# Use at own risk! Not well tested.

# Copy a file or install certificate on all nodes in a guest cluster

## Assumptions

- Must be run from a Supervisor Control Plane host
- Obtain the password via vCenter /usr/lib/vmware-wcp/decryptK8Pwd.py

## Copy File

Will create the directory on destination if it doesn't exist. Will backup existing file.
- copy-file.sh -l {PATH_TO_LOCAL_FILE} -d {FULL_PATH_ON_DESTINATION} -g {GUEST_CLUSTER_NAME}
-s {SUPERVISOR_NAMESPACE}


## Install Certificate

- copy-file.sh -c {PATH_TO_LOCAL_CERT}

## Restart Service
The -r {SERVICE} option will reload and restart a systemd service
