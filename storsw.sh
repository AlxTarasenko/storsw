#!/bin/bash
#
# Version 4.5
#
# Usage: ./storsw.sh
#
# The program inventory Storages and export to CSV file, with crosscheck by SAN inventory (my script - sansw.sh).
# I use this script with freeware Stor2RRD (Storage and SAN monitoring tool), install to /home/stor2rrd/storsw/, owner stor2rrd.
# *) run only by stor2rrd (SMcli auto reconfigure to runner user)
#
# Uses config file - storsw.lst with structure: IP Login Password StorageName Room KEY
# where KEY is:
#	LvoDS 	- Lenovo (DotHill) DS2200
#		ex. by default: IP manage Password Name Room MSA
#	MSA 	- HP MSA (DotHill) P2000G3 
#		ex. by default: IP manage \!manage Name Room MSA
#	NAp	- NetApp 7-mode (N6240)
#		ex. by stor2rrd user: IP stor2rrd Password Name Room NAp
#	DS	- IBM DS5K (DS3512)
#		ex. by stor2rrd uses SMcli: IP none SMcli Name Room DS
#	DPV	- Dell PowerVault (PV3820f)
#		ex. by stor2rrd uses SMcli: IP none SMcli Name Room DPV
#	SW	- IBM (Lenovo) Storwize (v3700, v5000, v5030, v7000)
#		ex. by SSH login: IP superuser Password Name Room SW
#		ex. by stor2rrd uses SSH public key: IP stor2rrd SSH Name Room SW
#	Xyr	- Xyratex (by dump file)
#		ex. by dump log file: IP xyratex_dump.log LOG Name Room Xyr
#
# Rules:
# 1) For HP MSA P2000, Lenovo DS2200 host (initiator) name as: HostName_A and HostName_B
# 2) Host(Storage), Port(SAN) and Alias(SAN) need equal, not applicable to NPIV
# 3) Out CSV file for export to DataBase (storsw_db.csv)
# 4) If exist file storsw_addon.csv, it merge to END of report CSV file (without first row (titles of columns)). For mix report by script and other systems
# 5) If exist file storsw_db_addon.csv, it merge to END of report CSV file for DataBase (without first row (titles of columns))
#
# 06/2018, Alexey Tarasenko, atarasenko@mail.ru
#
#
# ToDo: 
# 1. LenDS - volume, DiskGroupName as PoolName, not DiskGroupName
#


source "../lib_sw/lib_main.sh"
source "../lib_sw/lib_storage.sh"

Fsansw="../sansw/sansw_rep.csv"

Fout="storsw_rep.csv"
FoutDB="storsw_db.csv"
Fout2="storsw_stor2rrd.txt"
Fout3="storsw_rep.txt"
FoutXLS="storsw_rep.xls"
FoutDBXLS="storsw_db.xls"
Fadd="storsw_addon.csv"
FaddDB="storsw_db_addon.csv"
Flog="storsw.log"

Ftmp="storsw.tmp"
Ftmp2="storsw.tmp2"
FtmpC="storsw.tmpC"
FtmpV="storsw.tmpV"

curdate=$( date +"%d/%m/%Y %H:%M" )

if [[ -f $Fout ]]; then rm $Fout; fi
if [[ -f $FoutDB ]]; then rm $FoutDB; fi
if [[ -f $Fout2 ]]; then rm $Fout2; fi
if [[ -f $Fout3 ]]; then rm $Fout3; fi
if [[ -f $FoutXLS ]]; then rm $FoutXLS; fi
if [[ -f $FoutDBXLS ]]; then rm $FoutDBXLS; fi
if [[ -f $Flog ]]; then rm $Flog; fi

if [[ -f $Ftmp ]]; then rm $Ftmp; fi
if [[ -f $Ftmp2 ]]; then rm $Ftmp2; fi
if [[ -f $FtmpC ]]; then rm $FtmpC; fi
if [[ -f $FtmpV ]]; then rm $FtmpV; fi

if [[ -f "$Ftmp.volume" ]]; then rm "$Ftmp.volume"; fi
if [[ -f "$Ftmp.volwwn" ]]; then rm "$Ftmp.volwwn"; fi
if [[ -f "$Ftmp.host" ]]; then rm "$Ftmp.host"; fi
if [[ -f "$Ftmp.array" ]]; then rm "$Ftmp.array"; fi
if [[ -f "$Ftmp.cmd" ]]; then rm "$Ftmp.cmd"; fi
if [[ -f "$Ftmp.wwnhost" ]]; then rm "$Ftmp.wwnhost"; fi

index=0
while read line; do
    storsw[$index]="$line"
    index=$(($index+1))
done < storsw.lst


#SSH client parameters and options
#	-T					terminal off
    #v1 Fcmd="ssh $Flogin@$Fip /bin/bash"
    #v2 Fcmd="ssh -T $Flogin@$Fip"
#	-o PreferredAuthentications=password	auth by password prefer
#	-o ConnectTimeout=15			timeout of ssh session 
#	-i /home/$Flogin/.ssh/id_rsa 		path to ssh-key, if other user
#	-o PubkeyAuthentication=no		not use publis key
#	-o UserKnownHostsFile=/dev/null		pass if remote host key renewed, and add it to non exist file [know_hosts]
#	-o StrictHostKeyChecking=no		pass cheking remote host key in ~/.ssh/know_hosts, when first time session

