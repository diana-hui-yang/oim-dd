#!/bin/ksh
#
# Name:         incremerge.fastcopy.ksh
#
# Function:     This script will copy files created by RMAN copy files that
#               are used for incrmenetal merge from one diretory to two other 
#               directories in the same mtree using DD fasctcopy. This step 
#               saves a full Oracle image backup before they are updated with 
#               new incremental data. One directory is named with the backup date. 
#               The date is determined by incremerge.ksh script which does 
#               RMAN incremental merge backup.The other directory is named with 
#               "recent". 
#               First DD secure login should be set up from this Linux server
#               to DD. The last field of mount point is assumed to be the same
#               as the last field of mtree if mtree name is not provided. 
#               Retention lock is set based on the date that are fastcopied. 
#
# Show Usage: run the command to show the usage
#
# Changes:
# 10/1/16 Diana Yang   New script
# 08/29/18 Diana Yang  Add logs and troubleshooting
# 01/08/19 Diana Yang  Add log trimming 
# 02/01/19 Diana Yang  Add separate log directories for each host
#
# footnotes:
# If you use this script and would like to get new code when any fixes are added,
# please send an email to diana.h.yang@dell.com. Whenever it is updated, I will send
# you an alert.
#################################################################

function show_usage {
echo "usage: incremerge-fastcopy.ksh -d <Data Domain> -u <DD User> -m <Mount Point> -h <host> -o <Oracle_sid> -t <mtree>" 
echo " -d : Data Domain"
echo " -u : DD user (administrator role)"
echo " -m : Mount point"
echo " -h : host"
echo " -o : ORACLE_SID"
echo " -t : mtree (optional, start with /data/col1/
If mtree is not provides, we assume it is the same as the last field of Mount Point)"
}
while getopts ":d:u:m:h:o:t:" opt; do
  case $opt in
    d ) dd=$OPTARG;;
    u ) user=$OPTARG;;
    m ) mount=$OPTARG;;
    h ) host=$OPTARG;;
    o ) oraclesid=$OPTARG;;
    t ) mtree=$OPTARG;;
  esac
done

echo $dd $user $mount $host $oraclesid $lockday

# Check required parameters
if test $dd && test $user && test $mount && test $host && test $oraclesid 
then
  :
else
  show_usage
  exit 1
fi

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
if [[ $DIR = "." ]]; then
   DIR=`pwd`
fi

function prepare {
#echo "directory is $DIR"

if [[ ! -d $DIR/log/$host ]]; then
    print " $DIR/log/$host does not exist, create it"
    mkdir -p $DIR/log/$host
fi

#trim log directory
cd $DIR/log
find . -type f -mtime +7 -exec /bin/rm {} \;
 
currentDATE=`/bin/date '+%Y%m%d%H%M%S'`
runlog=$DIR/log/$host/$oraclesid.incremerge-fastcopy.$currentDATE.log
setret_ksh=$DIR/$host/$oraclesid.setretention.ksh

DATE_SUFFIX=`cat /tmp/$host.$oraclesid.incremerge.time`
if [ $? -ne 0 ]; then
    echo "Cannot open file /tmp/$host.$oraclesid.incremerge.time" >> $runlog
    exit 1
fi
echo "Oracle backup time was $DATE_SUFFIX" >> $runlog



#echo "runlog is $runlog"

echo "Incremerge-fastcopy.ksh script starts at $DATE_SUFFIX" > $runlog 
echo "Oracle datafiles were copied to directory $mount/full/datafile" >> $runlog 
sdir=$mount/$host/$oraclesid/full/datafile
tdir=$mount/$host/$oraclesid/full/datafile.$DATE_SUFFIX
echo "source directory is $sdir"
echo "target directory is $tdir"
}

function get_mtree {
if [[ -z $mtree ]]; then
    lmtree=`echo $mount | awk -F "/" '{print $NF}'`
    mtree=/data/col1/$lmtree
    print "Mtree is $mtree"
else
    ddinits1=`echo $mtree |  awk -F "/" '{print $2}'`
    ddinits2=`echo $mtree |  awk -F "/" '{print $3}'`
    if [[ $ddinits1 != "data" || $ddinits2 != "col1" ]]; then

        firsts=`echo $mtree | awk -F "/" '{print $1}'`
        if [[ -z $firsts ]]; then
           lmtree=${mtree:1}
        fi
        mtree=/data/col1/$lmtree
    fi
    print "Mtree is $mtree"
fi
}

function fastcopy_backup {
echo "Fastcopy Oracle datafiles in  $mount/$host/$oraclesid/full/datafile to $mount/$host/$oraclesid/full/datafile.$DATE_SUFFIX" >> $runlog 
#echo "Fastcopy Oracle datafiles in  $mount/$host/$oraclesid/full/datafile to $mount/$host/$oraclesid/full/datafile.recent" >> $runlog 

echo "fastcopy started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
ssh $user@$dd "filesys fastcopy source $mtree/$host/$oraclesid/full/datafile destination $mtree/$host/$oraclesid/full/datafile.$DATE_SUFFIX force"
#ssh $user@$dd "filesys fastcopy source $mtree/$host/$oraclesid/full/datafile destination $mtree/$host/$oraclesid/full/datafile.recent force"

if [ $? -ne 0 ]; then
    echo "fastcopy failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
    exit 1
fi

echo "fastcopy finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
}

function set_retention_p {
ret_status=`ssh $user@$dd "mtree list $mtree"  | grep -i $lmtree | awk '{print $3}' | awk -F "/" '{print $2}'`

if [[ $ret_status != "RLGE"  && $ret_status != "RLCE" ]]; then
   echo "Retention lock is not enabled on this mtree $mtee. Will enable governance mode " >> $runlog
   ssh $user@$dd "mtree retention-lock enable mode governance mtree $mtree"
   
   if [ $? -ne 0 ]; then
      echo "Cannot enable retention lock, maybe there is no license key" >> $runlog
      exit
   fi
   
   ssh $user@$dd "mtree retention-lock set max-retention-period "$lockday"day mtree $mtree"
else
   echo "Retention lock is enabled on this mtree $mtree. " >> $runlog
fi
}


prepare
get_mtree
fastcopy_backup
set_retention_p
