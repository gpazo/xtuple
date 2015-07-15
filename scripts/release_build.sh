#!/usr/bin/env bash
set -e

PROG=$(basename $0)
DEBUG=false
ADMIN=admin
PASSWD=admin
PORT=5432
HOST=localhost
MAJ=
MIN=
PAT=

XTUPLEDIR=$(pwd)

#  github repo        ARGS=derive from command line, default=default github branch
#                             true=use this in the build
#                                   path for build_app -e, relative to repo root
#  module             tag     build source
declare -a CONFIG=(\
  "xtuple             ARGS    skip  not-needed"                                  \
  "private-extensions ARGS    skip  not-needed"                                  \
  "xtdesktop          default false not-yet-used"                                \
  "xtte               default false extensions/time_expense/foundation-database" \
)

usage() {
  local CNT=0
  cat <<EOUSAGE
$PROG [ -x ] [ -h hostname ] [ -p port ] [ -U username ] [ -W password ] [ --XXX=tag ... ] Major Minor Patch

-h, -p, -U, and -W describe database server connection information
-x              turns on debugging
--XXX=tag       "tag" is the commit-ish to check out the XXX repository
EOUSAGE
  echo -n "possible values of XXX: "
  while [ $CNT -lt ${#CONFIG[*]} ] ; do
    echo ${CONFIG[$CNT]} | awk '{ printf "%s ", $1 }'
    CNT=$(($CNT + 1))
  done
  echo
}

getConfig() {
  local MODULE=$1 COL=$2 ROWNUM=0 ROW

  while [ -z "$ROW" -a -n "${CONFIG[$ROWNUM]}" ] ; do
    if [ "$MODULE" = $(echo "${CONFIG[$ROWNUM]}" | awk '{ print $1 }') ] ; then
      ROW="${CONFIG[$ROWNUM]}"
    else
      ROWNUM=$(($ROWNUM + 1))
    fi
  done

  case $COL in
    module) COL=1 ;;
    tag)    COL=2 ;;
    build)  COL=3 ;;
    source) COL=4 ;;
    *) echo "getConfig: unknown build config column $2"; return 1;;
  esac
  echo "$ROW" | awk -v COLNUM=$COL '{ print $COLNUM }'
}

setConfig() {
# setConfig module column-by-name value
  local MODULE=$1 COL=$2 ROWNUM=0 NEWROW

  while [ $ROWNUM -lt ${#CONFIG[*]} ] ; do
    if [ "$MODULE" = $(echo "${CONFIG[$ROWNUM]}" | awk '{ print $1 }') ] ; then
      break
    fi
    ROWNUM=$(($ROWNUM + 1))
  done

  case $COL in
    module) COL=1 ;;
    tag)    COL=2 ;;
    build)  COL=3 ;;
    source) COL=4 ;;
    *) echo "setConfig: unknown build config column $2"; return 1;;
  esac
  CONFIG[$ROWNUM]=$(echo ${CONFIG[$ROWNUM]} | \
                awk -v COL=$COL -v NEWVAL=$3 '{ for (i = 1; i <= NF; i++) {
                                                if (i == COL)
                                                  printf "%s\t", NEWVAL;
                                                else printf "%s\t", $i; }
                                            }')
  return 0
}

gitco() {
  local REPO=$1
  cd $XTUPLEDIR/../$REPO                                        || return 2

  local XTUPLE=$(git remote -v | grep /xtuple/ | head -n 1 | cut -f1)
  git fetch    $XTUPLE                                          || return 2

  local GITURL=$(git remote -v | grep /xtuple/ | head -n 1 | cut -f2)
  local GITTAG=$(getConfig $REPO tag)

  if [ $GITTAG = default ] ; then
    GITHUBREPO=$(echo $GITURL | sed -e "s,.*xtuple/,xtuple/," -e "s,\.git,,")
    GITTAG=$XTUPLE/$(curl https://api.github.com/repos/${GITHUBREPO} | \
                     awk -v FS='"' '/default_branch/ { print $4 }')
    if [ -z "$GITTAG" ] ; then
      GITTAG=$XTUPLE/master
    fi
  fi
  git checkout $GITTAG                                          || return 2
}

