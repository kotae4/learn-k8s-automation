# should not be invoked manually!
# invoke by calling bootstrap.sh and passing --primary
# this script should invoke bootstrap-common.sh
# as well as bootstrap-bind9.sh and bootstrap-mariadb.sh
# and finally init the cluster and set up the CNI plugin