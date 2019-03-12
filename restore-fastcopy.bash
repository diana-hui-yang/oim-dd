#!/bin/bash
#
# Name:         restore-fastcopy.bash
#
# Function:     This script will prepare DD Oracle files for Oracle instant restore.  
#		It will use DD fastcopy to copy Oracle image copy files in current
#		directory on to a restore directory on DD 
#
# Show Usage: run the command to show the usage
#
# Changes:
# 01/24/19 Diana Yang  New script
# 02/07/19 Diana Yang  Only fastcopy archivelog when needed 
# 03/12/19 Diana Yang  Allow several copies of the same database 
#
# footnotes:
# If you use this script and would like to get new code when any fixes are added,
# please send an email to diana.h.yang@dell.com. Whenever it is updated, I will send
# you an alert.
#################################################################

function show_usage {
echo "usage: restore-fastcopy.ksh -d <Data Domain> -u <DD User>  -m <Mount Point> -h <Host> -o <Oracle_sid> -t <Target Directory> -a <yes or no> -s <Source Directory>"
echo " -d : Data Domain"
echo " -u : DD user (administrator role)"
echo " -m : Mount Point"
echo " -h : Backup Host"
echo " -o : ORACLE_SID"
echo " -a : No means start the database without archivelog"
echo " -t : Target Directory after directory <mount point>/<host>/<oracle_sid>"
echo " -s : Source Directory after directory <mount point>/<host>/<oracle_sid>>/<Target Directory>"
}

while getopts ":d:u:m:h:a:o:t:s:" opt; do
  case $opt in
    d ) dd=$OPTARG;;
    u ) user=$OPTARG;;
    m ) mount=$OPTARG;; 
    h ) host=$OPTARG;;
    a ) applylog=$OPTARG;;
    o ) oraclesid=$OPTARG;;
    t ) tdir=$OPTARG;; 
    s ) sdir=$OPTARG;; 
  esac
done

echo $dd $user $mount $sdir $tdir
# Check required parameters
if test $dd && test $user && test $mount && test $host && test $oraclesid && test $sdir
then
  :
else
  show_usage
  exit 1
fi

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
#echo "directory is $DIR"
if [[ $DIR = "." ]]; then
   DIR=`pwd`
fi

if [[ ! -d $DIR/log ]]; then
    echo " $DIR/log does not exist, create it"
    mkdir -p $DIR/log
fi

data_root_dir=$mount/$host/$oraclesid

if [[ -z $mtree ]]; then
    mtree=/data/col1/`echo $mount | awk -F "/" '{print $NF}'`
    echo "Mtree is not provided, we assume it is same as the last field of Mount Point" 
    echo "Mtree is $mtree"
fi

source_dir_dd=${mtree}/$host/$oraclesid/full/$sdir
archives_dir_dd=${mtree}/$host/$oraclesid/archivelog
controls_dir_dd=${mtree}/$host/$oraclesid/controlfile

if [[ -z $tdir ]]; then
   target_dir_dd=${mtree}-instant/$host/$oraclesid/full/$sdir
   archivet_dir_dd=${mtree}-instant/$host/$oraclesid/archivelog
   controlt_dir_dd=${mtree}-instant/$host/$oraclesid/controlfile
else
   target_dir_dd=${mtree}-instant/$host/$oraclesid/$tdir/full/$sdir
   archivet_dir_dd=${mtree}-instant/$host/$oraclesid/$tdir/archivelog
   controlt_dir_dd=${mtree}-instant/$host/$oraclesid/$tdir/controlfile
fi

echo "Fastcopy from source $source_dir_dd to target $target_dir_dd"

echo ssh $user@$dd filesys fastcopy source ${source_dir_dd} destination ${target_dir_dd} force
ssh $user@$dd filesys fastcopy source ${source_dir_dd} destination ${target_dir_dd} force

if [[ $applylog != "NO" && $applylog != "No" && $applylog != "no" ]]; then
   echo "Fastcopy from source $archives_dir_dd to target $archivet_dir_dd"
   ssh $user@$dd filesys fastcopy source ${archives_dir_dd} destination ${archivet_dir_dd} force
else
   echo "applylog is $applylog. Will not apply archivelogs"
fi

#echo "Fastcopy from source $controls_dir_dd to target $controlt_dir_dd"
#ssh $user@$dd filesys fastcopy source ${controls_dir_dd} destination ${controlt_dir_dd} force

#sync; sync;
#ls -l ${data_root_dir}/$sdir/*data_D*
if [[ -z $tdir ]]; then
   echo ${data_root_dir}/full/$sdir
   echo ${data_root_dir}/archivelog
   echo ${data_root_dir}/controlfile
else
   echo ${data_root_dir}/$tdir/full/$sdir
   echo ${data_root_dir}/$tdir/archivelog
   echo ${data_root_dir}/$tdir/controlfile
fi