while [[ $1 =~ ^- ]] ; do
  case $1 in
    -h) HOST=$2
        shift
        ;;
    -p) PORT=$2
        shift
        ;;
    -U) ADMIN=$2
        shift
        ;;
    -W) PASSWD=$2
        shift
        ;;
    -x) set -x
        DEBUG=true
        ;;
    --*=*)
        REPO=$(expr   "$1" : "--\(.*\)=.*")
        RAWTAG=$(expr "$1" : ".*=\(.*\)")
        setConfig $REPO tag   $RAWTAG
        setConfig $REPO build true
        ;;
    *)  echo "$PROG: unrecognized option $1"
        usage
        exit 1
        ;;
  esac
  shift
done

if [ $# -lt 3 ] ; then
  echo $PROG: Major, Minor, and Patch release values are required
  usage
  exit 1
fi

MAJ=$1
MIN=$2
PAT=$3

if [ $(getConfig xtuple tag) = ARGS ] ; then
  setConfig xtuple             tag ${MAJ}_${MIN}_x
fi
if [ $(getConfig private-extensions tag) = ARGS ] ; then
  setConfig private-extensions tag ${MAJ}_${MIN}_x
fi

echo "BUILDING RELEASE ${MAJ}.${MIN}.${PAT}"

# check out the code that we need #########################################

CNT=0
while [ $CNT -lt ${#CONFIG[*]} ] ; do
  MODULE=$(echo ${CONFIG[$CNT]} | awk '{ print $1 }')
  case $(getConfig $MODULE build) in
    true) gitco $MODULE || $DEBUG
          ;;
    skip) echo skipping $MODULE checkout
          ;;
    false);;
  esac
  CNT=$(($CNT + 1))
done

cd $XTUPLEDIR
rm -rf scripts/output
npm run-script build-basic-postbooks-package-sql
npm run-script build-basic-empty
npm run-script build-basic-postbooks-demo
npm run-script build-basic-quickstart

cd ${XTUPLEDIR}/../private-extensions
npm run-script build-basic-manufacturing-package-sql
npm run-script build-basic-manufacturing-empty
npm run-script build-basic-manufacturing-quickstart
npm run-script build-basic-manufacturing-demo
npm run-script build-basic-distribution-package-sql
npm run-script build-basic-distribution-empty
npm run-script build-basic-distribution-quickstart

#postbooks upgrade
cd ${XTUPLEDIR}
mkdir scripts/output/postbooks-upgrade-$MAJ$MIN$PAT
cp scripts/xml/postbooks_package.xml scripts/output/postbooks-upgrade-$MAJ$MIN$PAT/package.xml
cp scripts/output/postbooks_upgrade.sql scripts/output/postbooks-upgrade-$MAJ$MIN$PAT
cd scripts/output
tar -zcvf postbooks-upgrade-$MAJ$MIN$PAT.gz postbooks-upgrade-$MAJ$MIN$PAT/

#distribution upgrade
cd ${XTUPLEDIR}
mkdir scripts/output/distribution-upgrade-$MAJ$MIN$PAT
cp scripts/xml/distribution_package.xml scripts/output/distribution-upgrade-$MAJ$MIN$PAT/package.xml
cp scripts/output/postbooks_upgrade.sql scripts/output/distribution-upgrade-$MAJ$MIN$PAT
cp scripts/output/inventory_upgrade.sql scripts/output/distribution-upgrade-$MAJ$MIN$PAT
cp scripts/output/commercialcore_upgrade.sql scripts/output/distribution-upgrade-$MAJ$MIN$PAT
cp scripts/output/distribution_upgrade.sql scripts/output/distribution-upgrade-$MAJ$MIN$PAT
cd scripts/output
tar -zcvf distribution-upgrade-$MAJ$MIN$PAT.gz distribution-upgrade-$MAJ$MIN$PAT/