echo "Date&Time  $curdate"
echo "Date,Room,Name+,IP,Firmware+,Capacity-,Used-,Free-,WWN,Ctrl#+,Ctrl WWPN,Ctrl Speed+,Ctrl Status+,Encl#+,Encl Status+,Encl Type,Encl PN#,Encl Serial#,Slots,Bkpl Speed,Disk Encl#+,Disk Bay#+,Disk Status+,Disk Type,Disk Mode,Disk Size,Disk Speed+,Disk PN#,Disk Serial#,Disk Group,DG Status+,DG Size,DG Free,Volume Name,Vol Status+,Vol Size,Volume WWID+,Volume Mapping,Vol DG,Func+,Host Name,Host Status+,Ports+,Device WWPN,Host Mapping" > $Fout
echo "Date,Room,Name+,IP,Firmware+,Capacity-,Used-,Free-,WWN,Ctrl#+,Ctrl WWPN,Ctrl Speed+,Ctrl Status+,Encl#+,Encl Status+,Encl Type,Encl PN#,Encl Serial#,Slots,Bkpl Speed,Disk Encl#+,Disk Bay#+,Disk Status+,Disk Type,Disk Mode,Disk Size,Disk Speed+,Disk PN#,Disk Serial#,Disk Group,DG Status+,DG Size,DG Free,Volume Name,Vol Status+,Vol Size,Volume WWID+,Volume Mapping,Vol DG,Func+,Host Name,Host Status+,Ports+,Device WWPN,Host Mapping" > $FoutDB
for ((a=0; a < ${#storsw[*]}; a++))
do
    declare -a item="( ${storsw[$a]} )"

    Fip="${item[0]}"
    Flogin="${item[1]}"
    Fpasswd="${item[2]}"
    Fname="${item[3]}"
    Froom="${item[4]}"
    Fkey="${item[5]}"

    echo -n "Processing $Fname..."

    part0=",,"
    part1=",,,,,"
    part2=",,,"
    part3=",,,,,,"
    part4=",,,,,,,,"
    part5=",,,"
    part6=",,,,,,"
    part7=",,,,"
    
    st_name=""
    st_ip=""
    st_os=""
    st_wwn=""
    st_size=""
    st_use=""
    st_free=""
    st_sizeKB=""
    st_useKB=""
    st_freeKB=""

    
# Processing Stor2RRD config.html files
    #Fcfg="/NONE"
    Fcfg="/home/stor2rrd/stor2rrd/data"
    if [[ -d $Fcfg ]]
    then
	#echo -n " +Stor2RRD"
        echo "=============================================" >> $Fout2
	
	st_name=""
	st_ip=""
	st_os=""
	st_wwn=""
	st_size=""
	st_use=""
	st_free=""
	
	Fdir="$Fcfg/$Fname"
    	if [[ -d $Fdir ]]
    	then
	    if [[ -f "$Fdir/config.html" ]] 
    	    then 
		getpart "$FtmpC" "$Fdir/config.html" "Configuration Data"
		if [[ ! -f $FtmpC ]]; then echo "Machine Name: $Fname" > $FtmpC; fi
		cat $FtmpC >> $Fout2

		getpart "$FtmpV" "$Fdir/config.html" "Volume Level Configuration"
		if [[ ! -f $FtmpV ]]; then echo "Machine Volume: $Fname" > $FtmpV; fi
		cat $FtmpV >> $Fout2
	    fi
	fi

        if [[ "$st_name" == "" ]]; then st_name="$Fname"; fi
        if [[ "$st_ip" == "" ]]; then st_ip="$Fip"; fi

	part0="$curdate,$Froom,$st_name"

        echo "" >> $Fout2
	echo "$part0,$st_ip,$st_os,$st_size,$st_use,$st_free,$st_wwn,$part2,$part3,$part4,$part5,$part6,$part7" >> $Fout2
        echo "---------------------------------------------" >> $Fout2
        echo "" >> $Fout2
    fi


#Xyratex
    # log file processing
    if [[ "$Fkey" == "Xyr" ]]
    then
            Fcmd=""
            if [[ "$Fpasswd" == "LOG" ]]
            then 
		Fcmd="cat $Flogin"
	    else
		Fcmd=""
	    fi
	    
	    # general storage info
	    st_name=""
	    #; st_name=$( trim "$st_name" )
	    st_os=`$Fcmd | grep "Firmware Version:" | cut -d: -f2`; st_os=$( trim "$st_os" )
	    st_ip=""
	    st_wwn=""

	    if [[ "$st_name" == "" ]]; then st_name="$Fname"; fi
	    if [[ "$st_ip" == "" ]]; then st_ip="($Fip)"; fi

	    part0="$curdate,$Froom,$st_name"

	    #---
	    # Calc total capacity, used, free by summ DiskGroups data 
	    # -- code from DiskGroup section --
	    st_size=0
	    st_use=0
	    st_free=0
	    # info about disk groups
	    dgrp_count=`$Fcmd | grep "Total Arrays:" | cut -d\  -f3 | cut -d, -f1`; dgrp_count=$( trim "$dgrp_count" )
	    for ((index=0; index<$dgrp_count; index++))
	    do
		dgrp_id="0000$index"; dgrp_id=${dgrp_id:(-2)}
		dgrp_size=`$Fcmd | grep -A 100 "Total Arrays:" | grep -B 100 "Total Logical Drives:" | tail -n +4 | grep "Array:$dgrp_id" | cut -d, -f5`; dgrp_size=$( trim "$dgrp_size" )
		dgrp_size=$( str2KB "$dgrp_size" )
		dgrp_free=0
		st_size=$(($st_size+$dgrp_size))
		st_free=$(($st_free+$dgrp_free))
		dgrp_use=$(($dgrp_size-$dgrp_free))
		st_use=$(($st_use+$dgrp_use))
	    done
    	    st_sizeKB="$st_size"
    	    st_useKB="$st_use"
    	    st_freeKB="$st_free"
    	    st_size=$( KB2str "$st_size" ) #; st_size=${st_size/" "/""}
    	    st_use=$( KB2str "$st_use" )   #; st_use=${st_use/" "/""}
    	    st_free=$( KB2str "$st_free" ) #; st_free=${st_free/" "/""}
	    #---

	    echo "$part0,$st_ip,$st_os,$st_size,$st_use,$st_free,$st_wwn,$part2,$part3,$part4,$part5,$part6,$part7" >> $Fout
	    echo "$part0,$st_ip,$st_os,$st_sizeKB,$st_useKB,$st_freeKB,$st_wwn,$part2,$part3,$part4,$part5,$part6,$part7" >> $FoutDB
            
	    
	    # info by each controller
	    ctrl=`$Fcmd | grep "Single Controller Mode:" | cut -d: -f2`; ctrl=$( trim "$ctrl" )
	    if [[ "$ctrl" != "Disabled" ]]; then ctrl=1; else ctrl=2; fi
	    ctrl_wwns=`$Fcmd | grep "Configuration WWN" | cut -d: -f2`; ctrl_wwns=$( trim "$ctrl_wwns" )
    	    index=1
    	    for ((c=1; c <= $ctrl; c++))
            do
    		for ((b=1; b <= 2; b++))
        	do
		    ctrl_wwns=`echo -n "$ctrl_wwns" | tr ' ' ':'`
		    ctrl_wwns1=${ctrl_wwns:0:1}
		    ctrl_wwns2=${ctrl_wwns:2}
    	    	    
    	    	    ctrl_id="Controller:$c"
    	    	    ctrl_wwn="${ctrl_wwns1}${index}${ctrl_wwns2}"
    	    	    ctrl_speed=""
    	    	    ctrl_status=""
    	    	    index=$(($index+1))

		    echo "$part0,$part1,$ctrl_id,$ctrl_wwn,$ctrl_speed,$ctrl_status,$part3,$part4,$part5,$part6,$part7" >> $Fout 
		    echo "$part0,$part1,$ctrl_id,$ctrl_wwn,$ctrl_speed,$ctrl_status,$part3,$part4,$part5,$part6,$part7" >> $FoutDB
        	done
            done

	    
#Enclosure Information:
#Number of Enclosures  :  1
#Total Number of Drives: 12


#Enclosure Number      :  1
#Enclosure WWN         : 20000050cc2052fc
#Drives Present        : 12
#Power Supply 01       : OK
#Power Supply 02       : OK
#Cooling Fan 01        : OK
#Cooling Fan 02        : OK
#Temperature Sensor 01 : OK | Current Temperature :27 | Status :  OK
#Temperature Sensor 02 : OK | Current Temperature :27 | Status :  OK
#Alarm 01, 0001        : The alarm is OFF.
#Audible Alarm Flags
#===================
#Enc 01 MUTE   FALSE
#DISABLE Flag  FALSE



#End Of Enclosure Information
	    # info by each enclosure
	    encl_count=`$Fcmd | grep "Number of Enclosures  :" | cut -d:  -f2`; encl_count=$( trim "$encl_count" )
    	    
	    for ((index=1; index<=$encl_count; index++))
    	    do
    	        encl_id="$index"; encl_id=$( trim "$encl_id" )
    	        encl_status=""; encl_status=$( trim "$encl_status" )
    	        encl_type=""; encl_type=$( trim "$encl_type" )
    	        encl_pn=""; encl_pn=$( trim "$encl_pn" )
    	        encl_sn=`$Fcmd | grep -A 100 "Enclosure Information:" | grep -B 100 "End Of Enclosure Information" | grep -A 13 "Enclosure Number      :  $index" | grep "Enclosure WWN" | cut -d: -f2`; encl_sn=$( trim "$encl_sn" )
    	        encl_hdd=`$Fcmd | grep -A 100 "Enclosure Information:" | grep -B 100 "End Of Enclosure Information" | grep -A 13 "Enclosure Number      :  $index" | grep "Drives Present" | cut -d: -f2`; encl_hdd=$( trim "$encl_hdd" )
		encl_speed=""; encl_speed=$( trim "$encl_speed" )

		echo "$part0,$part1,$part2,$encl_id,$encl_status,$encl_type,$encl_pn,$encl_sn,$encl_hdd,$encl_speed,$part4,$part5,$part6,$part7" >> $Fout 
		echo "$part0,$part1,$part2,$encl_id,$encl_status,$encl_type,$encl_pn,$encl_sn,$encl_hdd,$encl_speed,$part4,$part5,$part6,$part7" >> $FoutDB
	    done		
	    
#Drive List:

#Type Identifier       Product ID   Firmware Ser. No. EQRW Cap ID C EN SL ST R D
#--------------------------------------------------------------------------------
#SAS  5000c5004c2fe750 ST3300657SS      0008 6SJ27N2S YYYN 299 09 1 01 01 OK 0000
#SAS  5000c50012705ef4 ST3146356SS      XRH7 3QN0ZKAP YYYN 146 0c 1 01 02 OK 0100

#12 Drives


#Drive Command Time Log:
	    # info by hard disks
	    eval "$Fcmd | grep -A 100 \"Drive List:\" | grep -B 100 \" Drives\" | head -n -2 | tail -n +3 > $Ftmp"
	    #Type;Identifier;Product_ID;Firmware;Ser._No.;EQRW;Cap;ID;C;EN;SL;ST;R_D
	    tableconv $Ftmp "Type;Product_ID;Firmware;Ser._No.;Cap;EN;SL;ST"

	    while read 
	    do
		str=${REPLY}
    	    	disk_encl=`echo "$str" | cut -d\; -f6`; disk_encl=$( trim "$disk_encl" )
		disk_bay=`echo "$str" | cut -d\; -f7`; disk_bay=$( trim "$disk_bay" )
    	    	disk_status=`echo "$str" | cut -d\; -f8`; disk_status=$( trim "$disk_status" )
    	    	disk_type=`echo "$str" | cut -d\; -f1`; disk_type=$( trim "$disk_type" )
    	    	disk_mode=""; disk_mode=$( trim "$disk_mode" )
    	    	disk_size=`echo "$str" | cut -d\; -f5`; disk_size=$( trim "$disk_size" )
		#disk_size="$disk_size GB"
		disk_size=$( str2KB "$disk_size GB" )
		disk_sizeKB="$disk_size"
		disk_size=$( KB2str "$disk_size" )
		disk_sn=`echo "$str" | cut -d\; -f4`; disk_sn=$( trim "$disk_sn" )
		disk_speed=""; disk_speed=$( trim "$disk_speed" )
    	    	disk_pn=""; disk_pn=$( trim "$disk_pn" )

		unset str    
		echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_size,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $Fout 
		echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_sizeKB,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $FoutDB
	    done < $Ftmp
	    
	    
	    # info about disk groups
	    dgrp_count=`$Fcmd | grep "Total Arrays:" | cut -d\  -f3 | cut -d, -f1`; dgrp_count=$( trim "$dgrp_count" )
	    for ((index=0; index<$dgrp_count; index++))
	    do
		dgrp_id="0000$index"; dgrp_id=${dgrp_id:(-2)}
		dgrp_name=`$Fcmd | grep -A 100 "Total Arrays:" | grep -A 4 "Array:$dgrp_id" | grep "Array Name:" | cut -d: -f2`; dgrp_name=$( trim "$dgrp_name" )
		dgrp_status=""; dgrp_status=$( trim "$dgrp_status" )
		dgrp_size=`$Fcmd | grep -A 100 "Total Arrays:" | grep -B 100 "Total Logical Drives:" | tail -n +4 | grep "Array:$dgrp_id" | cut -d, -f5`; dgrp_size=$( trim "$dgrp_size" )
		dgrp_size=$( str2KB "$dgrp_size" )
		dgrp_free="0 B" #; dgrp_free=$( trim "$dgrp_free" )
		dgrp_sizeKB="$dgrp_size"
		dgrp_freeKB="0"
		dgrp_size=$( KB2str "$dgrp_size" )

		echo "$part0,$part1,$part2,$part3,$part4,$dgrp_name,$dgrp_status,$dgrp_size,$dgrp_free,$part6,$part7" >> $Fout
		echo "$part0,$part1,$part2,$part3,$part4,$dgrp_name,$dgrp_status,$dgrp_sizeKB,$dgrp_freeKB,$part6,$part7" >> $FoutDB
	    done
	    
	    
#Total Logical Drives: 02

#LD:000 Capacity:1781GB Regions:01 Mapped to:001 Ref:000 Blk:4096  Shared
#LD Name: vol_Array300
# REG:00 Capacity:1781GB Array:00 LBA:00000000 (0000000000->00cf6effff:cf680fff)
	    # info about volumes
	    vol_count=`$Fcmd | grep "Total Logical Drives:" | cut -d\  -f4`; vol_count=$( trim "$vol_count" )
	    for ((index=0; index<$vol_count; index++))
	    do
		vol_id="0000$index"; vol_id=${vol_id:(-3)}
		
		vol_name=`$Fcmd | grep -A 100 "Total Logical Drives:" | grep -A 2 "LD:$vol_id" | grep "LD Name:" | cut -d: -f2`; vol_name=$( trim "$vol_name" )
		vol_size=`$Fcmd | grep -A 100 "Total Logical Drives:" | grep "LD:$vol_id" | cut -d: -f3 | sed 's/ Regions//g'`; vol_size=$( trim "$vol_size" )
		vol_size=$( str2KB "$vol_size" )
		vol_sizeKB="$vol_size"
		vol_size=$( KB2str "$vol_size" )
		
		vol_array=`$Fcmd | grep -A 100 "Total Logical Drives:" | grep -A 2 "LD:$vol_id" | grep "Array:" | cut -d: -f4 | sed 's/ LBA//g'`; vol_array=$( trim "$vol_array" )
		vol_diskgrp=`$Fcmd | grep -A 100 "Total Arrays:" | grep -A 4 "Array:$vol_array" | grep "Array Name:" | cut -d: -f2`; vol_diskgrp=$( trim "$vol_diskgrp" )
        	
        	vol_status=""; vol_status=$( trim "$vol_status" )
    		vol_wwn=""; vol_wwn=$( trim "$vol_wwn" )
		vol_srvs=""
		
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_size,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $Fout
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_sizeKB,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $FoutDB
	    done
	    
	    
#Host List:

#No. Node Name        Port Name        C0P0     C0P1     C1P0     C1P1
#-------------------------------------------------------------------------
#000 20000000c98b1d07 10000000c98b1d07 001(F-?) -------- -------- --------
#001 20000000c98b1d06 10000000c98b1d06 -------- -------- 001(F-P) --------

#Host Command Time Log:
	    # info about hosts
	    eval "$Fcmd | grep -A 100 \"Host List:\" | grep -B 100 \"Host Command Time Log:\" | head -n -2 | tail -n +3 > $Ftmp"
	    #No.;Node_Name;Port_Name;C0P0;C0P1;C1P0;C1P1
	    tableconv $Ftmp "No.;Port_Name"
	    
	    while read 
	    do
		str=${REPLY}
		srv_name=`echo "$str" | cut -d\; -f1`; srv_name=$( trim "$srv_name" )
		srv_status=""; srv_status=$( trim "$srv_status" )
		srv_wwn=`echo "$str" | cut -d\; -f2`; srv_wwn=$( trim "$srv_wwn" )
		srv_wwn=`echo -n "$srv_wwn" | sed 's/../&:/g;s/:$//'`
		srv_ports=""
		#srv_vols=`$Fcmd | grep -A 100 "Total Logical Drives:" | grep -A 2 "Ref:$srv_name" | grep "LD Name:" | cut -d: -f2`; srv_vols=$( trim "$srv_vols" )
		srv_vols=""
		
    		#prepare WWN-Host info for processing
    		declare -a wh=(${srv_wwn//";"/""})
    		for ((c=0; c < ${#wh[*]}; c++)); do echo -e "${wh[$c]}\t$srv_name\t$part0" >> "$Ftmp.wwnhost"; done
		unset wh
		
		unset str    
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$part6,$srv_name,$srv_status,$srv_ports,$srv_wwn,$srv_vols" >> $Fout 
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$part6,$srv_name,$srv_status,$srv_ports,$srv_wwn,$srv_vols" >> $FoutDB
    	    done < $Ftmp
	    
	if [[ -f $Ftmp ]]; then rm $Ftmp; fi
    fi


#HP MSA P2000, Lenovo DS2200
    if [[ "$Fkey" == "MSA" ]] || [[ "$Fkey" == "LvoDS" ]]
    then
	    #FcmdSNMP="snmpwalk -v 1 -c public $Fip"
            #hpMSA		1.3.6.1.4.1.11.2.51
            #Experemental 	1.3.6.1.3.94
	    
	    #For hide: "Pseudo-terminal will not be allocated because stdin is not a terminal."
	    #v1 add /bin/bash 
	    #v2 -T Disable pseudo-tty allocation. 
            Fcmd=""
            if [[ "$Fpasswd" == "SSH" ]]
            then 
		Fcmd="ssh -T -i \"/home/$Flogin/.ssh/id_rsa\" -o \"StrictHostKeyChecking=no\" $Flogin@$Fip"
	    else
		Fcmd="sshpass -p $Fpasswd ssh -T -o \"PubkeyAuthentication=no\" -o \"StrictHostKeyChecking=no\" $Flogin@$Fip"
	    fi
	    
	    # general storage info
	    echo "set cli-parameters pager off#show system#exit#" | tr '#' '\n' > "$Ftmp.cmd"
	    eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
	    #echo "============= MSA SYSTEM =============" >> $Flog
	    #cat $Ftmp >> $Flog
	    
	    st_name=`grep "System Name:" $Ftmp | head -n 1 | cut -d: -f2`; st_name=$( trim "$st_name" )
	    st_os=`grep "Version:" $Ftmp | cut -d: -f2`; st_os=$( trim "$st_os" )
	    
	    echo "set cli-parameters pager off#show controllers#exit#" | tr '#' '\n' > "$Ftmp.cmd"
	    eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
	    st_ip=`grep "IP Address:" $Ftmp | tr ' ' '\t' | tr -s '\t' | cut -f3  | tr '\n' ';'`; st_ip=$( trim "$st_ip" )
	    if [[ ${st_ip:(-1)} == ";" ]]; then st_ip=${st_ip:0:(${#st_ip}-1)}; fi 
    	    st_ip=${st_ip//";"/"; "}
    	    #if [[ "$st_ip" != "" ]]; then st_ip="($Fip) ${st_ip}"; fi
    	    if [[ "$st_ip" != "" ]]; then st_ip=${st_ip/"$Fip"/"($Fip)"}; fi
	    
	    st_wwn=""
	    #echo "set cli-parameters pager off#show ports#exit#" | tr '#' '\n' > "$Ftmp.cmd"
	    #eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
	    #st_wwns=`grep "FC(" $Ftmp | tr ' ' '\t' | tr -s '\t' | cut -f3  | sed 's/../&:/g;s/:$//' | tr '\n' ';'`; st_wwns=$( trim "$st_wwns" )
	    #if [[ ${st_wwns:(-1)} == ";" ]]; then st_wwns=${st_wwns:0:(${#st_wwns}-1)}; fi 
    	    #st_wwns=${st_wwns//";"/"; "}
	    
	    #Midplane Serial Number: 00C0FF11ABB8

	    if [[ "$st_name" == "" ]]; then st_name="$Fname"; fi
	    if [[ "$st_ip" == "" ]]; then st_ip="($Fip)"; fi

	    part0="$curdate,$Froom,$st_name"

	    #---
	    # Calc total capacity, used, free by summ DiskGroups data 
	    # -- code from DiskGroup section --
	    # info about disk groups
    	    if [[ "$Fkey" == "MSA" ]]
    	    then
		echo "set cli-parameters pager off#show vdisks#exit#" | tr '#' '\n' > "$Ftmp.cmd"
		eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
		#echo "============= MSA DISKS GROUPS =============" >> $Flog
		#cat $Ftmp >> $Flog
		eval "grep -A 1000 \"show vdisks\" $Ftmp | grep -B 1000 \"\-\-\-\-\-\-\-\-\-\-\" | tail -n +2 | head -n -1 > $Ftmp2"
	    else
		echo "set cli-parameters pager off#show disk-groups#exit#" | tr '#' '\n' > "$Ftmp.cmd"
		eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
		#echo "============= LvDS DISKS GROUPS =============" >> $Flog
		#cat $Ftmp >> $Flog
		eval "grep -A 1000 \"show disk-groups\" $Ftmp | grep -B 1000 \"\-\-\-\-\-\-\-\-\-\-\" | tail -n +2 | head -n -1 > $Ftmp2"
	    fi
	    
	    #P2000  "Name;Size;Free;Own;Pref;RAID;Disks;Spr;Chk;Status;Jobs;Job%;Serial_Number;Drive_Spin_Down;Spin_Down_Delay;Health;Health_Reason;Health_Recommendation"
	    #DS2200 "Name;Size;Free;Pool;Tier;%_of_Pool;Own;RAID;Disks;Status;Current_Job;Job%;Sec_Fmt;Health;Reason_Action"
	    tableconv $Ftmp2 "Size;Free"
	    
	    index=0
            while read line; do
    		diskgrp[$index]="$line"
	        index=$(($index+1))
    	    done < $Ftmp2
    	                
    	    st_size=0
    	    st_use=0
    	    st_free=0
    	    for ((b=0; b < ${#diskgrp[*]}; b++))
            do
        	str="${diskgrp[$b]}"
		dgrp_size=`echo "$str" | cut -d\; -f1`; dgrp_size=$( trim "$dgrp_size" )
		dgrp_free=`echo "$str" | cut -d\; -f2`; dgrp_free=$( trim "$dgrp_free" )
		dgrp_size=$( str2KB "$dgrp_size" )
		dgrp_free=$( str2KB "$dgrp_free" )
		st_size=$(($st_size+$dgrp_size))
		st_free=$(($st_free+$dgrp_free))
		dgrp_use=$(($dgrp_size-$dgrp_free))
		st_use=$(($st_use+$dgrp_use))
	    done
    	    st_sizeKB="$st_size"
    	    st_useKB="$st_use"
    	    st_freeKB="$st_free"
    	    st_size=$( KB2str "$st_size" ) #; st_size=${st_size/" "/""}
    	    st_use=$( KB2str "$st_use" )   #; st_use=${st_use/" "/""}
    	    st_free=$( KB2str "$st_free" ) #; st_free=${st_free/" "/""}
	    #---

	    echo "$part0,$st_ip,$st_os,$st_size,$st_use,$st_free,$st_wwn,$part2,$part3,$part4,$part5,$part6,$part7" >> $Fout
	    echo "$part0,$st_ip,$st_os,$st_sizeKB,$st_useKB,$st_freeKB,$st_wwn,$part2,$part3,$part4,$part5,$part6,$part7" >> $FoutDB
	    
	    # info by each controller
	    echo "set cli-parameters pager off#show ports#exit#" | tr '#' '\n' > "$Ftmp.cmd"
	    eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
	    cat $Ftmp | grep -A 1000 "show ports" | tail -n +2 | head -n 5 | grep -B 10 "\-\-\-\-\-\-\-\-\-\-" > $Ftmp2
	    ctrl=$( cat $Ftmp2 | wc -l ); ctrl=$(($ctrl-2))
	    cat $Ftmp | grep -A ${ctrl} --no-group-separator "FC(" >> $Ftmp2
	    tableconv $Ftmp2 "Ports;Target_ID;Status;Speed(A);Health"
	    
	    index=0
            while read line; do
    		controller[$index]="$line"
	        index=$(($index+1))
    	    done < $Ftmp2
    	                
	    for ((b=0; b < ${#controller[*]}; b++))
	    do
        	str="${controller[$b]}"
    	    	ctrl_id=`echo "$str" | cut -d\; -f1`; ctrl_id=$( trim "$ctrl_id" )
    	    	ctrl_wwn=`echo "$str" | cut -d\; -f2`; ctrl_wwn=$( trim "$ctrl_wwn" )
		ctrl_wwn=`echo -n "$ctrl_wwn" | sed 's/../&:/g;s/:$//'`
    	    	ctrl_speed=`echo "$str" | cut -d\; -f4`; ctrl_speed=$( trim "$ctrl_speed" )
    	    	ctrl_status=`echo "$str" | cut -d\; -f3`; ctrl_status=$( trim "$ctrl_status" )

		echo "$part0,$part1,$ctrl_id,$ctrl_wwn,$ctrl_speed,$ctrl_status,$part3,$part4,$part5,$part6,$part7" >> $Fout 
		echo "$part0,$part1,$ctrl_id,$ctrl_wwn,$ctrl_speed,$ctrl_status,$part3,$part4,$part5,$part6,$part7" >> $FoutDB
            done
            unset controller
	    
	    # info by each enclosure
	    echo "set cli-parameters pager off#show enclosures#exit#" | tr '#' '\n' > "$Ftmp.cmd"
	    eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
	    #echo "============= MSA ENCLOSURES =============" >> $Flog
	    #cat $Ftmp >> $Flog
	    eval "grep -A 1000 \"show enclosures\" $Ftmp | grep -B 1000 \"\-\-\-\-\-\-\-\-\-\-\" | tail -n +2 | head -n -1 > $Ftmp2"
	    #P2000  "Encl;Encl_WWN;Name;Location;Rack;Pos;Vendor;Model;EMP_A;CH:ID;Rev;EMP_B;CH:ID;Rev;Midplane_Type;Health;Health_Reason;Health_Recommendation"
	    #DS2200 "Encl;Encl_WWN;Name;Location;Rack;Pos;Vendor;Model;EMP_A;CH:ID;Rev;EMP_B;CH:ID;Rev;Midplane_Type;Health;Reason_Action"
	    tableconv $Ftmp2 "Encl;Model;Rev;Midplane_Type;Health"
	    
	    index=0
            while read line; do
    		enclosure[$index]="$line"
	        index=$(($index+1))
    	    done < $Ftmp2
    	                
    	    for ((b=0; b < ${#enclosure[*]}; b++))
            do
        	str="${enclosure[$b]}"
    	        encl_id=`echo "$str" | cut -d\; -f1`; encl_id=$( trim "$encl_id" )
    	        encl_status=`echo "$str" | cut -d\; -f5`; encl_status=$( trim "$encl_status" )
    	        encl_type=`echo "$str" | cut -d\; -f2`; encl_type=$( trim "$encl_type" )
    	        encl_pn=`echo "$str" | cut -d\; -f3`; encl_pn=$( trim "$encl_pn" )
    	        encl_sn=""
    	        encl_hdd=""
		encl_speed=`echo "$str" | cut -d\; -f4`; encl_speed=$( trim "$encl_speed" )

		echo "$part0,$part1,$part2,$encl_id,$encl_status,$encl_type,$encl_pn,$encl_sn,$encl_hdd,$encl_speed,$part4,$part5,$part6,$part7" >> $Fout 
		echo "$part0,$part1,$part2,$encl_id,$encl_status,$encl_type,$encl_pn,$encl_sn,$encl_hdd,$encl_speed,$part4,$part5,$part6,$part7" >> $FoutDB
        	unset encl
            done
            unset enclosure
		
	    
	    # info by hard disks
	    echo "set cli-parameters pager off#show disks#exit#" | tr '#' '\n' > "$Ftmp.cmd"
	    eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
	    #echo "============= MSA DISKS =============" >> $Flog
	    #cat $Ftmp >> $Flog
	    eval "grep -A 1000 \"show disks\" $Ftmp | grep -B 1000 \"\-\-\-\-\-\-\-\-\-\-\" | tail -n +2 | head -n -1 > $Ftmp2"
	    #P2000  "Location;Serial_Number;Vendor;Rev;How_Used;Type;Size;Rate*(Gb/s)_SP;Health;Health_Reason;Health_Recommendation"
	    #DS2200 "Location;Serial_Number;Vendor;Rev;Description;Usage;Jobs;Speed_(kr/min);Size;Sec_Fmt;Disk_Group;Pool;Tier;Health"
    	    if [[ "$Fkey" == "MSA" ]]
    	    then
		tableconv $Ftmp2 "Location;Serial_Number;Rev;Type;How_Used;Rate*(Gb/s)_SP;Size;Health"
	    else
		tableconv $Ftmp2 "Location;Serial_Number;Rev;Description;Usage;Speed_(kr/min);Size;Health"
	    fi
	    
	    unset harddisk
	    index=0
            while read line; do
    		harddisk[$index]="$line"
	        index=$(($index+1))
    	    done < $Ftmp2

    	    for ((b=0; b < ${#harddisk[*]}; b++))
            do
        	str="${harddisk[$b]}"
		
		disk_id=$(($b+1))
    	    	disk_pos=`echo "$str" | cut -d\; -f1`; disk_pos=$( trim "$disk_pos" )
    	    	disk_encl=`echo "$disk_pos" | cut -d. -f1`; disk_encl=$( trim "$disk_encl" )
		disk_bay=`echo "$disk_pos" | cut -d. -f2`; disk_bay=$( trim "$disk_bay" )
		disk_sn=`echo "$str" | cut -d\; -f2`; disk_sn=$( trim "$disk_sn" )
    	    	disk_pn=`echo "$str" | cut -d\; -f3`; disk_pn=$( trim "$disk_pn" )
    	    	disk_status=`echo "$str" | cut -d\; -f8`; disk_status=$( trim "$disk_status" )
    	    	disk_mode=`echo "$str" | cut -d\; -f5`; disk_mode=$( trim "$disk_mode" )
    	    	disk_type=`echo "$str" | cut -d\; -f4`; disk_type=$( trim "$disk_type" )
    	    	disk_size=`echo "$str" | cut -d\; -f7`; disk_size=$( trim "$disk_size" )
		disk_size=$( str2KB "$disk_size" )
		disk_sizeKB="$disk_size"
		disk_size=$( KB2str "$disk_size" )

		disk_speed=`echo "$str" | cut -d\; -f6`; disk_speed=$( trim "$disk_speed" )
    		if [[ "$Fkey" == "MSA" ]]
    		then
		    disk_speed="${disk_speed}Gb/s"
		else
		    disk_speed="${disk_speed}000RPM"
		fi
		
		echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_size,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $Fout 
		echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_sizeKB,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $FoutDB 
        	unset disk
            done
            unset harddisk
	    
	    
	    # info about disk groups
    	    if [[ "$Fkey" == "MSA" ]]
    	    then
		echo "set cli-parameters pager off#show vdisks#exit#" | tr '#' '\n' > "$Ftmp.cmd"
		eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
		#echo "============= MSA DISKS GROUPS =============" >> $Flog
		#cat $Ftmp >> $Flog
		eval "grep -A 1000 \"show vdisks\" $Ftmp | grep -B 1000 \"\-\-\-\-\-\-\-\-\-\-\" | tail -n +2 | head -n -1 > $Ftmp2"
	    else
		echo "set cli-parameters pager off#show disk-groups#exit#" | tr '#' '\n' > "$Ftmp.cmd"
		eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
		#echo "============= LvDS DISKS GROUPS =============" >> $Flog
		#cat $Ftmp >> $Flog
		eval "grep -A 1000 \"show disk-groups\" $Ftmp | grep -B 1000 \"\-\-\-\-\-\-\-\-\-\-\" | tail -n +2 | head -n -1 > $Ftmp2"
	    fi
	    
	    #P2000  "Name;Size;Free;Own;Pref;RAID;Disks;Spr;Chk;Status;Jobs;Job%;Serial_Number;Drive_Spin_Down;Spin_Down_Delay;Health;Health_Reason;Health_Recommendation"
	    #DS2200 "Name;Size;Free;Pool;Tier;%_of_Pool;Own;RAID;Disks;Status;Current_Job;Job%;Sec_Fmt;Health;Reason_Action"
	    tableconv $Ftmp2 "Name;Size;Free;Status"
	    
	    index=0
            while read line; do
    		diskgrp[$index]="$line"
	        index=$(($index+1))
    	    done < $Ftmp2
    	                
    	    for ((b=0; b < ${#diskgrp[*]}; b++))
            do
        	str="${diskgrp[$b]}"
		dgrp_name=`echo "$str" | cut -d\; -f1`; dgrp_name=$( trim "$dgrp_name" )
		dgrp_status=`echo "$str" | cut -d\; -f4`; dgrp_status=$( trim "$dgrp_status" )
		dgrp_size=`echo "$str" | cut -d\; -f2`; dgrp_size=$( trim "$dgrp_size" )
		dgrp_size=$( str2KB "$dgrp_size" )
		dgrp_free=`echo "$str" | cut -d\; -f3`; dgrp_free=$( trim "$dgrp_free" )
		dgrp_free=$( str2KB "$dgrp_free" )
		dgrp_sizeKB="$dgrp_size"
		dgrp_freeKB="$dgrp_free"
		dgrp_size=$( KB2str "$dgrp_size" )
		dgrp_free=$( KB2str "$dgrp_free" )

		echo "$part0,$part1,$part2,$part3,$part4,$dgrp_name,$dgrp_status,$dgrp_size,$dgrp_free,$part6,$part7" >> $Fout
		echo "$part0,$part1,$part2,$part3,$part4,$dgrp_name,$dgrp_status,$dgrp_sizeKB,$dgrp_freeKB,$part6,$part7" >> $FoutDB
            done
            unset diskgrp
	    
	    
	    # info about volumes
	    echo "set cli-parameters pager off#show host-maps#exit#" | tr '#' '\n' > "$Ftmp.cmd"
	    eval "$Fcmd < $Ftmp.cmd > $FtmpC"; wait
	    echo "set cli-parameters pager off#show volume-maps#exit#" | tr '#' '\n' > "$Ftmp.cmd"
	    eval "$Fcmd < $Ftmp.cmd > $FtmpV"; wait
	    ###
	    echo "set cli-parameters pager off#show volumes#exit#" | tr '#' '\n' > "$Ftmp.cmd"
	    eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
	    #echo "============= MSA VOLUMES =============" >> $Flog
	    #cat $Ftmp >> $Flog
	    eval "grep -A 1000 \"show volumes\" $Ftmp | grep -B 1000 \"\-\-\-\-\-\-\-\-\-\-\" | tail -n +2 | head -n -1 > $Ftmp2"
	    #P2000  "Vdisk;Name;Size;Serial_Number;WR_Policy;Cache_Opt;Read_Ahead_Size;Type;Class;Qualifier;Volume_Description;WWN;Health;Health_Reason;Health_Recommendation"
	    #DS2200 "Pool;Name;Total_Size;Alloc_Size;Type;Large_Virtual_Extents;Health;Reason_Action"
    	    if [[ "$Fkey" == "MSA" ]]
    	    then
		tableconv $Ftmp2 "Vdisk;Name;Size;Health;WWN"
	    else
		tableconv $Ftmp2 "Pool;Name;Total_Size;Health"
	    fi
	    
	    vol_func=""
    	    vol_wwn=""
	    
	    echo -n > "$Ftmp.volume"
	    while read 
	    do
		str=${REPLY}
		vol_name=`echo "$str" | cut -d\; -f2`; vol_name=$( trim "$vol_name" )
		vol_diskgrp=`echo "$str" | cut -d\; -f1`; vol_diskgrp=$( trim "$vol_diskgrp" )
        	vol_status=`echo "$str" | cut -d\; -f4`; vol_status=$( trim "$vol_status" )
		vol_size=`echo "$str" | cut -d\; -f3`; vol_size=$( trim "$vol_size" )
		vol_size=$( str2KB "$vol_size" )
		vol_sizeKB="$vol_size"
		vol_size=$( KB2str "$vol_size" )
    		
    		if [[ "$Fkey" == "MSA" ]]
    		then 
    		    vol_wwn=`echo "$str" | cut -d\; -f5`; vol_wwn=$( trim "$vol_wwn" )
    		    vol_wwn="${vol_wwn,,}"
        	fi
        	
    		if [[ "$Fkey" == "LvoDS" ]]
    		then 
		    echo "set cli-parameters pager off#show provisioning no-mapping#exit#" | tr '#' '\n' > "$Ftmp.cmd"
		    eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
		    eval "grep -A 1000 \"show provisioning no-mapping\" $Ftmp | grep -B 1000 \"\-\-\-\-\-\-\-\-\-\-\" | tail -n +2 | head -n -1 > \"$Ftmp.volwwn\""
		    tableconv "$Ftmp.volwwn" "Volume;WWN"
		    vol_wwn=$( cat "$Ftmp.volwwn" | grep "$vol_name" | cut -d\;  -f2 ); vol_wwn=$( trim "$vol_wwn" )
    		    vol_wwn="${vol_wwn,,}"
        	fi
        	
		echo "set cli-parameters pager off#show volume-maps ${vol_name}#exit#" | tr '#' '\n' > "$Ftmp.cmd"
		eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
		vol_srvs=$( cat $Ftmp | grep "read-write" | tr -s ' ' | cut -d\  -f6 | tr '\n' ';' )
    		if [[ "$vol_srvs" != "" ]]; then vol_srvs="${vol_srvs:0:(${#vol_srvs}-1)}"; fi
		vol_srvs=${vol_srvs//";"/"; "}

    		declare -a hosts=(${vol_srvs//";"/""})
    		for ((b=0; b < ${#hosts[*]}; b++))
        	do
		    echo "$vol_name#${hosts[$b]}#" >> "$Ftmp.volume"
		done
		unset hosts
		
		unset str
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_size,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $Fout
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_sizeKB,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $FoutDB
	    done < $Ftmp2
	    
	    
	    # info about hosts
	    echo "set cli-parameters pager off#show hosts#exit#" | tr '#' '\n' > "$Ftmp.cmd"
	    eval "$Fcmd < $Ftmp.cmd > $Ftmp"; wait
	    #echo "============= MSA HOSTS =============" >> $Flog
	    #cat $Ftmp >> $Flog
	    eval "grep -A 1000 \"show hosts\" $Ftmp | grep -B 1000 \"\-\-\-\-\-\-\-\-\-\-\" | tail -n +2 | head -n -1 > $Ftmp2"
	    #P2000  "Host_ID;Name;Discovered;Mapped;Profile;Host_Type"
	    #DS2200 "Host_ID;Host_Name;Discovered;Mapped;Profile;Host_Type"
    	    if [[ "$Fkey" == "MSA" ]]
    	    then
		tableconv $Ftmp2 "Host_ID;Name;Discovered"
	    else
		tableconv $Ftmp2 "Host_ID;Host_Name;Discovered"
	    fi

	    while read 
	    do
		str=${REPLY}
		srv_name=`echo "$str" | cut -d\; -f2`; srv_name=$( trim "$srv_name" )
		#if [[ "$srv_name" == "" ]]; then continue; fi
		srv_status=`echo "$str" | cut -d\; -f3`; srv_status=$( trim "$srv_status" )
		srv_wwn=`echo "$str" | cut -d\; -f1`; srv_wwn=$( trim "$srv_wwn" )
		srv_wwn=$(echo $srv_wwn | sed 's/../&:/g;s/:$//')
		srv_ports="1"
		srv_vols=""
        	
    	        srv_vols=$( cat "$Ftmp.volume" | grep "#$srv_name#" | cut -d# -f1 | tr '\n' ';' )
		if [[ ${srv_vols:(-1)} == ";" ]]; then srv_vols=${srv_vols:0:(${#srv_vols}-1)}; fi 
    		srv_vols=${srv_vols//";"/"; "}
		
    		#prepare WWN-Host info for processing
		# proccessing HostName_A or HostName_B
		srv_name2="$srv_name"; sufix="";
    		if [[ ${#srv_name2} -gt 2 ]]; then sufix=${srv_name2:(${#srv_name2}-2)}; fi
    		if [[ "$sufix" == "_A" ]] || [[ "$sufix" == "_B" ]]; then srv_name2=${srv_name2:0:${#srv_name2}-2}; fi
    		declare -a wh=(${srv_wwn//";"/""})
    		for ((c=0; c < ${#wh[*]}; c++)); do echo -e "${wh[$c]}\t$srv_name2\t$part0" >> "$Ftmp.wwnhost"; done
		unset wh
		
		unset str    
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$part6,$srv_name,$srv_status,$srv_ports,$srv_wwn,$srv_vols" >> $Fout 
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$part6,$srv_name,$srv_status,$srv_ports,$srv_wwn,$srv_vols" >> $FoutDB
	    done < $Ftmp2

	if [[ -f $Ftmp2 ]]; then rm $Ftmp2; fi
	if [[ -f "$Ftmp.cmd" ]]; then rm "$Ftmp.cmd"; fi
	if [[ -f "$Ftmp.volume" ]]; then rm "$Ftmp.volume"; fi
	if [[ -f "$Ftmp.volwwn" ]]; then rm "$Ftmp.volwwn"; fi
    fi

    
#NetApp 7-mode
    if [[ "$Fkey" == "NAp" ]]
    then
	    FcmdSNMP="snmpwalk -v 1 -c public $Fip"
            Fcmd=""
            if [[ "$Fpasswd" == "SSH" ]]
            then 
		Fcmd="ssh -i \"/home/$Flogin/.ssh/id_rsa\" -o \"StrictHostKeyChecking no\" $Flogin@$Fip"
	    else
		Fcmd="sshpass -p $Fpasswd ssh -o \"PubkeyAuthentication=no\" -o \"StrictHostKeyChecking=no\" $Flogin@$Fip"
	    fi
	    
	    # general storage info
	    #eval "$Fcmd \"sysconfig\" > $Ftmp"
    
	    st_name=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.7.1.3.0" | cut -d\" -f2 )
	    st_os=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.1.2.0" | cut -d\" -f2 | cut -d: -f1 )

	    st_ip=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.16.4.1.3" | cut -d\: -f4 | sed 's/^[ \t]*//' | tr '\n' ';' ); st_ip=$( trim "$st_ip" )
	    if [[ ${st_ip:(-1)} == ";" ]]; then st_ip=${st_ip:0:(${#st_ip}-1)}; fi 
    	    st_ip=${st_ip//";"/"; "}
    	    #if [[ "$st_ip" != "" ]]; then st_ip="($Fip) ${st_ip}"; fi
    	    if [[ "$st_ip" != "" ]]; then st_ip=${st_ip/"$Fip"/"($Fip)"}; fi
	    
    	    st_wwn=""
	    #st_wwns=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.17.1.1.4" | cut -d\" -f2 | tr '\n' ';' ); st_wwns=$( trim "$st_wwns" )
	    #if [[ ${st_wwns:(-1)} == ";" ]]; then st_wwns=${st_wwns:0:(${#st_wwns}-1)}; fi 
    	    #st_wwns=${st_wwns//";"/"; "}
    	    
	    if [[ "$st_name" == "" ]]; then st_name="$Fname"; fi
	    if [[ "$st_ip" == "" ]]; then st_ip="($Fip)"; fi

	    part0="$curdate,$Froom,$st_name"

	    #---
	    # Calc total capacity, used, free by summ DiskGroups data 
	    # -- code from DiskGroup section --
	    # info about disk groups
    	    st_size=0
    	    st_use=0
    	    st_free=0
	    diskgrp=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.12" | cut -d: -f4 ); diskgrp=$( trim "$diskgrp" )
    	    for ((b=0; b < $diskgrp; b++))
            do
    	        dgrp_id=$(($b+1))
		
		dgrp_name=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.11.1.2.$dgrp_id" | cut -d\" -f2 )
		
		dflist=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.1" | wc -l )
        	for ((c=0; c < $dflist; c++))
	        do
    	    	    df_id=$(($c+1))
		    df_name=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.2.$df_id" | cut -d\" -f2 )
		    if [[ "$dgrp_name" != "$df_name"  ]]; then continue; fi
		    
		    valH=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.14.$df_id" | cut -d: -f4 ); valH=$( trim "$valH" )
		    valL=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.15.$df_id" | cut -d: -f4 ); valL=$( trim "$valL" )
		    dgrp_size=$( value64bit $valH $valL )
		
		    valH=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.18.$df_id" | cut -d: -f4 ); valH=$( trim "$valH" )
		    valL=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.19.$df_id" | cut -d: -f4 ); valL=$( trim "$valL" )
		    dgrp_free=$( value64bit $valH $valL )
		    
		    st_size=$(($st_size+$dgrp_size))
		    st_free=$(($st_free+$dgrp_free))
		    dgrp_use=$(($dgrp_size-$dgrp_free))
		    st_use=$(($st_use+$dgrp_use))
		    break
		done
	    done
    	    st_sizeKB="$st_size"
    	    st_useKB="$st_use"
    	    st_freeKB="$st_free"
    	    st_size=$( KB2str "$st_size" ) #; st_size=${st_size/" "/""}
    	    st_use=$( KB2str "$st_use" )   #; st_use=${st_use/" "/""}
    	    st_free=$( KB2str "$st_free" ) #; st_free=${st_free/" "/""}
	    #---
	    
	    echo "$part0,$st_ip,$st_os,$st_size,$st_use,$st_free,$st_wwn,$part2,$part3,$part4,$part5,$part6,$part7" >> $Fout
	    echo "$part0,$st_ip,$st_os,$st_sizeKB,$st_useKB,$st_freeKB,$st_wwn,$part2,$part3,$part4,$part5,$part6,$part7" >> $FoutDB
            
	    
	    # info by each controller
	    ctrl=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.17.1.1.1" | wc -l )
    	    for ((b=1; b <= $ctrl; b++))
            do
    		ctrl_id=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.17.1.1.2.$b" | cut -d\" -f2 | tr '[:lower:]' '[:upper:]' ); ctrl_id=$( trim "$ctrl_id" )
    		#ctrl_id="Port:$ctrl_id"
    		ctrl_wwn=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.17.1.1.4.$b" | cut -d\" -f2 ); ctrl_wwn=$( trim "$ctrl_wwn" )
    		ctrl_speed=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.17.1.1.5.$b" |  cut -d: -f4 ); ctrl_speed=$( trim "$ctrl_speed" )
    		if [[ "$ctrl_speed" != "0" ]]; then ctrl_speed="${ctrl_speed}Gb"; else ctrl_speed=""; fi
    		ctrl_status=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.17.1.1.6.$b" |  cut -d: -f4 ); ctrl_status=$( trim "$ctrl_status" )
		if [[ "$ctrl_status" == "1" ]]; then ctrl_status="startup"; fi
		if [[ "$ctrl_status" == "2" ]]; then ctrl_status="uninitialized"; fi
		if [[ "$ctrl_status" == "3" ]]; then ctrl_status="initializingFW"; fi
		if [[ "$ctrl_status" == "4" ]]; then ctrl_status="linkNotConnected"; fi
		if [[ "$ctrl_status" == "5" ]]; then ctrl_status="waitingForLinkUp"; fi
		if [[ "$ctrl_status" == "6" ]]; then ctrl_status="online"; fi
		if [[ "$ctrl_status" == "7" ]]; then ctrl_status="linkDisconnected"; fi
		if [[ "$ctrl_status" == "8" ]]; then ctrl_status="resetting"; fi
		if [[ "$ctrl_status" == "9" ]]; then ctrl_status="offline"; fi
		if [[ "$ctrl_status" == "10" ]]; then ctrl_status="offlinedByUserSystem"; fi
                                                                                    			    		        		        		        		        		        		        		                                                      
		echo "$part0,$part1,$ctrl_id,$ctrl_wwn,$ctrl_speed,$ctrl_status,$part3,$part4,$part5,$part6,$part7" >> $Fout 
		echo "$part0,$part1,$ctrl_id,$ctrl_wwn,$ctrl_speed,$ctrl_status,$part3,$part4,$part5,$part6,$part7" >> $FoutDB
            done

	    
	    # info by each enclosure
	    enclosure=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.21.1.1.0" | cut -d: -f4 ); enclosure=$( trim "$enclosure" )
    	    for ((b=0; b < $enclosure; b++))
            do
		encl_id=$(($b+1))
		encl_status=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.21.1.2.1.2.$encl_id" | cut -d: -f4 ); encl_status=$( trim "$encl_status" )
		if [[ "$encl_status" == "1" ]]; then encl_status="initializing"; fi
		if [[ "$encl_status" == "2" ]]; then encl_status="transitioning"; fi
		if [[ "$encl_status" == "3" ]]; then encl_status="active"; fi
		if [[ "$encl_status" == "4" ]]; then encl_status="inactive"; fi
		if [[ "$encl_status" == "5" ]]; then encl_status="reconfiguring"; fi
		if [[ "$encl_status" == "6" ]]; then encl_status="nonexistent"; fi
		encl_type=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.21.1.2.1.3.$encl_id" | cut -d\" -f2 ); encl_type=$( trim "$encl_type" )
		encl_pn=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.21.1.2.1.7.$encl_id" | cut -d\" -f2 ); encl_pn=$( trim "$encl_pn" )
		encl_sn=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.21.1.2.1.9.$encl_id" | cut -d\" -f2 ); encl_sn=$( trim "$encl_sn" )
		encl_hdd=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.21.1.2.1.10.$encl_id" | cut -d: -f4 ); encl_hdd=$( trim "$encl_hdd" )
		encl_speed=""
		
		echo "$part0,$part1,$part2,$encl_id,$encl_status,$encl_type,$encl_pn,$encl_sn,$encl_hdd,$encl_speed,$part4,$part5,$part6,$part7" >> $Fout 
		echo "$part0,$part1,$part2,$encl_id,$encl_status,$encl_type,$encl_pn,$encl_sn,$encl_hdd,$encl_speed,$part4,$part5,$part6,$part7" >> $FoutDB
	    done
	    
	    
	    # info by hard disks
	    # Summary hard disk count 
	    #[root@stor2rrd ~]# snmpwalk -v 1 -c public 10.100.0.246 1.3.6.1.4.1.789.1.6.4.1.0
	    #SNMPv2-SMI::enterprises.789.1.6.4.1.0 = INTEGER: 24
	    # RAID disks
	    # disks by volumes, need scan
	    diskvols=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.5" | cut -d: -f4 ); diskvols=$( trim "$diskvols" )
    	    for ((c=1; c <= $diskvols; c++))
            do
		dvol=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.2.1.1.$c" | wc -l )
    		for ((b=0; b < $dvol; b++))
        	do
		    disk_id=$(($b+1))
    	    	    disk_encl=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.2.1.19.$c.1.$disk_id" | cut -d: -f4 ); disk_encl=$( trim "$disk_encl" )
		    disk_bay=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.2.1.20.$c.1.$disk_id" | cut -d: -f4 ); disk_bay=$( trim "$disk_bay" )
    	        
    	    	    disk_status=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.2.1.3.$c.1.$disk_id" | cut -d: -f4 ); disk_status=$( trim "$disk_status" )
		    if [[ "$disk_status" == "1" ]]; then disk_status="active"; fi
		    if [[ "$disk_status" == "2" ]]; then disk_status="reconstructionInProgress"; fi
		    if [[ "$disk_status" == "3" ]]; then disk_status="parityReconstructionInProgress"; fi
		    if [[ "$disk_status" == "4" ]]; then disk_status="parityVerificationInProgress"; fi
		    if [[ "$disk_status" == "5" ]]; then disk_status="scrubbingInProgress"; fi
		    if [[ "$disk_status" == "6" ]]; then disk_status="failed"; fi
		    if [[ "$disk_status" == "9" ]]; then disk_status="prefailed"; fi
		    if [[ "$disk_status" == "10" ]]; then disk_status="offline"; fi
    	        
    	    	    disk_mode=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.2.1.2.$c.1.$disk_id" | cut -d\" -f2 ); disk_mode=$( trim "$disk_mode" )
    	    	    disk_type=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.2.1.31.$c.1.$disk_id" | cut -d\" -f2 ); disk_type=$( trim "$disk_type" )
    	        
    	    	    disk_size=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.2.1.9.$c.1.$disk_id" | cut -d: -f4 ); disk_size=$( trim "$disk_size" )
    	    	    #disk_size=$( printf "%.1fGB" $(($disk_size/1024)) )
		    disk_size=$( str2KB "$disk_size MB" )
		    disk_sizeKB="$disk_size"
		    disk_size=$( KB2str "$disk_size" )
		
		    disk_speed=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.2.1.30.$c.1.$disk_id" | cut -d\" -f2 ); disk_speed=$( trim "$disk_speed" ); disk_speed="${disk_speed}RPM"
    	    	    disk_pn=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.2.1.28.$c.1.$disk_id" | cut -d\" -f2 ); disk_pn=$( trim "$disk_pn" )
    	    	    disk_sn=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.2.1.26.$c.1.$disk_id" | cut -d\" -f2 ); disk_sn=$( trim "$disk_sn" )
		
		    echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_size,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $Fout 
		    echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_sizeKB,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $FoutDB
        	done
	    done	    
	    # Spare disks
	    harddisk=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.4.8.0" | cut -d: -f4 ); harddisk=$( trim "$harddisk" )
    	    for ((b=0; b < $harddisk; b++))
            do
		disk_id=$(($b+1))
    	        disk_encl=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.3.1.12.$disk_id" | cut -d: -f4 ); disk_encl=$( trim "$disk_encl" )
		disk_bay=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.3.1.13.$disk_id" | cut -d: -f4 ); disk_bay=$( trim "$disk_bay" )
    	        
    	        disk_status=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.3.1.3.$disk_id" | cut -d: -f4 ); disk_status=$( trim "$disk_status" )
		if [[ "$disk_status" == "1" ]]; then disk_status="spare"; fi
		if [[ "$disk_status" == "2" ]]; then disk_status="addingspare"; fi
		if [[ "$disk_status" == "3" ]]; then disk_status="bypassed"; fi
		if [[ "$disk_status" == "4" ]]; then disk_status="unknown"; fi
		if [[ "$disk_status" == "10" ]]; then disk_status="offline"; fi
    	        
    	        disk_mode=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.3.1.2.$disk_id" | cut -d\" -f2 ); disk_mode=$( trim "$disk_mode" )
    	        disk_type=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.3.1.21.$disk_id" | cut -d\" -f2 ); disk_type=$( trim "$disk_type" )
    	        
    	        disk_size=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.3.1.7.$disk_id" | cut -d: -f4 ); disk_size=$( trim "$disk_size" )
    	        #disk_size=$( printf "%.1fGB" $(($disk_size/1024)) )
		disk_size=$( str2KB "$disk_size MB" )
		disk_sizeKB="$disk_size"
		disk_size=$( KB2str "$disk_size" )
		
		disk_speed=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.3.1.20.$disk_id" | cut -d\" -f2 ); disk_speed=$( trim "$disk_speed" ); disk_speed="${disk_speed}RPM"
    	        disk_pn=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.3.1.18.$disk_id" | cut -d\" -f2 ); disk_pn=$( trim "$disk_pn" )
    	        disk_sn=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.6.3.1.16.$disk_id" | cut -d\" -f2 ); disk_sn=$( trim "$disk_sn" )
		
		echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_size,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $Fout 
		echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_sizeKB,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $FoutDB
            done
	    
	    
	    # info about disk groups
	    diskgrp=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.12" | cut -d: -f4 ); diskgrp=$( trim "$diskgrp" )
    	    for ((b=0; b < $diskgrp; b++))
            do
    	        dgrp_id=$(($b+1))
		
		dgrp_name=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.11.1.2.$dgrp_id" | cut -d\" -f2 )
		dgrp_status=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.11.1.5.$dgrp_id" | cut -d\" -f2 )
		
		dgrp_size="0 B"
		dgrp_free="0 B"
		dgrp_sizeKB="0"
		dgrp_freeKB="0"
		dflist=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.1" | wc -l )
        	for ((c=0; c < $dflist; c++))
	        do
    	    	    df_id=$(($c+1))
		    df_name=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.2.$df_id" | cut -d\" -f2 )
		    if [[ "$dgrp_name" != "$df_name"  ]]; then continue; fi
		    
		    valH=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.14.$df_id" | cut -d: -f4 ); valH=$( trim "$valH" )
		    valL=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.15.$df_id" | cut -d: -f4 ); valL=$( trim "$valL" )
		    dgrp_size=$( value64bit $valH $valL )
		
		    valH=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.18.$df_id" | cut -d: -f4 ); valH=$( trim "$valH" )
		    valL=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.19.$df_id" | cut -d: -f4 ); valL=$( trim "$valL" )
		    dgrp_free=$( value64bit $valH $valL )
		    
		    dgrp_sizeKB="$dgrp_size"
		    dgrp_freeKB="$dgrp_free"
		    dgrp_size=$( KB2str "$dgrp_size" ) #; dgrp_size=${dgrp_size/" "/""}
		    dgrp_free=$( KB2str "$dgrp_free" ) #; dgrp_free=${dgrp_free/" "/""}
		    break
		done
		
		echo "$part0,$part1,$part2,$part3,$part4,$dgrp_name,$dgrp_status,$dgrp_size,$dgrp_free,$part6,$part7" >> $Fout
		echo "$part0,$part1,$part2,$part3,$part4,$dgrp_name,$dgrp_status,$dgrp_sizeKB,$dgrp_freeKB,$part6,$part7" >> $FoutDB
	    done
	    
	    
	    # info about volumes
	    volum=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.9" | cut -d: -f4 ); volum=$( trim "$volum" )
    	    for ((b=0; b < $volum; b++))
            do
    	        vol_id=$(($b+1))
		vol_name=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.8.1.2.$vol_id" | cut -d\" -f2 )
		vol_status=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.8.1.5.$vol_id" | cut -d\" -f2 )
		
		#vol_size=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.8.1.3.$vol_id" | cut -d\" -f2 );...
		vol_size="0 B"
		vol_sizeKB="0"
		dflist=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.1" | wc -l )
        	for ((c=0; c < $dflist; c++))
	        do
    	    	    df_id=$(($c+1))
		    df_name=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.2.$df_id" | cut -d\" -f2 )
		    if [[ "/vol/${vol_name}/" != "$df_name"  ]]; then continue; fi
		    
		    valH=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.14.$df_id" | cut -d: -f4 ); valH=$( trim "$valH" )
		    valL=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.4.1.15.$df_id" | cut -d: -f4 ); valL=$( trim "$valL" )
		    vol_size=$( value64bit $valH $valL )
		    vol_sizeKB="$vol_size"
		    vol_size=$( KB2str "$vol_size" ) #; vol_size=${vol_size/" "/""}
		
		    break
		done
		
		#vol_wwn=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.8.1.8.$vol_id" | cut -d\" -f2 )
		vol_wwn=""
		vol_diskgrp=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.8.1.9.$vol_id" | cut -d\" -f2 )
		vol_func="volume"
		vol_srvs=""

		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_size,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $Fout
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_sizeKB,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $FoutDB
	    done
	    
	    # info about LUNs
	    #out mapping
	    echo -n > "$Ftmp.volume"
	    echo -n > "$Ftmp.host"
	    unset volum
	    unset maphost
	    declare -a volum=($( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.15.3.1.3" | cut -d\" -f2 ))
	    declare -a maphost=($( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.15.3.1.4" | cut -d\" -f2 ))
    	    for ((b=0; b < ${#volum[*]}; b++))
            do
		echo "${volum[$b]}#${maphost[$b]}#" >> "$Ftmp.volume"
		echo "${maphost[$b]}#${volum[$b]}#" >> "$Ftmp.host"
	    done   
	    unset volum
	    unset maphost
	    #proccessing LUNs
	    #volum=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.15.1.0" | cut -d: -f4 ); volum=$( trim "$volum" )
	    declare -a volum=($( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.15.2.1.1" | cut -d: -f4 | tr ' ' '\t' | cut -f2 ))
    	    for ((b=0; b < ${#volum[*]}; b++))
            do
    	        vol_id=${volum[$b]}
		vol_name=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.15.2.1.2.$vol_id" | cut -d\" -f2 )
		
		vol_status=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.15.2.1.17.$vol_id" | cut -d: -f4 ); vol_status=$( trim "$vol_status" )
		if [[ "$vol_status" == "1" ]]; then vol_status="offline"; else vol_status="online"; fi
		
		valH=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.15.2.1.5.$vol_id" | cut -d: -f4 ); valH=$( trim "$valH" )
		valL=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.15.2.1.4.$vol_id" | cut -d: -f4 ); valL=$( trim "$valL" )
		vol_size=$( value64bit $valH $valL ); 
		#volume size in Bytes
		vol_size=$( str2KB "$vol_size" )
		vol_sizeKB="$vol_size"
		vol_size=$( KB2str "$vol_size" ) #; vol_size=${vol_size/" "/""}
		
		vol_wwn=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.15.2.1.7.$vol_id" | cut -d\" -f2 )
		vol_wwn=$( echo -n "$vol_wwn" | xxd -ps -c 200 | tr -d '\n' ); 
		#add prefix NetApp 7-mode
		vol_wwn="360a98000${vol_wwn}"
		
		vol_diskgrp=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.15.2.1.8.$vol_id" | cut -d\" -f2 )
		vol_func="lun"
		
    	        vol_srvs=$( cat "$Ftmp.host" | grep "#$vol_name#" | cut -d# -f1 | tr '\n' ';' )
		if [[ ${vol_srvs:(-1)} == ";" ]]; then vol_srvs=${vol_srvs:0:(${#vol_srvs}-1)}; fi 
    		vol_srvs=${vol_srvs//";"/"; "}

		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_size,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $Fout
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_sizeKB,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $FoutDB
	    done
	    unset volum

	    # info about qtree (CIFS)
	    declare -a volum=($( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.10.1.3" | cut -d\" -f2 ))
	    declare -a share=($( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.10.1.5" | cut -d\" -f2 ))
	    declare -a sstatus=($( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.10.1.7" | cut -d: -f4 ))
	    declare -a stype=($( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.5.10.1.6" | cut -d: -f4 ))
    	    for ((b=0; b < ${#volum[*]}; b++))
            do
    	        vol_id=${volum[$b]}
		vol_name=${share[$b]}
		if [[ "$vol_name" == "." ]]; then continue; fi
		vol_name="${volum[$b]}/$vol_name"
		
		vol_status=${sstatus[$b]}
		if [[ "$vol_status" == "1" ]]; then vol_status="normal"; fi
		if [[ "$vol_status" == "2" ]]; then vol_status="snapmirrored"; fi
		if [[ "$vol_status" == "3" ]]; then vol_status="snapvaulted"; fi
		
   	        vol_wwn=${stype[$b]}
		if [[ "$vol_wwn" == "1" ]]; then vol_wwn="unix"; fi
		if [[ "$vol_wwn" == "2" ]]; then vol_wwn="ntfs"; fi
		if [[ "$vol_wwn" == "3" ]]; then vol_wwn="mixed"; fi
		
		vol_func="qtree"
		vol_size=""
		vol_sizeKB="0"
		vol_srvs=""
		vol_diskgrp=""
		
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_size,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $Fout
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_sizeKB,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $FoutDB
	    done
	    unset volum
	    unset share
	    unset sstatus
	    unset stype
	    
	    
	    # info about hosts
	    server=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.16.1.1.2" | wc -l )
    	    for ((b=0; b < $server; b++))
            do
    	        srv_id=$(($b+1))
		srv_name=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.16.1.1.2.$srv_id" | cut -d\" -f2 )
		
		srv_status=""
		
		srv_ports=""
		srv_wwn=""
		plist=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.16.2.1.3.$srv_id" | wc -l )
        	for ((c=0; c < $plist; c++))
	        do
    	    	    p_id=$(($c+1))
		    p_wwn=$( eval "$FcmdSNMP 1.3.6.1.4.1.789.1.17.16.2.1.3.$srv_id.$p_id" | cut -d\" -f2 )
		    p_wwn=${p_wwn:4:(${#p_wwn}-5)}
		    srv_wwn="$srv_wwn; $p_wwn"
		done
		if [[ ${#srv_wwn} -gt 2 ]]; then srv_wwn=${srv_wwn:2:${#srv_wwn}}; fi 
		if [[ "$srv_wwn" != "" ]]; then srv_ports=$( echo \"$srv_wwn\" | tr ';' '\n' | wc -l ); fi
		
		#srv_vols=""
    	        srv_vols=$( cat "$Ftmp.volume" | grep "#$srv_name#" | cut -d# -f1 | tr '\n' ';' )
		if [[ ${srv_vols:(-1)} == ";" ]]; then srv_vols=${srv_vols:0:(${#srv_vols}-1)}; fi 
    		srv_vols=${srv_vols//";"/"; "}
		
    		#prepare WWN-Host info for processing
    		declare -a wh=(${srv_wwn//";"/""})
    		for ((c=0; c < ${#wh[*]}; c++)); do echo -e "${wh[$c]}\t$srv_name\t$part0" >> "$Ftmp.wwnhost"; done
		unset wh
		
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$part6,$srv_name,$srv_status,$srv_ports,$srv_wwn,$srv_vols" >> $Fout 
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$part6,$srv_name,$srv_status,$srv_ports,$srv_wwn,$srv_vols" >> $FoutDB
	    done

	if [[ -f "$Ftmp.volume" ]]; then rm "$Ftmp.volume"; fi
	if [[ -f "$Ftmp.host" ]]; then rm "$Ftmp.host"; fi
    fi


#IBM DS5K
    if [[ "$Fkey" == "DS" ]] || [[ "$Fkey" == "DPV" ]]
    then
            Fcmd="SMcli $Fip"
	    
	    # general storage info
	    eval "$Fcmd -c \"show storageArray;\" > $Ftmp"
	    cp $Ftmp "$Ftmp.array"

	    poolNgrp=0
	    if [[ $( cat $Ftmp | grep "Total Disk Pools:" | awk '{ print $4 }' ) != "0" ]]; then poolNgrp=1; fi

	    st_name=$( cat $Ftmp | grep "Storage Subsystem Name:" | awk '{ print $4}' )
	    st_os=$( cat $Ftmp | grep "Current Package Version:" | head -n 1 | awk '{ print $4}' )
	    key="tail -n1"; if [[ $poolNgrp == 1 ]]; then key="head -n1"; fi
	    #st_size=$( cat $Ftmp | grep "Total Capacity:" | tail -n1 | awk '{ print $3 }' | sed 's/,//g' | awk -F'.' '{ print $1 }' )
	    #st_use=$( cat $Ftmp | grep "Total Capacity:" | tail -n1 | awk '{ print $6 }' | sed 's/,//g' | awk -F'.' '{ print $1 }' )
	    #st_free=$( cat $Ftmp | grep "Total Free Capacity:" | tail -n1 | awk '{ print $4}' | sed 's/,//g' | awk -F'.' '{ print $1 }' )
	    st_size=$( cat $Ftmp | grep "Total Capacity:" | $key | awk '{ print $3 $4 }' | sed 's/,//g' )
	    st_use=$( cat $Ftmp | grep "Total Capacity:" | $key | awk '{ print $6 $7 }' | sed 's/,//g' )
	    st_free=$( cat $Ftmp | grep "Total Free Capacity:" | $key | awk '{ print $4 $5}' | sed 's/,//g' )
	    st_size=$( str2KB "$st_size" )
	    st_use=$( str2KB "$st_use" )
	    st_free=$( str2KB "$st_free" )
    	    st_sizeKB="$st_size"
    	    st_useKB="$st_use"
    	    st_freeKB="$st_free"
	    st_size=$( KB2str "$st_size" )
	    st_use=$( KB2str "$st_use" )
	    st_free=$( KB2str "$st_free" )
	    
	    st_ip=$( cat "$Ftmp" | grep -A 1000 "CONTROLLERS----------" | grep -B 1000 "DRIVES---------" | grep "IP address:" | grep -v "Local" | grep -v "0.0.0.0" | awk '{ print $3 }' | tr '\n' ';' | tr -s ';' ); st_ip=$( trim "$st_ip" )
	    if [[ ${st_ip:(-1)} == ";" ]]; then st_ip=${st_ip:0:(${#st_ip}-1)}; fi 
    	    st_ip=${st_ip//";"/"; "}
    	    #if [[ "$st_ip" != "" ]]; then st_ip="($Fip) ${st_ip}"; fi
    	    if [[ "$st_ip" != "" ]]; then st_ip=${st_ip/"$Fip"/"($Fip)"}; fi

	    st_wwn=""
	    #st_wwns=$( cat $Ftmp | grep "World-wide port identifier:" | awk '{ print $4}' | tr '\n' ';' ); st_wwns=$( trim "$st_wwns" )
	    #if [[ ${st_wwns:(-1)} == ";" ]]; then st_wwns=${st_wwns:0:(${#st_wwns}-1)}; fi 
    	    #st_wwns=${st_wwns//";"/"; "}

	    if [[ "$st_name" == "" ]]; then st_name="$Fname"; fi
	    if [[ "$st_ip" == "" ]]; then st_ip="($Fip)"; fi

	    part0="$curdate,$Froom,$st_name"
	    
	    echo "$part0,$st_ip,$st_os,$st_size,$st_use,$st_free,$st_wwn,$part2,$part3,$part4,$part5,$part6,$part7" >> $Fout
	    echo "$part0,$st_ip,$st_os,$st_sizeKB,$st_useKB,$st_freeKB,$st_wwn,$part2,$part3,$part4,$part5,$part6,$part7" >> $FoutDB
            
	    
	    # info by each controller
	    ctrl=$( cat $Ftmp | grep "Number of RAID controller modules:" | awk '{ print $6}' )
    	    for ((c=0; c < $ctrl; c++))
            do
		eval "$Fcmd -c \"show controller [${c}];\" > $Ftmp2"
		ctrl_wwns=$( cat $Ftmp2 | grep "World-wide port identifier:" | awk '{ print $4}' | tr '\n' ' ' ); ctrl_wwns=$( trim "$ctrl_wwns" )
		declare -a controller=($ctrl_wwns)
    		for ((b=0; b < ${#controller[*]}; b++))
        	do
        	    str="${controller[$b]}"
    	    	    ctrl_id=$( cat $Ftmp2 | grep "RAID Controller Module in" ); ctrl_id=$( trim "$ctrl_id" )
    	    	    ctrl_id=${ctrl_id/"RAID Controller Module in "/""}
    	    	    ctrl_id=${ctrl_id/"Enclosure"/"Encl"}
    	    	    ctrl_id=${ctrl_id//" "/":"}
    	    	    ctrl_id=${ctrl_id//",:"/" "}
    	    	    ctrl_wwn="$str"; ctrl_wwn=$( trim "$ctrl_wwn" )
    	    	    #ctrl_speed=$( cat $Ftmp2 | grep -B 12 "$str" | grep "Maximum data rate:" | awk '{ print $4 $5}'); ctrl_speed=$( trim "$ctrl_speed" )
    	    	    ctrl_speed1=$( cat $Ftmp2 | grep -B 12 "$str" | grep "Current data rate:" | awk '{ print $4}'); ctrl_speed1=$( trim "$ctrl_speed1" )
    	    	    if [[ "$ctrl_speed1" == "Not" ]]; then ctrl_speed1="-"; fi
    	    	    ctrl_speed2=$( cat $Ftmp2 | grep -B 12 "$str" | grep "Maximum data rate:" | awk '{ print $4}'); ctrl_speed2=$( trim "$ctrl_speed2" )
    	    	    ctrl_speed="${ctrl_speed1}/${ctrl_speed2}Gb"
    	    	    ctrl_status=$( cat $Ftmp2 | grep -B 12 "$str" | grep "Link status:" | awk '{ print $3}'); ctrl_status=$( trim "$ctrl_status" )

		    echo "$part0,$part1,$ctrl_id,$ctrl_wwn,$ctrl_speed,$ctrl_status,$part3,$part4,$part5,$part6,$part7" >> $Fout 
		    echo "$part0,$part1,$ctrl_id,$ctrl_wwn,$ctrl_speed,$ctrl_status,$part3,$part4,$part5,$part6,$part7" >> $FoutDB
        	done
        	unset controller
            done

	    
	    # info by each enclosure
	    encl=$( cat "$Ftmp.array" | grep "HARDWARE SUMMARY" -A 10 | grep "Enclosures:" | awk '{ print $2 }' )
	    cat $Ftmp | grep "ENCLOSURES------" -A 1000 | grep "Enclosure path" -A 10 > $Ftmp2
	    
    	    for ((b=0; b < $encl; b++))
            do
    	        encl_id=$(($b+1))
    	        encl_up="tail -n +$encl_id"
    	        encl_down="head -n 1"
    	        encl_status=$( cat $Ftmp2 | grep "Enclosure path consistency:" | $encl_up | $encl_down | awk '{ print $4 }' )
    	        encl_type=""
    	        encl_pn=$( cat $Ftmp2 | grep "Part number:" | $encl_up | $encl_down | awk '{ print $3 $4 }' )
    	        encl_sn=$( cat $Ftmp2 | grep "Serial number:" | $encl_up | $encl_down | awk '{ print $3 $4 }' )
    	        encl_hdd=""
		encl_speed=""
	
		echo "$part0,$part1,$part2,$encl_id,$encl_status,$encl_type,$encl_pn,$encl_sn,$encl_hdd,$encl_speed,$part4,$part5,$part6,$part7" >> $Fout 
		echo "$part0,$part1,$part2,$encl_id,$encl_status,$encl_type,$encl_pn,$encl_sn,$encl_hdd,$encl_speed,$part4,$part5,$part6,$part7" >> $FoutDB
            done
	    
	    
	    # info about hard disks
	    eval "$Fcmd -c \"show allPhysicalDisks;\" > $Ftmp"
	    harddisk=$( cat $Ftmp | grep "Number of physical disks:" | awk '{ print $5}' )
	    #ENCLOSURE,;SLOT;STATUS;CAPACITY;MEDIA_TYPE;INTERFACE_TYPE;CURRENT_DATA_RATE;PRODUCT_ID;FIRMWARE_VERSION;CAPABILITIES
	    cat $Ftmp | grep "BASIC:" -A 2 | tail -n -1 > $Ftmp2
	    str_len=$( cat $Ftmp2 | wc -c ); str_len=$((${str_len}-1))
	    printf "%${str_len}s\n" ' ' | sed "s/ /-/g" >> $Ftmp2
	    #cat $Ftmp | grep "BASIC:" -A $(($harddisk+2)) | tail -n +4 | sed 's/^/NN/' >> $Ftmp2
	    #tableconv $Ftmp2 "NN;ENCLOSURE,;SLOT;STATUS;CAPACITY;MEDIA_TYPE;INTERFACE_TYPE;CURRENT_DATA_RATE;PRODUCT_ID"
	    cat $Ftmp | grep "BASIC:" -A $(($harddisk+2)) | tail -n +4 >> $Ftmp2
	    tableconv $Ftmp2 "ENCLOSURE,;SLOT;STATUS;CAPACITY;MEDIA_TYPE;INTERFACE_TYPE;CURRENT_DATA_RATE;PRODUCT_ID"
	    
	    unset harddisk
	    index=0
            while read line; do
    		harddisk[$index]="$line"
	        index=$(($index+1))
    	    done < $Ftmp2

    	    for ((b=0; b < ${#harddisk[*]}; b++))
            do
        	str="${harddisk[$b]}"
		disk_id=$(($b+1))
    	    	disk_encl=`echo "$str" | cut -d\; -f1`; disk_encl=$( trim "$disk_encl" ); disk_encl=${disk_encl:0:(${#disk_encl}-1)}
		disk_bay=`echo "$str" | cut -d\; -f2`; disk_bay=$( trim "$disk_bay" )
    	    	disk_status=`echo "$str" | cut -d\; -f3`; disk_status=$( trim "$disk_status" )
    	    	disk_mode=`echo "$str" | cut -d\; -f5`; disk_mode=$( trim "$disk_mode" )
    	    	disk_type=`echo "$str" | cut -d\; -f6`; disk_type=$( trim "$disk_type" )
		disk_speed=`echo "$str" | cut -d\; -f7`; disk_speed=$( trim "$disk_speed" )
    	    	disk_pn=`echo "$str" | cut -d\; -f8`; disk_pn=$( trim "$disk_pn" )
    	    	disk_size=`echo "$str" | cut -d\; -f4`; disk_size=$( trim "$disk_size" )
		disk_size=$( str2KB "$disk_size" )
		disk_sizeKB="$disk_size"
		disk_size=$( KB2str "$disk_size" )
    		
		#SMcli 10.100.11.69 -c "show physicalDisk [0,1];"
		eval "$Fcmd -c \"show physicalDisk [${disk_encl},${disk_bay}];\" > $Ftmp"
		disk_sn=`cat $Ftmp | grep "Serial number:" |  cut -d: -f2`; disk_sn=$( trim "$disk_sn" )
		
		echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_size,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $Fout 
		echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_sizeKB,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $FoutDB
        	unset disk
            done
            unset harddisk
	    
	    
	    # info about disk groups
	    #DS5K, DellPV
	    diskpool=$( cat "$Ftmp.array" | grep "Total Disk Pools:" | awk '{ print $4 }' )
	    diskgrp=$( cat "$Ftmp.array" | grep "Total Disk Groups:" | awk '{ print $4 }' )
	    if [[ "$diskgrp" == "0" ]]
	    then
		cat "$Ftmp.array" | grep "DISK POOLS------" -A 1000 | grep "DISK GROUPS------" -B 1000 | head -n $((20+$diskpool)) | grep "DETAILS" -B 100 | head -n -2 | grep "Status:" -A 100 | tail -n +3 > $Ftmp2
	    else
		cat "$Ftmp.array" | grep "DISK GROUPS------" -A 1000 | grep "STANDARD VIRTUAL DISKS------" -B 1000 | head -n $((20+$diskgrp)) | grep "DETAILS" -B 100 | head -n -2 | grep "Status:" -A 100 | tail -n +3 > $Ftmp2
	    fi
	    
	    cat $Ftmp2 | head -n 1 > $Ftmp
	    str_len=$( cat $Ftmp2 | head -n 1 | wc -c ); str_len=$((${str_len}-1))
	    printf "%${str_len}s\n" ' ' | sed "s/ /-/g" >> $Ftmp
	    cat $Ftmp2 | tail -n +2 >> $Ftmp
	    # DISK POOLS  "Name;Status;Usable_Capacity;Used_Capacity;Free_Capacity;Preservation_Capacity;Physical_Disk/Media_Type;Virtual_Disks;Secure_Capable;DA_Capable"
	    # DISK GROUPS "Name;Status;Usable_Capacity;Used_Capacity;Free_Capacity;RAID_Level;Physical_Disk/Media_Type;Virtual_Disks;Secure_Capable;DA_Capable"
	    tableconv $Ftmp "Name;Status;Usable_Capacity;Free_Capacity"
	    
            unset diskgrp
	    index=0
            while read line; do
    		diskgrp[$index]="$line"
	        index=$(($index+1))
    	    done < $Ftmp

    	    for ((b=0; b < ${#diskgrp[*]}; b++))
            do
        	str="${diskgrp[$b]}"
		dgrp_name=`echo "$str" | cut -d\; -f1`; dgrp_name=$( trim "$dgrp_name" )
		dgrp_status=`echo "$str" | cut -d\; -f2`; dgrp_status=$( trim "$dgrp_status" )
		dgrp_size=`echo "$str" | cut -d\; -f3 | sed 's/,//g'`; dgrp_size=$( trim "$dgrp_size" )
		dgrp_size=$( str2KB "$dgrp_size" )
		dgrp_free=`echo "$str" | cut -d\; -f4 | sed 's/,//g'`; dgrp_free=$( trim "$dgrp_free" ) 
		dgrp_free=$( str2KB "$dgrp_free" )
		dgrp_sizeKB="$dgrp_size"
		dgrp_freeKB="$dgrp_free"
		dgrp_size=$( KB2str "$dgrp_size" )
		dgrp_free=$( KB2str "$dgrp_free" )
	
		echo "$part0,$part1,$part2,$part3,$part4,$dgrp_name,$dgrp_status,$dgrp_size,$dgrp_free,$part6,$part7" >> $Fout
		echo "$part0,$part1,$part2,$part3,$part4,$dgrp_name,$dgrp_status,$dgrp_sizeKB,$dgrp_freeKB,$part6,$part7" >> $FoutDB
            done
            unset diskgrp
	    
	    
	    # info about volumes
	    eval "$Fcmd -c \"show allVirtualDisks;\" > $Ftmp"
	    
	    volum=$( cat $Ftmp | grep "Number of standard virtual disks:" | awk '{ print $6 }' )

    	    echo -n > "$Ftmp.volume"
    	    for ((b=0; b < $volum; b++))
            do
    	        vol_id=$(($b+1))
    	        vol_up="tail -n +$vol_id"
    	        vol_down="head -n 1"
    	        vol_name=$( cat $Ftmp | grep "Virtual Disk name:" | $vol_up | $vol_down | awk '{ print $4 }' )
    	        vol_status=$( cat $Ftmp | grep "Virtual Disk status:" | $vol_up | $vol_down | awk '{ print $4 }' )
		vol_wwn=$( cat $Ftmp | grep "Virtual Disk world-wide identifier:" | $vol_up | $vol_down | awk '{ print $5 }' | sed 's/://g' )
		vol_func=""
		vol_size=$( cat $Ftmp | grep "Capacity:" | $vol_up | $vol_down | awk '{ print $2 $3 }' | sed 's/,//g' )
		vol_size=$( str2KB "$vol_size" )
		vol_sizeKB="$vol_size"
		vol_size=$( KB2str "$vol_size" )
		
		key="Associated disk group:"; if [[ $poolNgrp == 1 ]]; then key="Associated disk pool:"; fi
		vol_diskgrp=$( cat $Ftmp | grep "$key" | $vol_up | $vol_down | awk '{ print $4 }' )
		# out to Ftmp2 struct Group-Host (10 space is Host, 12 spaces is Host in Group)
		cat "$Ftmp.array" | grep "TOPOLOGY DEFINITIONS" -A 1000 | grep "HOST TYPE DEFINITIONS" -B 1000 | grep -E "Host Group:|            Host:" | tr ' ' '\t' | tr -s '\t' | tr '\t' ' ' > $Ftmp2
		vol_srvs=$( cat $Ftmp | grep "Accessible By:" | $vol_up | $vol_down | cut -d: -f2 ); vol_srvs=$( trim $vol_srvs )
		if [[ "$vol_srvs" == "NA" ]]; then vol_srvs=""; fi
		if [[ ${#vol_srvs} -gt 11 && ${vol_srvs:0:10} == "Host Group" ]]
		then 
		    vol_srvs=${vol_srvs:11:${#vol_srvs}}
		    srv_lst=""
        	    key=""
        	    while read line; do
    			if [[ ${#line} -gt 11 && ${line:0:10} == "Host Group" ]]
    			then
    			    if [[ "${line:12:${#line}}" == "$vol_srvs" ]]; then key=${line:12:${#line}}; else key=""; fi
    			else
    			    if [[ "$key" != "" ]]; then srv_lst="$srv_lst; ${line:6:${#line}}"; echo "$vol_name#${line:6:${#line}}#" >> "$Ftmp.volume"; fi
    			fi
    		    done < $Ftmp2
    		    if [[ "$srv_lst" != "" ]]; then vol_srvs="${srv_lst:2:${#srv_lst}}"; fi
		fi 
		if [[ ${#vol_srvs} -gt 5 && ${vol_srvs:0:4} == "Host" ]]; then vol_srvs=${vol_srvs:5:${#vol_srvs}}; echo "$vol_name#$vol_srvs#" >> "$Ftmp.volume"; fi 
	    
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_size,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $Fout
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_sizeKB,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $FoutDB
	    done
	    
	    
	    # info about hosts
	    cat "$Ftmp.array" | grep "TOPOLOGY DEFINITIONS" -A 1000 | grep "HOST TYPE DEFINITIONS" -B 1000 | tr -s ' ' > $Ftmp2
	    # add last dummy host
	    echo " Host: x#y#z" >> $Ftmp2
	    server=$( grep "Host:" $Ftmp2 | wc -l )
    	    for ((b=0; b < $server; b++))
            do
    	        srv_id=$(($b+1))
    	        srv_up="tail -n +$srv_id"
    	        srv_id_next=$(($b+2))
    	        srv_up_next="tail -n +$srv_id_next"
    	        srv_down="head -n 1"
    	        srv_name=$( cat $Ftmp2 | grep "Host:" | $srv_up | $srv_down | awk '{ print $2 }' )
    	        # check dummy host
    	        if [[ "$srv_name" == "x#y#z" ]]; then continue; fi
    	        srv_name_next=$( cat $Ftmp2 | grep "Host:" | $srv_up_next | $srv_down | awk '{ print $2 }' )
	        srv_status=""
    	        #srv_ports=$( cat $Ftmp2 | grep "Host: $srv_name" -A10 | grep "Large sector size" -B 10 | grep "Host port" | wc -l )
    	        srv_ports=$( cat $Ftmp2 | grep "Host: $srv_name" -A20 | grep "Host: $srv_name_next" -B 20 | grep "Host port" | wc -l )
    	        
    	        #srv_wwn=$( cat $Ftmp2 | grep "Host: $srv_name" -A10 | grep "Large sector size" -B 10 | grep "Host port" | tr ' ' '\t' | tr -s '\t' | cut -f5 | tr '\n' ';' )
    	        srv_wwn=$( cat $Ftmp2 | grep "Host: $srv_name" -A20 | grep "Host: $srv_name_next" -B 20 | grep "Host port" | tr ' ' '\t' | tr -s '\t' | cut -f5 | tr '\n' ';' )
		if [[ ${srv_wwn:(-1)} == ";" ]]; then srv_wwn=${srv_wwn:0:(${#srv_wwn}-1)}; fi 
    		srv_wwn=${srv_wwn//";"/"; "}
    	        
    	        srv_vols=$( cat "$Ftmp.volume" | grep "#$srv_name#" | cut -d# -f1 | tr '\n' ';' )
		if [[ ${srv_vols:(-1)} == ";" ]]; then srv_vols=${srv_vols:0:(${#srv_vols}-1)}; fi 
    		srv_vols=${srv_vols//";"/"; "}

    		#prepare WWN-Host info for processing
    		declare -a wh=(${srv_wwn//";"/""})
    		for ((c=0; c < ${#wh[*]}; c++)); do echo -e "${wh[$c]}\t$srv_name\t$part0" >> "$Ftmp.wwnhost"; done
		unset wh
		
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$part6,$srv_name,$srv_status,$srv_ports,$srv_wwn,$srv_vols" >> $Fout 
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$part6,$srv_name,$srv_status,$srv_ports,$srv_wwn,$srv_vols" >> $FoutDB
	    done
	    
	if [[ -f "$Ftmp.volume" ]]; then rm "$Ftmp.volume"; fi
        rm "$Ftmp.array"
    fi


#IBM Storwize 
    if [[ "$Fkey" == "SW" ]]
    then
            Fcmd=""
            if [[ "$Fpasswd" == "SSH" ]]
            then 
		Fcmd="ssh -i \"/home/$Flogin/.ssh/id_rsa\" -o \"StrictHostKeyChecking no\" $Flogin@$Fip"
	    else
		Fcmd="sshpass -p $Fpasswd ssh -o \"PubkeyAuthentication=no\" -o \"StrictHostKeyChecking=no\" $Flogin@$Fip"
	    fi
	    
	    # general storage info
	    eval "$Fcmd \"lssystem -delim :\" > $Ftmp"
	    st_name=`cat $Ftmp | head -3 | grep "name" | cut -d: -f2`; st_name=$( trim "$st_name" )
	    st_os=`grep "code_level" $Ftmp | cut -d: -f2 | tr ' ' '\t' | tr -s '\t' | cut -f1`; st_os=$( trim "$st_os" )
	    st_size=`grep "total_mdisk_capacity" $Ftmp | cut -d: -f2`; st_size=$( trim "$st_size" )
	    st_use=`grep "total_used_capacity" $Ftmp | cut -d: -f2`; st_use=$( trim "$st_use" )
	    st_free=`grep "total_free_space" $Ftmp | cut -d: -f2`; st_free=$( trim "$st_free" )
	    st_size=$( str2KB "$st_size" )
	    st_use=$( str2KB "$st_use" )
	    st_free=$( str2KB "$st_free" )
    	    st_sizeKB="$st_size"
    	    st_useKB="$st_use"
    	    st_freeKB="$st_free"
	    st_size=$( KB2str "$st_size" )
	    st_use=$( KB2str "$st_use" )
	    st_free=$( KB2str "$st_free" )
	    
	    eval "$Fcmd \"lssystemip -delim : -nohdr \" > $Ftmp"
	    st_ip=`cat $Ftmp | grep ":local:" | cut -d: -f5  | tr '\n' ';' | tr -s ';'`; st_ip=$( trim "$st_ip" )
	    if [[ ${st_ip:(-1)} == ";" ]]; then st_ip=${st_ip:0:(${#st_wwns}-1)}; fi 
    	    st_ip=${st_ip//";"/"; "}
    	    #if [[ "$st_ip" != "" ]]; then st_ip="($Fip) ${st_ip}"; fi
    	    if [[ "$st_ip" != "" ]]; then st_ip=${st_ip/"$Fip"/"($Fip)"}; fi
	    
    	    st_wwn=""
	    #eval "$Fcmd \"lsportfc -delim : -nohdr \" > $Ftmp"
	    #st_wwns=`cat $Ftmp | cut -d: -f8  | tr '[:upper:]' '[:lower:]' | sed 's/../&:/g;s/:$//' | tr '\n' ';'`; st_wwns=$( trim "$st_wwns" )
	    #if [[ ${st_wwns:(-1)} == ";" ]]; then st_wwns=${st_wwns:0:(${#st_wwns}-1)}; fi 
    	    #st_wwns=${st_wwns//";"/"; "}

	    if [[ "$st_name" == "" ]]; then st_name="$Fname"; fi
	    if [[ "$st_ip" == "" ]]; then st_ip="($Fip)"; fi

	    part0="$curdate,$Froom,$st_name"
	    
	    echo "$part0,$st_ip,$st_os,$st_size,$st_use,$st_free,$st_wwn,$part2,$part3,$part4,$part5,$part6,$part7" >> $Fout
	    echo "$part0,$st_ip,$st_os,$st_sizeKB,$st_useKB,$st_freeKB,$st_wwn,$part2,$part3,$part4,$part5,$part6,$part7" >> $FoutDB


	    # info by each controller
	    #cluster_id:cluster_name:location:port_id:IP_address:subnet_mask:gateway:IP_address_6:prefix_6:gateway_6
	    #eval "$Fcmd \"lssystemip -delim : -nohdr\" > $Ftmp"
	    #id:fc_io_port_id:port_id:type:port_speed:node_id:node_name:WWPN:nportid:status:attachment:cluster_use:adapter_location:adapter_port_id
	    eval "$Fcmd \"lsportfc -delim : -nohdr\" | grep ":fc:" > $Ftmp"

	    index=0
            while read line; do
    		controller[$index]="$line"
	        index=$(($index+1))
    	    done < $Ftmp
    	                
    	    for ((b=0; b < ${#controller[*]}; b++))
            do
        	str="${controller[$b]}"
    	        ctrl_id=`echo "$str" | cut -d: -f7`; ctrl_id=$( trim "$ctrl_id" )
    	        ctrl_wwn=`echo "$str" | cut -d: -f8 | tr '[:upper:]' '[:lower:]'| sed 's/../&:/g;s/:$//'`; ctrl_wwn=$( trim "$ctrl_wwn" )
    	        ctrl_speed=`echo "$str" | cut -d: -f5`; ctrl_speed=$( trim "$ctrl_speed" )
    		if [[ "$ctrl_speed" == "N/A" ]]; then ctrl_speed=""; fi
    	        ctrl_status=`echo "$str" | cut -d: -f10`; ctrl_status=$( trim "$ctrl_status" )

		echo "$part0,$part1,$ctrl_id,$ctrl_wwn,$ctrl_speed,$ctrl_status,$part3,$part4,$part5,$part6,$part7" >> $Fout 
		echo "$part0,$part1,$ctrl_id,$ctrl_wwn,$ctrl_speed,$ctrl_status,$part3,$part4,$part5,$part6,$part7" >> $FoutDB
        	unset ctrl
            done
            unset controller
	    
	    
	    # info by each enclosure
	    #id:status:type:managed:IO_group_id:IO_group_name:product_MTM:serial_number:total_canisters:online_canisters:total_PSUs:online_PSUs:drive_slots:total_fan_modules:online_fan_modules:total_sems:online_sems
	    eval "$Fcmd \"lsenclosure -delim : -nohdr\" > $Ftmp"

	    index=0
            while read line; do
    		enclosure[$index]="$line"
	        index=$(($index+1))
    	    done < $Ftmp
    	                
    	    for ((b=0; b < ${#enclosure[*]}; b++))
            do
        	str="${enclosure[$b]}"
    	        encl_id=`echo "$str" | cut -d: -f1`; encl_id=$( trim "$encl_id" )
    	        encl_status=`echo "$str" | cut -d: -f2`; encl_status=$( trim "$encl_status" )
    	        encl_type=`echo "$str" | cut -d: -f3`; encl_type=$( trim "$encl_type" )
    	        encl_pn=`echo "$str" | cut -d: -f7`; encl_pn=$( trim "$encl_pn" )
    	        encl_sn=`echo "$str" | cut -d: -f8`; encl_sn=$( trim "$encl_sn" )
    	        encl_hdd=`echo "$str" | cut -d: -f13`; encl_hdd=$( trim "$encl_hdd" )

	        eval "$Fcmd \"lsenclosure -delim : $encl_id\" > $Ftmp"
		encl_speed=`grep "interface_speed" $Ftmp | cut -d: -f2`; encl_speed=$( trim "$encl_speed" )
		
		echo "$part0,$part1,$part2,$encl_id,$encl_status,$encl_type,$encl_pn,$encl_sn,$encl_hdd,$encl_speed,$part4,$part5,$part6,$part7" >> $Fout 
		echo "$part0,$part1,$part2,$encl_id,$encl_status,$encl_type,$encl_pn,$encl_sn,$encl_hdd,$encl_speed,$part4,$part5,$part6,$part7" >> $FoutDB
        	unset encl
            done
            unset enclosure
	    
	    
	    # info about hard disks 
	    #id:status:error_sequence_number:use:tech_type:capacity:mdisk_id:mdisk_name:member_id:enclosure_id:slot_id:node_id:node_name:auto_manage:drive_class_id
	    eval "$Fcmd \"lsdrive -nohdr -delim :\" > $Ftmp"

	    index=0
            while read line; do
    		harddisk[$index]="$line"
	        index=$(($index+1))
    	    done < $Ftmp
    	                
    	    for ((b=0; b < ${#harddisk[*]}; b++))
            do
        	str="${harddisk[$b]}"
    	        disk_id=`echo "$str" | cut -d: -f1`; disk_id=$( trim "$disk_id" )
    	        disk_encl=`echo "$str" | cut -d: -f10`; disk_encl=$( trim "$disk_encl" )
    	        disk_bay=`echo "$str" | cut -d: -f11`; disk_bay=$( trim "$disk_bay" )
    	        disk_status=`echo "$str" | cut -d: -f2`; disk_status=$( trim "$disk_status" )
    	        disk_mode=`echo "$str" | cut -d: -f4`; disk_mode=$( trim "$disk_mode" )
    	        disk_type=`echo "$str" | cut -d: -f5`; disk_type=$( trim "$disk_type" )
    	        disk_size=`echo "$str" | cut -d: -f6`; disk_size=$( trim "$disk_size" )
		disk_size=$( str2KB "$disk_size" )
		disk_sizeKB="$disk_size"
		disk_size=$( KB2str "$disk_size" )

	        eval "$Fcmd \"lsdrive $disk_id\" > $Ftmp"
		disk_speed=`grep "interface_speed" $Ftmp | tr ' ' '\t' | cut -f2`; disk_speed=$( trim "$disk_speed" )
    	        disk_pn=`grep "FRU_part_number" $Ftmp | tr ' ' '\t' | cut -f2`; disk_pn=$( trim "$disk_pn" )
    	        disk_sn=`grep "FRU_identity" $Ftmp | tr ' ' '\t' | cut -f2`; disk_sn=$( trim "$disk_sn" )
		
		echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_size,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $Fout 
		echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_sizeKB,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $FoutDB
        	unset disk
            done
            unset harddisk
	    
	    
	    # info about disk groups
	    #id:name:status:mdisk_count:vdisk_count:capacity:extent_size:free_capacity:virtual_capacity:used_capacity:real_capacity:overallocation:warning:easy_tier:easy_tier_status:compression_active:compression_virtual_capacity:compression_compressed_capacity:compression_uncompressed_capacity:parent_mdisk_grp_id:parent_mdisk_grp_name:child_mdisk_grp_count:child_mdisk_grp_capacity:type:encrypt:owner_type:site_id:site_name
	    eval "$Fcmd \"lsmdiskgrp -delim : -nohdr\" > $Ftmp"

	    index=0
            while read line; do
    		diskgrp[$index]="$line"
	        index=$(($index+1))
    	    done < $Ftmp
    	                
    	    for ((b=0; b < ${#diskgrp[*]}; b++))
            do
        	str="${diskgrp[$b]}"
    	        dgrp_id=`echo "$str" | cut -d: -f1`; dgrp_id=$( trim "$dgrp_id" )
    	        dgrp_name=`echo "$str" | cut -d: -f2`; dgrp_name=$( trim "$dgrp_name" )
    	        dgrp_status=`echo "$str" | cut -d: -f3`; dgrp_status=$( trim "$dgrp_status" )
    	        dgrp_size=`echo "$str" | cut -d: -f6`; dgrp_size=$( trim "$dgrp_size" )
		dgrp_size=$( str2KB "$dgrp_size" )
    	        dgrp_free=`echo "$str" | cut -d: -f8`; dgrp_free=$( trim "$dgrp_free" )
		dgrp_free=$( str2KB "$dgrp_free" )
		dgrp_sizeKB="$dgrp_size"
		dgrp_freeKB="$dgrp_free"
		dgrp_size=$( KB2str "$dgrp_size" )
		dgrp_free=$( KB2str "$dgrp_free" )

		echo "$part0,$part1,$part2,$part3,$part4,$dgrp_name,$dgrp_status,$dgrp_size,$dgrp_free,$part6,$part7" >> $Fout
		echo "$part0,$part1,$part2,$part3,$part4,$dgrp_name,$dgrp_status,$dgrp_sizeKB,$dgrp_freeKB,$part6,$part7" >> $FoutDB
            done
            unset diskgrp


	    # info about volumes
	    #id:name:IO_group_id:IO_group_name:status:mdisk_grp_id:mdisk_grp_name:capacity:type:FC_id:FC_name:RC_id:RC_name:vdisk_UID:fc_map_count:copy_count:fast_write_state:se_copy_count:RC_change:compressed_copy_count:parent_mdisk_grp_id:parent_mdisk_grp_name:formatting:encrypt:volume_id:volume_name:function
	    eval "$Fcmd \"lsvdisk -nohdr -delim :\" > $Ftmp"

	    index=0
            while read line; do
    		volume[$index]="$line"
	        index=$(($index+1))
    	    done < $Ftmp
    	                
    	    for ((b=0; b < ${#volume[*]}; b++))
            do
	        str="${volume[$b]}"
    	        vol_id=`echo "$str" | cut -d: -f1`; vol_id=$( trim "$vol_id" )
    	        vol_name=`echo "$str" | cut -d: -f2`; vol_name=$( trim "$vol_name" )
    	        vol_status=`echo "$str" | cut -d: -f5`; vol_status=$( trim "$vol_status" )
		vol_wwn=`echo "$str" | cut -d: -f14`; vol_wwn=$( trim "$vol_wwn" )
		vol_wwn=$(echo $vol_wwn | tr '[:upper:]' '[:lower:]')
		vol_func=`echo "$str" | cut -d: -f27`; vol_func=$( trim "$vol_func" )
		vol_diskgrp=`echo "$str" | cut -d: -f22`; vol_diskgrp=$( trim "$vol_diskgrp" )
		vol_size=`echo "$str" | cut -d: -f8`; vol_size=$( trim "$vol_size" )
		vol_size=$( str2KB "$vol_size" )
		vol_sizeKB="$vol_size"
		vol_size=$( KB2str "$vol_size" )
	        
	        #id:name:SCSI_id:host_id:host_name:vdisk_UID:IO_group_id:IO_group_name:mapping_type:host_cluster_id:host_cluster_name
	        eval "$Fcmd \"lsvdiskhostmap -delim : -nohdr $vol_id\" > $Ftmp"
    		vol_srvs=""
    		
		index=0
        	while read line; do
    		    volumehost[$index]="$line"
	    	    index=$(($index+1))
    		done < $Ftmp
    		
    		for ((c=0; c < ${#volumehost[*]}; c++))
        	do
	    	    str="${volumehost[$c]}"
	    	    str=`echo "$str" | cut -d: -f5`
	    	    if [[ "$vol_srvs" == "" ]]; then vol_srvs="$str"; else vol_srvs="$vol_srvs; $str"; fi
		done
    		unset volumehost

		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_size,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $Fout
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_sizeKB,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $FoutDB
        	unset vol
            done
            unset volume


	    # info about hosts
	    #id:name:port_count:iogrp_count:status:site_id:site_name:host_cluster_id:host_cluster_name
	    eval "$Fcmd \"lshost -nohdr -delim :\" > $Ftmp"

	    index=0
            while read line; do
    		server[$index]="$line"
	        index=$(($index+1))
    	    done < $Ftmp
    	                
    	    for ((b=0; b < ${#server[*]}; b++))
            do
    	        str="${server[$b]}"
    	        srv_id=`echo "$str" | cut -d: -f1`; srv_id=$( trim "$srv_id" )
    	        srv_name=`echo "$str" | cut -d: -f2`; srv_name=$( trim "$srv_name" )
    	        srv_status=`echo "$str" | cut -d: -f5`; srv_status=$( trim "$srv_status" )
    	        srv_ports=`echo "$str" | cut -d: -f3`; srv_ports=$( trim "$srv_ports" )
		srv_wwn=""
    	        
	        eval "$Fcmd \"lshost -delim : $srv_id\" > $Ftmp"
		srv_wwn=`grep "WWPN" $Ftmp | cut -d: -f2  | tr '[:upper:]' '[:lower:]'| sed 's/../&:/g;s/:$//' | tr '\n' ';'`; srv_wwn=$( trim "$srv_wwn" )
		if [[ ${srv_wwn:(-1)} == ";" ]]; then srv_wwn=${srv_wwn:0:(${#srv_wwn}-1)}; fi 
    		srv_wwn=${srv_wwn//";"/"; "}
    		
	        #id:name:SCSI_id:vdisk_id:vdisk_name:vdisk_UID:IO_group_id:IO_group_name:mapping_type:host_cluster_id:host_cluster_name
	        eval "$Fcmd \"lshostvdiskmap -delim : -nohdr $srv_id\" > $Ftmp"
    		srv_vols=""
    		
		index=0
        	while read line; do
    		    hostvolume[$index]="$line"
	    	    index=$(($index+1))
    		done < $Ftmp
    		
    		for ((c=0; c < ${#hostvolume[*]}; c++))
        	do
	    	    str="${hostvolume[$c]}"
	    	    str=`echo "$str" | cut -d: -f5`
	    	    if [[ "$srv_vols" == "" ]]; then srv_vols="$str"; else srv_vols="$srv_vols; $str"; fi
		done
    		unset hostvolume
	
    		#prepare WWN-Host info for processing
    		declare -a wh=(${srv_wwn//";"/""})
    		for ((c=0; c < ${#wh[*]}; c++)); do echo -e "${wh[$c]}\t$srv_name\t$part0" >> "$Ftmp.wwnhost"; done
		unset wh
		
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$part6,$srv_name,$srv_status,$srv_ports,$srv_wwn,$srv_vols" >> $Fout 
		echo "$part0,$part1,$part2,$part3,$part4,$part5,$part6,$srv_name,$srv_status,$srv_ports,$srv_wwn,$srv_vols" >> $FoutDB
        	unset srv
            done
            unset server
    fi

	
#Not processing
    if [[ "$Fkey" == "Pass" ]]
    then 
	echo -n " Passed" 
    fi


#Template
    if [[ "$Fkey" == "NONE" ]]
    then
            Fcmd=""
            if [[ "$Fpasswd" == "VALUE" ]]
            then 
		Fcmd="" #command with VALUE specific
	    else
		Fcmd="" #command
	    fi
	    
	    # general storage info
	    st_name=""; st_name=$( trim "$st_name" )
	    st_os=""; st_os=$( trim "$st_os" )
	    st_ip=""
	    st_wwn=""; st_wwns=$( trim "$st_wwn" )
	    st_size=""
	    st_use=""
	    st_free=""
	    st_size=$( str2KB "$st_size" )
	    st_use=$( str2KB "$st_size" )
	    st_free=$( str2KB "$st_size" )
    	    st_sizeKB="$st_size"
    	    st_useKB="$st_use"
    	    st_freeKB="$st_free"
	    st_size=$( KB2str "$st_size" )
	    st_use=$( KB2str "$st_size" )
	    st_free=$( KB2str "$st_size" )

	    if [[ "$st_name" == "" ]]; then st_name="$Fname"; fi
	    if [[ "$st_ip" == "" ]]; then st_ip="($Fip)"; fi

	    part0="$curdate,$Froom,$st_name"

	    echo "$part0,$st_ip,$st_os,$st_size,$st_use,$st_free,$st_wwn,$part2,$part3,$part4,$part5,$part6,$part7" >> $Fout
	    echo "$part0,$st_ip,$st_os,$st_sizeKB,$st_useKB,$st_freeKB,$st_wwn,$part2,$part3,$part4,$part5,$part6,$part7" >> $FoutDB

	    
	    # info by each controller
    	        #ctrl_id=""; ctrl_id=$( trim "$ctrl_id" )
    	        #ctrl_wwn=""; ctrl_wwn=$( trim "$ctrl_wwn" )
    	        #ctrl_speed=""; ctrl_speed=$( trim "$ctrl_speed" )
    	        #ctrl_status=""; ctrl_status=$( trim "$ctrl_status" )

		#echo "$part0,$part1,$ctrl_id,$ctrl_wwn,$ctrl_speed,$ctrl_status,$part3,$part4,$part5,$part6,$part7" >> $Fout 
		#echo "$part0,$part1,$ctrl_id,$ctrl_wwn,$ctrl_speed,$ctrl_status,$part3,$part4,$part5,$part6,$part7" >> $FoutDB
	    
	    
	    # info by each enclosure
    	        #encl_id=""; encl_id=$( trim "$encl_id" )
    	        #encl_status=""; encl_status=$( trim "$encl_status" )
    	        #encl_type=""; encl_type=$( trim "$encl_type" )
    	        #encl_pn=""; encl_pn=$( trim "$encl_pn" )
    	        #encl_sn=""
    	        #encl_hdd=""
		#encl_speed=""; encl_speed=$( trim "$encl_speed" )

		#echo "$part0,$part1,$part2,$encl_id,$encl_status,$encl_type,$encl_pn,$encl_sn,$encl_hdd,$encl_speed,$part4,$part5,$part6,$part7" >> $Fout 
		#echo "$part0,$part1,$part2,$encl_id,$encl_status,$encl_type,$encl_pn,$encl_sn,$encl_hdd,$encl_speed,$part4,$part5,$part6,$part7" >> $FoutDB
		
	    
	    # info by hard disks
    	    	#disk_encl=""; disk_encl=$( trim "$disk_encl" )
		#disk_bay=""; disk_bay=$( trim "$disk_bay" )
    	    	#disk_status=""; disk_status=$( trim "$disk_status" )
    	    	#disk_type=""; disk_type=$( trim "$disk_type" )
    	    	#disk_mode=""; disk_mode=$( trim "$disk_mode" )
    	    	#disk_size=""; disk_size=$( trim "$disk_size" )
    	    	#disk_sizeKB="$disk_size"
		#disk_speed=""; disk_speed=$( trim "$disk_speed" )
    	    	#disk_pn=""; disk_pn=$( trim "$disk_pn" )
		#disk_sn=""; disk_sn=$( trim "$disk_sn" )
		
		#echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_size,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $Fout 
		#echo "$part0,$part1,$part2,$part3,$disk_encl,$disk_bay,$disk_status,$disk_type,$disk_mode,$disk_sizeKB,$disk_speed,$disk_pn,$disk_sn,$part5,$part6,$part7" >> $FoutDB
	    
	    
	    # info about disk groups
		#dgrp_name=""; dgrp_name=$( trim "$dgrp_name" )
		#dgrp_status=""; dgrp_status=$( trim "$dgrp_status" )
		#dgrp_size=""; dgrp_size=$( trim "$dgrp_size" )
		#dgrp_free=""; dgrp_free=$( trim "$dgrp_free" )
		#dgrp_sizeKB="$dgrp_size"
		#dgrp_freeKB="$dgrp_free"

		#echo "$part0,$part1,$part2,$part3,$part4,$dgrp_name,$dgrp_status,$dgrp_size,$dgrp_free,$part6,$part7" >> $Fout
		#echo "$part0,$part1,$part2,$part3,$part4,$dgrp_name,$dgrp_status,$dgrp_sizeKB,$dgrp_freeKB,$part6,$part7" >> $FoutDB
	    
	    
	    # info about volumes
		#vol_name=""; vol_name=$( trim "$vol_name" )
		#vol_size=""; vol_size=$( trim "$vol_size" )
		#vol_diskgrp=""; vol_diskgrp=$( trim "$vol_diskgrp" )
        	#vol_status=""; vol_status=$( trim "$vol_status" )
    		#vol_wwn=""; vol_wwn=$( trim "$vol_wwn" )
		#vol_srvs=""
		
		#echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_size,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $Fout
		#echo "$part0,$part1,$part2,$part3,$part4,$part5,$vol_name,$vol_status,$vol_sizeKB,$vol_wwn,$vol_srvs,$vol_diskgrp,$vol_func,$part7" >> $FoutDB
	    
	    
	    # info about hosts
		#srv_name=""; srv_name=$( trim "$srv_name" )
		#srv_status=""; srv_status=$( trim "$srv_status" )
		#srv_wwn=""; srv_wwn=$( trim "$srv_wwn" )
		#srv_ports=""
		#srv_vols=""
		
    		##prepare WWN-Host info for processing
    		#declare -a wh=(${srv_wwn//";"/""})
    		#for ((c=0; c < ${#wh[*]}; c++)); do echo -e "${wh[$c]}\t$srv_name\t$part0" >> "$Ftmp.wwnhost"; done
		#unset wh
		
		#echo "$part0,$part1,$part2,$part3,$part4,$part5,$part6,$srv_name,$srv_status,$srv_ports,$srv_wwn,$srv_vols" >> $Fout 
		#echo "$part0,$part1,$part2,$part3,$part4,$part5,$part6,$srv_name,$srv_status,$srv_ports,$srv_wwn,$srv_vols" >> $FoutDB

	#if [[ -f $Ftmp2 ]]; then rm $Ftmp2; fi
    fi
    echo " end"
done
unset storsw

if [[ -f $Fadd ]]
then 
    echo -n "Merge CSV file with file \"${Fadd}\"..."
    cat $Fadd | tail -n +2 >> $Fout; 
    echo " end"
fi

if [[ -f $FaddDB ]]
then 
    echo -n "Merge CSV file for DataBase with file \"${FaddDB}\"..."
    cat $FaddDB | tail -n +2 >> $FoutDB; 
    echo " end"
fi

echo "Processing:"
if [[ -f "$Ftmp.wwnhost" ]] && [[ -f "$Fsansw" ]]
then 
    echo -n "Check SAN PortName and HostName..."

    #-------------------------------------------
    # Check SAN PortName and HostName on Storage
    if [[ -f $Ftmp2 ]]; then rm $Ftmp2; fi

    index=0
    declare -a wh
    while read line; do
	wh[$index]="$line"
	index=$(($index+1))
    done < "$Ftmp.wwnhost"
    
    for ((b=0; b < ${#wh[*]}; b++))
    do
	str="${wh[$b]}"
    	    
    	hostWWN=`echo "$str" | cut -f1`
    	hostName=`echo "$str" | cut -f2`
    	hostStor=`echo "$str" | cut -f3`; hostStor=${hostStor//","/", "}
	    
	#sansw.sh - Date,Room,Fabric+,Switch Name+,Domen+,IP,Switch WWN,Model,Firmware,Serial#,Config,Port#+,Port Name,Speed+,Status,State,Type,Port WWN,Device WWPN,Alias,Zone,SFP#+,Wave+,SFP Vendor,SFP Serial#,SFP Speed
    	title=$( cat "$Fsansw" | head -n 1 )

    	#do not check port with more 1 WWPN, for exclude NPIV
    	pos=$(val2pos "$title" "," "Device WWPN")
    	sanWWPN=`cat "$Fsansw" | grep "$hostWWN" | cut -d, -f$pos`
    	sanWWPN="${sanWWPN//"; "/"\n"}"
    	sanWWPNcount=`echo -n "$sanWWPN" | wc -l`
    	if [[ sanWWPNcount -gt 1 ]]; then continue; fi

    	pos=$(val2pos "$title" "," "Switch Name+")
    	sanName=`cat "$Fsansw" | grep "$hostWWN" | cut -d, -f$pos`
    	pos=$(val2pos "$title" "," "Room")
    	sanRoom=`cat "$Fsansw" | grep "$hostWWN" | cut -d, -f$pos`
    	pos=$(val2pos "$title" "," "Port Name")
    	sanPName=`cat "$Fsansw" | grep "$hostWWN" | cut -d, -f$pos`
    	pos=$(val2pos "$title" "," "Port#+")
    	sanPNum=`cat "$Fsansw" | grep "$hostWWN" | cut -d, -f$pos`
    	sanPNum="     $sanPNum"; sanPNum=${sanPNum:(${#sanPNum}-2)}
    	
    	if [[ "$hostName" != "$sanPName" ]]
    	then
    	    x="${sanRoom}, ${sanName}"
    	    if [[ "$x" == ", " ]]; then x="-"; fi
    	    xl=${#x}
	    if [[ $xl -lt 32 ]]; then x="${x}\t"; fi
    	    if [[ $xl -lt 24 ]]; then x="${x}\t"; fi
    	    if [[ $xl -lt 16 ]]; then x="${x}\t"; fi
    	    if [[ $xl -lt 8  ]]; then x="${x}\t"; fi
    	    sanSwitch="$x"

    	    x="[${sanPNum}] $sanPName"
    	    if [[ "$x" == "[  ] " ]]; then x="  -  "; fi
    	    xl=${#x}
	    if [[ $xl -lt 32 ]]; then x="${x}\t"; fi
    	    if [[ $xl -lt 24 ]]; then x="${x}\t"; fi
    	    if [[ $xl -lt 16 ]]; then x="${x}\t"; fi
    	    if [[ $xl -lt 8  ]]; then x="${x}\t"; fi
    	    sanPName="$x"
    		
    	    x="$hostName"
    	    if [[ "$x" == "" ]]; then x="-"; fi
    	    xl=${#x}
	    if [[ $xl -lt 32 ]]; then x="${x}\t"; fi
    	    if [[ $xl -lt 24 ]]; then x="${x}\t"; fi
    	    if [[ $xl -lt 16 ]]; then x="${x}\t"; fi
    	    if [[ $xl -lt 8  ]]; then x="${x}\t"; fi
    	    hostName="$x"

    	    echo -e "${sanSwitch}${sanPName}${hostName}$hostWWN, $hostStor" >> $Ftmp2
	fi
    done
    
    if [[ -f $Ftmp2 ]] 
    then
        echo "Processing SAN PortName and HostName" >> $Fout3
        echo "------------------------------------" >> $Fout3
        cat $Ftmp2 >> $Fout3
        echo "" >> $Fout3
        echo "" >> $Fout3
    fi

    echo " end"
fi

if [[ -f "$Ftmp.wwnhost" ]]
then 
    echo -n "Check WWN and HostName..."
    
    #----------------------------------
    # Check WWN and HostName on Storage
    #cat "$Ftmp.wwnhost" | sort -k 1,2 | uniq -d -w 23 --all-repeated=separate > $Ftmp
    cat "$Ftmp.wwnhost" | sort -uk 1,2 > $Ftmp
    if [[ -f $Ftmp2 ]]; then rm $Ftmp2; fi
    
    index=0
    declare -a wh
    while read line; do
        wh[$index]="$line"
	index=$(($index+1))
    done < $Ftmp
    
    index=0
    prevWWN=""
    prevhost=""
    prevstor=""
    prevstr=""
    for ((b=0; b < ${#wh[*]}; b++))
    do
        str="${wh[$b]}"
        curWWN=`echo "$str" | cut -f1`
        curhost=`echo "$str" | cut -f2`
        curstor=`echo "$str" | cut -f3`; curstor=${curstor//","/", "}
        if [[ $curWWN == $prevWWN ]]
        then 
    	    if [[ $index -eq 0 ]]
    	    then 
    		i=`grep -P "$prevWWN\t$prevhost" "$Ftmp.wwnhost" | wc -l`
    		x="$i $prevhost"
        	xl=${#x}
		if [[ $xl -lt 32 ]]; then x="${x}\t"; fi
    		if [[ $xl -lt 24 ]]; then x="${x}\t"; fi
    		if [[ $xl -lt 16 ]]; then x="${x}\t"; fi
    		if [[ $xl -lt 8  ]]; then x="${x}\t"; fi
    		x="$prevWWN\t\t${x}"
    		if [[ $i -eq 1 ]]; then x="${x}$prevstor"; else x="${x}($prevstor)"; fi
    		echo -e "${x}" >> $Ftmp2
    	    fi
    	    i=`grep -P "$curWWN\t$curhost" "$Ftmp.wwnhost" | wc -l`
    	    x="$i $curhost"
            xl=${#x}
	    if [[ $xl -lt 32 ]]; then x="${x}\t"; fi
    	    if [[ $xl -lt 24 ]]; then x="${x}\t"; fi
    	    if [[ $xl -lt 16 ]]; then x="${x}\t"; fi
    	    if [[ $xl -lt 8  ]]; then x="${x}\t"; fi
    	    x="$curWWN\t\t${x}"
    	    if [[ $i -eq 1 ]]; then x="${x}$curstor"; else x="${x}($curstor)"; fi
    	    echo -e "${x}" >> $Ftmp2
    	    index=$(($index+1))
    	    continue
    	else
    	    if [[ $index -gt 0 ]]; then echo "-" >> $Ftmp2; fi
    	    index=0
    	fi
    	prevWWN="$curWWN"
    	prevhost="$curhost"
	prevstor="$curstor"
    	prevstr="$str"
    done
    unset wh
    
    if [[ -f $Ftmp2 ]] 
    then
	echo "Processing WWN and HostName" >> $Fout3
	echo "---------------------------" >> $Fout3
	if [[ "$(tail -n 1 $Ftmp2)" != "-" ]]; then cat $Ftmp2 >> $Fout3; else cat $Ftmp2 | head -n -1 >> $Fout3; fi
	echo "" >> $Fout3
	echo "" >> $Fout3
    fi

    rm "$Ftmp.wwnhost"
    echo " end"
fi

echo "Post processing:"
if [[ -f "../csv2xls/csv2xls.pl" ]]
then 
    echo -n "Converting report file CSV to XLS..."
    eval "../csv2xls/csv2xls.pl $Fout $FoutXLS"
    echo " end"
    echo -n "Converting report file CSV for DataBase to XLS..."
    eval "../csv2xls/csv2xls.pl $FoutDB $FoutDBXLS"
    echo " end"
fi

if [[ -f "../smb/smbupload.sh" ]]
then
    echo "Upload to Inventory share.."
    eval "../smb/smbupload.sh storsw $Fout $FoutDB $FoutXLS $FoutDBXLS $Fout2 $Fout3"
    echo "..end"
fi

if [[ -f "../csv2mysql/csv2mysql.pl" ]]
then
    # Date,Room,Name+,IP,Firmware+,Capacity-,Used-,Free-,WWN,Ctrl#+,Ctrl WWPN,Ctrl Speed+,Ctrl Status+,Encl#+,Encl Status+,Encl Type,Encl PN#,Encl Serial#,Slots,Bkpl Speed,
    # Disk Encl#+,Disk Bay#+,Disk Status+,Disk Type,Disk Mode,Disk Size,Disk Speed+,Disk PN#,Disk Serial#,Disk Group,DG Status+,DG Size,DG Free,
    # Volume Name,Vol Status+,Vol Size,Volume WWID+,Volume Mapping,Vol DG,Func+,Host Name,Host Status+,Ports+,Device WWPN,Host Mapping
    echo "Upload to MySQL base.."
    eval "../csv2mysql/csv2mysql.pl $FoutDB storage \"Date,Name+,Room\" \"date,field1,field2\""
    echo "..end"
fi

if [[ -f $Ftmp ]]; then rm $Ftmp; fi
if [[ -f $Ftmp2 ]]; then rm $Ftmp2; fi
if [[ -f $FtmpC ]]; then rm $FtmpC; fi
if [[ -f $FtmpV ]]; then rm $FtmpV; fi

#if [[ -f $Flog ]]; then rm $Flog; fi

