#!/bin/bash

################################################################################
# Help                                                                         #
################################################################################
Help()
{
   # Display Help
   echo "Checks if the latest simulation ran to completion in the current directory and continues it"
   echo "This program is meant to be run when there are no simulations running in the current directory" 
   echo "Syntax: scriptTemplate [-h]"
   echo "option:"
   echo "h     Print this Help."
   echo
}

################################################################################
################################################################################

# Main program
# This program is a combination of 3 scripts: continuesimulation, simcheck and mostrecentsimulation.

# Get the options
while getopts ":h" option; do
   case $option in
      h) # display Help
         Help
         exit;;
   esac
done

#function to convert month to number
monthnumber() {
	month=$1
	months="JanFebMarAprMayJunJulAugSepOctNovDec"
	tmp=${months%%$month*}
	month=${#tmp}
	monthnumber=$((month/3+1))
	printf "%02d\n" $monthnumber
}

#this takes the ddmmmyy format of date and with the help of above function, monthnumber, it returns numeric date in the form of yyyymmdd that can be sorted
fullynumericdate () {
	string=$1
	year=$(expr ${string:$((${#string}-2))} + 2000 | bc)
	mon=${string:$((${#string}-5)):3}
	mon_num=$(monthnumber $mon) 
	day=$(printf %02d ${string%$mon*})  #using printf to add a zero to single digit dates so I get 07 instead of just 7.       
	numericdate="${year}${mon_num}${day}"	
	echo $numericdate
  }

#this function continues the simulation of the folder passed as the argument
continuesimulation () {
	folder=$1
	#capturing the relevant details for an appropriate naming of the files downstream
	prefix=$(grep -oP '\K.*(?=_cont)' <<< "$folder")
	contnumber=$(grep -oP 'cont\K.*(?=_)' <<< "$folder")
	oldcontnumber=$(expr $contnumber-1 | bc)
	newcontnumber=$(expr $contnumber+1 | bc)
	dayofsim=$(date +%d%b%y)
	suffix=${newcontnumber}_${dayofsim}
	newfolder=${prefix}_cont${suffix}

	echo "creating new folder..."
	mkdir "$newfolder" 
	cd $newfolder
	pathtonewfolder=$(pwd)
	cd ..

	#copying requisite files from old to new folder
	echo "copying files..."
	cd $folder
	LC_line=$(grep '^lastconf_file =' input.txt) 
	LC_file=${LC_line:16}
	cp input.txt run.sh *.top $LC_file $pathtonewfolder
	test -e external_forces.txt && cp external_forces.txt $pathtonewfolder #if external_forces file exists then copy it to the path of new folder else do nothing
	cd ..

	#editing input and run files
	echo "editing files..."
	cd $newfolder
	sed -i -e "s/LC_cont${contnumber}/LC_cont${newcontnumber}/g" input.txt #changing the last configuration name
	sed -i -e "s/LC_cont${oldcontnumber}/LC_cont${contnumber}/g" input.txt #initial configuration name 
	#The above order of editing the input file is important because otherwise, both the initial and last conf names would end up to be the same (same as the LC). 

	sed -i -e "s/$folder/$newfolder/g" run.sh #path of output files
	qsub run.sh
	echo "job submitted"

#Creating a dictionary with where the key is the foldername and the value is the numerical date processed from its name in yyyymmdd format 
declare -A z
folders=($(ls -d 4_*))
for folder in "${folders[@]}"; do z["$folder"]=$(fullynumericdate $(grep -o '[^_]*$' <<< "${folder}")); done

#creating an array of the dictionary's values
arrayofvalues=()
for value in "${z[@]}"; do
	arrayofvalues+=($value)
done

#sorting that array so the latest date can be accessed using -1 index
sortedarrayofvalues=($(sort -n < <(printf '%s\n' "${arrayofvalues[@]}")))

#finding the key (i.e. the folder) whose value is equal to the latest date obtained from the sorted array of values. 
for key in "${!z[@]}"; do
	if test ${z[$key]} == "${sortedarrayofvalues[-1]}"
	then
		recentsimfolder=$key
		echo "The most recent simulation folder is ${key}"
	fi
done

echo "Checking the most recent simulation folder ${recentsimfolder}..."

cd $recentsimfolder
steps_line=$(grep '^steps =' input.txt)
steps_enotation=${steps_line:8}
steps=$(printf "%.0f" $steps_enotation)
readarray -t listofsteps <<< "$(grep 't =' trajectory.dat)" #creates a list of all timesteps; each element having the prefix of 't = '
if test $steps -eq ${listofsteps[-1]:4} #accessing the last element/timestep of the list above & removing the prefix of 't =';then bash automatically takes it as an integer
then
	echo "The simulation ran to completion i.e. ${listofsteps[-1]:4} steps"
	echo "Readying for next simulation"
	continuesimulation $recentsimfolder
else
	echo "The simulation didn't complete; the last configuration created is ${listofsteps[-1]} therefore the last completed conf should be ${listofsteps[-2]}"  
	startingline=$(sed -n "/${listofsteps[-2]}/=" trajectory.dat)
	endingline=$(sed -n "/${listofsteps[-1]}/=" trajectory.dat)
	head_line=$(expr $endingline - 1 | bc)
	tail_line=$(expr $endingline - $startingline | bc)
	echo "Rejecting the last configuration generated by the incomplete simulation..."
	LC_line=$(grep '^lastconf_file =' input.txt) 
	LC_file=${LC_line:16}
	mv $LC_file LC_rejected.dat
	echo "Extracting the last completed configuration to continue simulation..." 
	head -n $head_line trajectory.dat | tail -n $tail_line > file.dat  
	mv file.dat $LC_file
	echo "Modifying the input file so that simulation time can be correctly calculated for analysis"
	sed -i -e "s/${steps_enotation}/${listofsteps[-2]:4}/g" input.txt
	echo "Done"
	echo "Readying for next simulation"
	continuesimulation $recentsimfolder
fi
cd ..



