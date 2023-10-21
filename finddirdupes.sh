#! /bin/sh -

# check if first argument exists
if ! dir=$(ls -pd "$1"); then
	prog=$(basename $0)
	echo "$prog - Finds duplicate folders 
First checks the size, then check the hash of folders with the same size.

Usage:

Find duplicate folders inside directory:
	$prog dir_name

Specify the minimum size of folders to consider, in bytes:
	$prog dir_name min_size

Example: analyze the folders contained in the current folder and ignore the empty ones.
	$prog . 5000"
fi

#######################################################
############# define helper function ##################

# function that takes a non-cryptographic hash of a folder which gets calculated from the hash of all the contained files, regardless the file names
hash_dir () {
	# it ignores the presence of symbolic links
	if [[ -L "$1" ]]; then
		>&2 echo Ignoring symbolic link $1
	elif [[ -d "$1" ]]; then
		# checks if the folder is accessible (readable and executable)
		# in case it is not, mark this and the parent folders as bad content
		# folders with bad content will not be considered for duplicates
		if [[ ! -x "$1" || ! -r "$1" ]]; then
			>&2 echo Found non-accessible folder $1, ignoring all the parent folders
			echo ////BAD CONTENT////
		else
			# launch this same function, in a recursive fashion, 
			# over all the found subdirectories and files
			dirhashes=$(ls -1Ap "$1" | while read p; do hash_dir "$1$p"; done)
			# if any of the subdirectories had something marked as
			# "bad content", then mark also this parent folder as bad content
			if [[ $dirhashes =~ "////BAD CONTENT////" ]]; then
				echo ////BAD CONTENT////
			else
				# otherwise sort the content by hash (not by file name!)
				# and take a hash of the hashes of the subdirectories and files 
				dirhash=$(echo $dirhashes | sort | xxhsum -H3)
				# print hash for the parent function to process
				echo $dirhash
				# use a new pipe (as STDOUT is used for marking bad content
				# and hashes and STDERR has often errors) for outputting the 
				# actually interesting output
				# this implies, that when calling this function, there has to be
				# some redirect in place, ready for capturing pipe 3, e. g.:
				# hash_dir ./ 3>&1
				# otherwise, you get an error:
				# hash_dir ./
				# 3: bad file descriptor
				>&3 echo $dirhash $1
			fi
		fi
	# if a non-regular file (e.g. pipes, block devices...) is found, mark
	# the directory as bad content
	elif [[ ! -f "$1" ]]; then
		>&2 echo Found non-regular file $1, ignoring all the parent folders
		echo ////BAD CONTENT////
	# if a non-readable file is found, mark the directory as bad content, so that
	# it does not get considered for duplicates
	elif [[ ! -r "$1" ]]; then
		>&2 echo Found non-readable file $1, ignoring all the parent folders
		echo ////BAD CONTENT////
	# if the given argument was a simple file, take its hash
	else
		# the hash function has been selected based on a comparison published
		# by its authors:
		# https://xxhash.com/#benchmarks
		hash=$(xxhsum -H3 < "$1")
		echo $hash
		# when using this function out of the finddirdupes.sh file, you can set 
		# an environment variable for printing also the file hashes
		[ $ALSO_FILES ] && >&3 echo $hash $1
	fi
}

# check if the second argument is a number, if so, use it as minimum folder size
# https://stackoverflow.com/a/808740/5033401
if [ -n "$2" ] && [ "$2" -eq "$2" ] 2>/dev/null; then
	du_out=$(du -t $2 $dir)
else
	du_out=$(du $dir)
fi

#######################################################
########### find folders with the same size ###########

# find how many characters wide is the size column of the du output
du_out_last_line=$(tail -1 <<< $du_out)
max_size_length=$(echo -n $du_out_last_line | cut -d" " -f 1 | wc -c)

# uniq cannot understand what the "first field" is, it wants a number of characters
# but du uses a tab for separating the column,
# so the number of characters of the first column is different for each line
# so I increase the separation between columns adding some padding
du_out_spacer=$(sed 's/\t/...................\//' <<< $du_out)

# keep only the directories with the same size
du_dups=$(sort <<< $du_out_spacer | uniq -D -w $max_size_length )

#######################################################
############### eliminate subfolders ##################

# exclude from the folders list all the folders which have a parent folder also in the list
# for example, if the folders list was:
#  uno/due
#  uno
#  tre
# then the parents list will be:
#  uno
#  tre

# list folders, removing the size
folders=$(cut -d"/" -f 2- <<< $du_dups)

# append slash
folders_slash=$(sed 's/$/\//' <<< $folders )

# remove from the list all the folders which contain the name of another folder plus a slash
# which are the subfolders of another folder in the list
parents=$(grep -v -f <(cat <<< $folders_slash) <<< $folders)

#######################################################
####### analyze in deep the selected folders ##########

hash_dir_dups=""
for parent in $parents; do
	# use the hash_dir function for calculating the hash of the folders
	# ignore the internal bad content marks
	hash_dir_dups+=$(hash_dir $parent/ 3>&1 | grep -v "////BAD CONTENT////")
	# add a newline between folder and folder
	hash_dir_dups+="
	"
done

# keep only the entries with a duplicate hash
hash_dups=$(sort <<< $hash_dir_dups| uniq -D -w 32 )

#######################################################
############## print in a nice format #################

if [[ $hash_dups ]]; then
	# take only the last two fields of the strings and add 
	# info about the size of the folders
	hash_size_dups=$(while read t t t hash ddir; do
		# in presence of empty dirs, the ddir can be empty, I am not sure why...
		if [ -n "$ddir" ]; then 
			# check if the second argument is a number, if so,
			# use it as minimum folder size
			# https://stackoverflow.com/a/808740/5033401
			if [ -n "$2" ] && [ "$2" -eq "$2" ] 2>/dev/null; then
				size_dir=$(du -s -t $2 "$ddir")
				# if the folder is smaller than $2, do not print anything
				if [ -n "$size_dir" ]; then
					echo $hash $size_dir
				fi
			else
				echo $hash $(du -s "$ddir")
			fi
		fi; done <<< $hash_dups)
	
	# sort by the size
	hash_size_dups_sorted=$(sort -k2,2n -k1,1 <<< $hash_size_dups)
	
	# add empty lines dividers and remove the hash
	uniq --all-repeated=separate -w 16 <<< $hash_size_dups_sorted | cut -d" " -f 2-
else
	echo No duplicate folders found.
fi
