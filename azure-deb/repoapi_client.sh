#!/bin/bash
# This is a VERY basic script for Create/Delete operations on repos and packages
# 
defaultPackageFile=new_package.json
defaultRepoFile=new_repo.json

function BailIf
{
    if [ $1 -ne 0 ]; then
        echo "Failure occurred communicating with $server"
        exit 1
    fi
}

# List packages, using $1 as a regex to filter results
function ListPackages
{
    curl -k "$baseurl/v1/packages" | sed 's/{/\n{/g' | egrep "$1" | sed 's/,/,\n/g' | sed 's/^"/\t"/g'
    echo ""
}

# Create a new Repo using the specified JSON file
function AddRepo
{
    repoFile=$1
    if [ -z $repoFile ]; then
        echo "Error: Must specify a JSON-formatted file. Reference $defaultRepoFile.template"
        exit 1
    fi
    if [ ! -f $repoFile ]; then
        echo "Error: Cannot create repo - $repoFile does not exist"
        exit 1
    fi
    packageUrl=$(grep "url" $repoFile  | head -n 1 | awk '{print $2}' | tr -d ',')
    echo "Creating new repo on $server [$packageUrl]"
    curl -i -k "$baseurl/v1/repositories" --data @./$repoFile -H "Content-Type: application/json"
    BailIf $?
    echo ""
}

# Upload a single package using the specified JSON file
function AddPackage
{
    packageFile=$1
    if [ -z $packageFile ]; then
        echo "Error: Must specify a JSON-formatted file. Reference $defaultPackageFile.template"
        exit 1
    fi
    if [ ! -f $packageFile ]; then
        echo "Error: Cannot add package - $packageFile does not exist"
        exit 1
    fi
    packageUrl=$(grep "sourceUrl" $packageFile  | head -n 1 | awk '{print $2}')
    echo "Adding package to $server [$packageUrl]"
    curl -i -k "$baseurl/v1/packages" --data @./$packageFile -H "Content-Type: application/json"
    BailIf $?
    echo ""
}

# Upload a single package by dynamically creating a JSON file using a provided URL
function AddPackageByUrl
{
	# Parse URL
	url=$(echo "$1")
    if [ -z $url ]; then
        return
    fi
	escapedUrl=$(echo "$url" | sed 's/\//\\\//g')
	set -- "$1" 
	oldIFS=$IFS
	IFS="/"; declare -a splitUrl=($*) 
	index=${#splitUrl[@]}
	let "index -= 1"
	filename=${splitUrl[$index]}
	set -- "$filename"
	IFS="_"; declare -a splitFile=($*)
	IFS=$oldIFS
	pkgName=${splitFile[0]}
	pkgVer=${splitFile[1]}
	if [ -z $pkgName ] || [ -z $pkgVer ]; then
		echo "ERROR parsing $url"
		return
	fi
	# Create Package .json file
	cp $defaultPackageFile.template $defaultPackageFile
	sed -i "s/PACKAGENAME/$pkgName/g" $defaultPackageFile
	sed -i "s/PACKAGEVERSION/$pkgVer/g" $defaultPackageFile
	sed -i "s/PACKAGEURL/$escapedUrl/g" $defaultPackageFile
	sed -i "s/REPOSITORYID/$repositoryId/g" $defaultPackageFile
	# Test that URL is ok
	wget -q --spider "$url"
	if [[ $? -eq 0 ]]; then
		echo "Ready to upload $pkgName [$pkgVer]"
	else
		echo "ERROR testing URL $url"
		return
	fi
	# Perform Upload
	AddPackage $defaultPackageFile
	# Cleanup
	# rm $defaultPackageFile
}

# Upload multiple packages by reading urls line-by-line from the specified file
function AddPackages
{
    urlFile=$1
    if [ -z $urlFile ]; then
        echo "Error: Must specify a flat text file containing one or more URLs"
        exit 1
    fi
    if [ ! -f $urlFile ]; then
        echo "Error: Cannot add packages. File $urlFile does not exist"
        exit 1
    fi
    for url in $(cat $urlFile); do
        AddPackageByUrl "$url" 
        sleep 5
    done
}

# Delete the specified repo
function DeleteRepo
{
    repoId=$1
    if [ -z $repoId ]; then
        echo "Error: Please specify repository ID. Run -listrepos for a list of IDs"
        exit 1
    fi
    curl -I -k -X DELETE "$baseurl/v1/repositories/$repoId"
    BailIf $?
}

# Delete the specified package
function DeletePackage
{
    packageId=$1
    if [ -z $packageId ]; then
        echo "Error: Please specify package ID. Run -listpkgs for a list of IDs"
        exit 1
    fi
    echo Removing pkgId $packageId from repo $repositoryId
    curl -I -k -X DELETE "$baseurl/v1/packages/$packageId"
    BailIf $?
}

usage()
{
    echo "Usage: $0 [-p pass] cmd arg" 1>&2
    exit 1
}

repositoryId=$REPOSITORYID

server=azure-apt-cat.cloudapp.net
user=sonic
protocol=https
port=443

while getopts "p:" opt; do
  case $opt in
    p)
      pass=$OPTARG
      ;;
    *)
      usage
      ;;
  esac
done

baseurl="$protocol://$user:$pass@$server:$port"

shift $((OPTIND-1))

cmd=$1

echo $cmd
if [[ "$1" == "listrepos" ]]; then
  echo "Fetching repo list from $server..."
  curl -k "$baseurl/v1/repositories" | sed 's/,/,\n/g' | sed 's/^"/\t"/g'
  echo ""
elif [[ "$1" == "listpkgs" ]]; then
  echo "Fetching package list from $server"
  ListPackages $2
elif [[ "$1" == "addrepo" ]]; then
  AddRepo $2
elif [[ "$1" == "addpkg" ]]; then
  AddPackage $2
elif [[ "$1" == "addpkgs" ]]; then
  AddPackages $2
elif [[ "$1" == "delrepo" ]]; then
  DeleteRepo $2
elif [[ "$1" == "delpkg" ]]; then
  DeletePackage $2
else
  echo "USAGE: ./repotool.sh -p PASS cmd arg"
  echo "listrepos: Gather a list of repos"
  echo "listpkgs:  Gather a list of packages"
  echo "addrepo [FILENAME] :   Create a new repo using the specified JSON file"
  echo "addpkg [FILENAME]  :   Add package to repo using the specified JSON file"
  echo "addpkgs [FILENAME] :   Add packages to repo using urls contained in FILENAME"
  echo "delrepo REPOID     :   Delete the specified repo by ID"
  echo "delpkg PKGID       :   Delete the specified package by ID"
fi
