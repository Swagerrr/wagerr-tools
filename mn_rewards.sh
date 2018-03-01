#!/bin/bash
#
# Swagerr
#
# Dependencies: jq, bc
#

clear

wcli="./wagerr-cli"
if [ ! -f "$wcli" ]; then
  wcli=$(find / -type f -name "wagerr-cli" 2>/dev/null | head -1)
  echo "Found $wcli"
fi
if [ ! -f "$wcli" ]; then
  echo "Could not find 'wagerr-cli' Run this script in your wagerr bin directory"
  exit 1
fi

wconf="~/.wagerr/wagerr.conf"
if [ ! -f "$wconf" ]; then
  wconf=$(find / -type f -name "wagerr.conf" 2>/dev/null | head -1)
  echo "Found $wconf"
fi
echo ""
if [ ! -f "$wconf" ]; then
  echo "Could not find 'wagerr.conf'"
  exit 1
fi

# user check
confUser=$(stat -c '%U' $wconf)
currentUser=$(whoami)
if [ "$confUser" != "$currentUser" ]; then
  path=$(readlink -f $0)
  su -c "$path $@" $confUser
  exit
fi

wcmd="${wcli} -conf=${wconf}" 

which jq &>/dev/null
if [ "$?" -ne 0 ]; then
  echo "Could not find 'jq'. Install 'jq' package to use this script."
  exit 1
fi
which bc &>/dev/null
if [ "$?" -ne 0 ]; then
  echo "Could not find 'bc'. Install 'bc' package to use this script."
  exit 1
fi

# Test wagerrd connectivety
${wcmd} getmasternodecount &>/dev/null
if [ "$?" -ne 0 ]; then
  echo "Error communicating with wagerr daemon"
  exit 1
fi

echo "==== General Rewards Info ==="
echo ""

mnCount=$(${wcmd} getmasternodecount | jq .enabled)
echo "Total # of Masternodes: $mnCount"

minTimeSec=$(echo "scale=0; ($mnCount * 60 * 2.6)/1" | bc -l)
minTimeMin=$(echo "scale=0; ($minTimeSec / 60)/1" | bc -l)
minTimeHours=$(echo "scale=2; ($minTimeMin / 60)/1" | bc -l)
echo "Minimum Active Time for Rewards: $minTimeSec seconds (${minTimeHours} hours)"


allMN=$(${wcmd} listmasternodes)
eligible=$(echo $allMN | jq "[ .[] | select(.activetime > $minTimeSec) ] | sort_by(.lastpaid)")

numEligible=$(echo $eligible | jq '. | length')
num10=$(echo "scale=0; ($numEligible /10)/1" | bc -l)
echo "# of Masternodes Eligible for Rewards: $numEligible"
echo "# of Masternodes in 10% lottery: $num10"

# Specific Masternode Info
echo ""

# Test masternode status
${wcmd} masternode status &>/dev/null
if [ "$?" -ne 0 ]; then
  echo "This server is not a masternode"
  exit 1
fi

if [ $# -eq 2 ]; then
  mnTxHash=$1
  mnTxId=$2
else 
  mnTxHash=$(${wcmd} masternode status | jq -r .txhash)
  mnTxId=$(${wcmd} masternode status | jq -r .outputidx)
fi

echo "==== Rewards Info for ${mnTxHash}:${mnTxId} ==="
echo ""

i=1
found=0
while read tx && read idx
do
  if [ "$mnTxHash" == "$tx" -a "$mnTxId" == "$idx" ]; then
    found=1
    break
  fi
  i=$[$i+1]
done < <(echo $eligible | jq -r '.[] | (.txhash, .outidx)')

mnInfo=$(echo $allMN | jq ".[] | select(.outidx==$mnTxId and .txhash==\"$mnTxHash\")")
if [ "$mnInfo" == "" ]; then
  echo "Your masternode not found in masternode list"
else
  mnStatus=$(echo $mnInfo | jq -r ".status")
  mnActiveTime=$(echo $mnInfo | jq -r ".activetime")
  mnLastPaid=$(echo $mnInfo | jq -r ".lastpaid")

  if [ "$mnStatus" != "ENABLED" ]; then
    echo "Masternode not Enabled"
    exit
  fi

  # Get waiting period requirements

  mnWaitingSec=0
  if [ "$mnActiveTime" -lt "$minTimeSec" ]; then
    mnWaitingSec=$(echo "$minTimeSec - $mnActiveTime" | bc -l)
  fi
  mnWaitingMin=$(echo "scale=0; ($mnWaitingSec / 60)/1" | bc -l)
  mnWaitingHours=$(echo "scale=2; ($mnWaitingMin / 60)/1" | bc -l)

  echo -n "Masternode met Active Time requirement: "
  if [ "$mnWaitingSec" != "0" ]; then
    echo "No"
    mnLotterySec=$(echo "scale=0; ($numEligible * .9 * 60)/1" | bc -l)
    echo "Waiting period remaining: $mnWaitingSec seconds ($mnWaitingHours hours)"
  else
    echo "Yes"
    if [ "$i" -le "$num10" ]; then
      mnLotterySec=0
    else 
      mnLotterySec=$(echo "scale=0; (($i - $num10) * 60)/1" | bc -l)
    fi
  fi
  mnLotteryMin=$(echo "scale=0; ($mnLotterySec / 60)/1" | bc -l)
  mnLotteryHours=$(echo "scale=2; ($mnLotteryMin / 60)/1" | bc -l)

  echo -n "In Lottery: "
  if [ "$mnLotterySec" -eq 0 ]; then
    echo "Yes"
  else
    echo "No"
  fi
  echo "Time remaining in queue for lottery: $mnLotterySec seconds ($mnLotteryHours hours)"

  # Now check the line of last paids
  
  totalWaitSec=$(echo "$mnWaitingSec + $mnLotterySec" | bc -l)
  totalWaitHours=$(echo "scale=2; ($totalWaitSec / 60 / 60)/1" | bc -l)

  echo "Total estimated wait time until eligible for lottery: $totalWaitSec seconds ($totalWaitHours hours)"
  
  lotTimeSec=$(echo "scale=0; (($num10 / 2) * 60)" | bc -l)
  lotTimeMin=$(echo "scale=0; ($lotTimeSec / 60)/1" | bc -l)

  echo "Average Lottery Time: $lotTimeSec seconds ($lotTimeMin minutes)"

  tillRewardSec=$(echo "$lotTimeSec + $totalWaitSec" | bc -l)
  tillRewardMin=$(echo "scale=0; ($tillRewardSec / 60)/1" | bc -l)
  tillRewardHours=$(echo "scale=2; ($tillRewardMin / 60)/1" | bc -l)

  echo ""
  echo "Estimated time until block reward: $tillRewardMin minutes ($tillRewardHours hours)"


fi


echo ""