#distribution install
cd ${XTUPLEDIR}
mkdir scripts/output/distribution-install-$MAJ$MIN$PAT
cp scripts/xml/distribution_install.xml scripts/output/distribution-install-$MAJ$MIN$PAT/package.xml
cp scripts/output/postbooks_upgrade.sql scripts/output/distribution-install-$MAJ$MIN$PAT
cp scripts/output/inventory_basic_install.sql scripts/output/distribution-install-$MAJ$MIN$PAT
cp scripts/output/inventory_upgrade.sql scripts/output/distribution-install-$MAJ$MIN$PAT
cp scripts/output/commercialcore_basic_install.sql scripts/output/distribution-install-$MAJ$MIN$PAT
cp scripts/output/commercialcore_upgrade.sql scripts/output/distribution-install-$MAJ$MIN$PAT
cp scripts/output/distribution_basic_install.sql scripts/output/distribution-install-$MAJ$MIN$PAT
cp scripts/output/distribution_upgrade.sql scripts/output/distribution-install-$MAJ$MIN$PAT
cd scripts/output
tar -zcvf distribution-install-$MAJ$MIN$PAT.gz distribution-install-$MAJ$MIN$PAT/

#manufacturing upgrade
cd ${XTUPLEDIR}
mkdir scripts/output/manufacturing-upgrade-$MAJ$MIN$PAT
cp scripts/xml/xtmfg_package.xml scripts/output/manufacturing-upgrade-$MAJ$MIN$PAT/package.xml
cp scripts/output/postbooks_upgrade.sql scripts/output/manufacturing-upgrade-$MAJ$MIN$PAT
cp scripts/output/inventory_upgrade.sql scripts/output/manufacturing-upgrade-$MAJ$MIN$PAT
cp scripts/output/commercialcore_upgrade.sql scripts/output/manufacturing-upgrade-$MAJ$MIN$PAT
cp scripts/output/manufacturing_upgrade.sql scripts/output/manufacturing-upgrade-$MAJ$MIN$PAT
cd scripts/output
tar -zcvf manufacturing-upgrade-$MAJ$MIN$PAT.gz manufacturing-upgrade-$MAJ$MIN$PAT/

#manufacturing install
cd ${XTUPLEDIR}
mkdir scripts/output/manufacturing-install-$MAJ$MIN$PAT
cp scripts/xml/xtmfg_install.xml scripts/output/manufacturing-install-$MAJ$MIN$PAT/package.xml
cp scripts/output/postbooks_upgrade.sql scripts/output/manufacturing-install-$MAJ$MIN$PAT
cp scripts/output/inventory_basic_install.sql scripts/output/manufacturing-install-$MAJ$MIN$PAT
cp scripts/output/inventory_upgrade.sql scripts/output/manufacturing-install-$MAJ$MIN$PAT
cp scripts/output/commercialcore_basic_install.sql scripts/output/manufacturing-install-$MAJ$MIN$PAT
cp scripts/output/commercialcore_upgrade.sql scripts/output/manufacturing-install-$MAJ$MIN$PAT
cp scripts/output/manufacturing_basic_install.sql scripts/output/manufacturing-install-$MAJ$MIN$PAT
cp scripts/output/manufacturing_upgrade.sql scripts/output/manufacturing-install-$MAJ$MIN$PAT
cd scripts/output
tar -zcvf manufacturing-install-$MAJ$MIN$PAT.gz manufacturing-install-$MAJ$MIN$PAT/

#enterprise upgrade
cd ${XTUPLEDIR}
mkdir scripts/output/enterprise-upgrade-$MAJ$MIN$PAT
cp scripts/xml/ent_package.xml scripts/output/enterprise-upgrade-$MAJ$MIN$PAT/package.xml
cp scripts/output/postbooks_upgrade.sql scripts/output/enterprise-upgrade-$MAJ$MIN$PAT
cp scripts/output/inventory_upgrade.sql scripts/output/enterprise-upgrade-$MAJ$MIN$PAT
cp scripts/output/commercialcore_upgrade.sql scripts/output/enterprise-upgrade-$MAJ$MIN$PAT
cp scripts/output/distribution_upgrade.sql scripts/output/enterprise-upgrade-$MAJ$MIN$PAT
cp scripts/output/manufacturing_upgrade.sql scripts/output/enterprise-upgrade-$MAJ$MIN$PAT
cd scripts/output
tar -zcvf enterprise-upgrade-$MAJ$MIN$PAT.gz enterprise-upgrade-$MAJ$MIN$PAT/

#enterprise install
cd ${XTUPLEDIR}
mkdir scripts/output/enterprise-install-$MAJ$MIN$PAT
cp scripts/xml/ent_install.xml scripts/output/enterprise-install-$MAJ$MIN$PAT/package.xml
cp scripts/output/postbooks_upgrade.sql scripts/output/enterprise-install-$MAJ$MIN$PAT
cp scripts/output/inventory_basic_install.sql scripts/output/enterprise-install-$MAJ$MIN$PAT
cp scripts/output/inventory_upgrade.sql scripts/output/enterprise-install-$MAJ$MIN$PAT
cp scripts/output/commercialcore_basic_install.sql scripts/output/enterprise-install-$MAJ$MIN$PAT
cp scripts/output/commercialcore_upgrade.sql scripts/output/enterprise-install-$MAJ$MIN$PAT
cp scripts/output/distribution_basic_install.sql scripts/output/enterprise-install-$MAJ$MIN$PAT
cp scripts/output/distribution_upgrade.sql scripts/output/enterprise-install-$MAJ$MIN$PAT
cp scripts/output/manufacturing_basic_install.sql scripts/output/enterprise-install-$MAJ$MIN$PAT
cp scripts/output/manufacturing_upgrade.sql scripts/output/enterprise-install-$MAJ$MIN$PAT
cd scripts/output
tar -zcvf enterprise-install-$MAJ$MIN$PAT.gz enterprise-install-$MAJ$MIN$PAT/

cd ${XTUPLEDIR}

awk '/databaseServer: {/,/}/ {
      if ($1 == "hostname:") { $2 = "\"'$HOST'\",";  }
      if ($1 == "port:")     { $2 = "'$PORT',";      }
      if ($1 == "admin:")    { $2 = "\"'$ADMIN'\","; }
      if ($1 == "password:") { $2 = "\"'$PASSWD'\""; }
    }
    { print
    }' node-datasource/config.js > scripts/output/config.js


DB_LIST="postbooks_demo empty quickstart distempty distquickstart mfgempty mfgquickstart mfgdemo";
for DB in $DB_LIST ; do
  CNT=0
  while [ $CNT -lt ${#CONFIG[*]} ] ; do
    MODULE=$(echo ${CONFIG[$CNT]} | awk '{ print $1 }')
    MODULESRCDIR=$XTUPLEDIR/../$MODULE/$(getConfig $MODULE source)
    if [ -d $MODULESRCDIR ] ; then
      scripts/build_app.js -c scripts/output/config.js -e $MODULESRCDIR -d $DB
    fi
    CNT=$(($CNT + 1))
  done
  /usr/bin/pg_dump --host $HOST --username $ADMIN --port $PORT --format c --file $DB-$MAJ.$MIN.$PAT.backup $DB
done

#cleanup
cd ${XTUPLEDIR}
rm -rf scripts/output/postbooks-upgrade-$MAJ$MIN$PAT/
rm -rf scripts/output/postbooks_upgrade.sql
rm -rf scripts/output/distribution-install-$MAJ$MIN$PAT/
rm -rf scripts/output/distribution-upgrade-$MAJ$MIN$PAT/
rm -rf scripts/output/distribution_upgrade.sql
rm -rf scripts/output/distribution_basic_install.sql
rm -rf scripts/output/inventory_basic_install.sql
rm -rf scripts/output/inventory_upgrade.sql
rm -rf scripts/output/commercialcore_basic_install.sql
rm -rf scripts/output/commercialcore_upgrade.sql
rm -rf scripts/output/manufacturing-install-$MAJ$MIN$PAT/
rm -rf scripts/output/manufacturing-upgrade-$MAJ$MIN$PAT/
rm -rf scripts/output/enterprise-upgrade-$MAJ$MIN$PAT/
rm -rf scripts/output/enterprise-install-$MAJ$MIN$PAT/
rm -rf scripts/output/manufacturing_basic_install.sql
rm -rf scripts/output/manufacturing_upgrade.sql
rm -rf scripts/output/config.js
