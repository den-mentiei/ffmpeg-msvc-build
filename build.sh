# exit immediately upon error
set -e

function make_zip() {
	local folder
	local "${@}"
	find "$folder"  # prints paths of all files to be zipped
	7z a -tzip -r "$folder.zip" $folder
}

get_git_date() {
	local folder
	local "${@}"
	pushd "$folder" > /dev/null
	git show -s --format=%ci HEAD | sed 's/\([0-9]\{4\}\)-\([0-9][0-9]\)-\([0-9][0-9]\).*/\1\2\3/'
	popd > /dev/null
}

get_git_hash() {
	local folder
	local "${@}"
	pushd "$folder" > /dev/null
	git show -s --format=%h HEAD
	popd > /dev/null
}

get_toolset() {
	local visual_studio
	local "${@}"
	case "$1" in
		Visual\ Studio\ 2013)
			echo -n "v120"
			;;
		Visual\ Studio\ 2015)
			echo -n "v140"
			;;
		Visual\ Studio\ 2017)
			echo -n "v141"
			;;
		*)
			return 1
	esac
}

# RUNTIME_LIBRARY CONFIGURATION
cflags_runtime() {
	echo -n "-$1" | tr '[:lower:]' '[:upper:]'
	case "$2" in
		Release)
			echo ""
			;;
		Debug)
			echo "d"
			;;
		*)
			return 1
	esac
}

# BASE LICENSE VISUAL_STUDIO LINKAGE RUNTIME_LIBRARY CONFIGURATION PLATFORM
target_id() {
	local toolset_=$(get_toolset visual_studio="$3")
	local date_=$(get_git_date folder="$1")
	local hash_=$(get_git_hash folder="$1")
	echo "$1-${date_}-${hash_}-$2-${toolset_}-$4-$5-$6-$7" | tr '[:upper:]' '[:lower:]'
}

# LICENSE
license_file() {
	case "$1" in
		LGPL21)
			echo "COPYING.LGPLv2.1"
			;;
		LGPL3)
			echo "COPYING.LGPLv3"
			;;
		GPL2)
			echo "COPYING.GPLv2"
			;;
		GPL3)
			echo "COPYING.GPLv3"
			;;
		*)
			return 1
	esac
}

# LICENSE
ffmpeg_options_license() {
	case "$1" in
		LGPL21)
			;;
		LGPL3)
			echo "--enable-version3"
			;;
		GPL2)
			echo "--enable-gpl --enable-libx264"
			;;
		GPL3)
			echo "--enable-gpl --enable-version3 --enable-libx264"
			;;
		*)
			return 1
	esac
}

# LINKAGE
ffmpeg_options_linkage() {
	case "$1" in
		shared)
			echo "--disable-static --enable-shared"
			;;
		static)
			echo "--enable-static --disable-shared"
			;;
		*)
			return 1
	esac
}

# RUNTIME_LIBRARY CONFIGURATION
ffmpeg_options_runtime() {
	cflags=`cflags_runtime $1 $2`
	echo "--extra-cflags=$cflags --extra-cxxflags=$cflags"
}

# CONFIGURATION
ffmpeg_options_debug() {
	case "$1" in
		Release)
			echo "--disable-debug"
			;;
		Debug)
			echo ""
			;;
		*)
			return 1
	esac
}

# PREFIX LICENSE LINKAGE RUNTIME_LIBRARY CONFIGURATION
ffmpeg_options () {
	echo -n "--disable-doc --enable-runtime-cpudetect"
	echo -n " --prefix=$1"
	echo -n " $(ffmpeg_options_license $2)"
	echo -n " $(ffmpeg_options_linkage $3)"
	echo -n " $(ffmpeg_options_runtime $4 $5)"
	echo -n " $(ffmpeg_options_debug $5)"
}

# assumes we are in the ffmpeg folder
# PREFIX LICENSE LINKAGE RUNTIME_LIBRARY CONFIGURATION
function build_ffmpeg() {
	echo "==============================================================================="
	echo "build_ffmpeg"
	echo "==============================================================================="
	echo "PREFIX=$1"
	echo "LICENSE=$2"
	echo "LINKAGE=$3"
	echo "RUNTIME_LIBRARY=$4"
	echo "CONFIGURATION=$5"
	echo "-------------------------------------------------------------------------------"
	echo "PATH=$PATH"
	echo "INCLUDE=$INCLUDE"
	echo "LIB=$LIB"
	echo "LIBPATH=$LIBPATH"
	echo "CL=$CL"
	echo "_CL_=$_CL_"
	echo "-------------------------------------------------------------------------------"

	# find absolute path for prefix
	local abs1=$(readlink -f $1)

	# install license file
	mkdir -p "$abs1/share/doc/ffmpeg"
	cp "ffmpeg/$(license_file $2)" "$abs1/share/doc/ffmpeg/license.txt"

	# run configure and save output (lists all enabled features and mentions license at the end)
	pushd ffmpeg
	# reduce clashing windows.h imports ("near", "Rectangle")
	sed -i 's/#include <windows.h>/#define Rectangle WindowsRectangle\n#include <windows.h>\n#undef Rectangle\n#undef near/' compat/atomics/win32/stdatomic.h
	# temporary fix for C99 syntax error on msvc, patch already on mailing list
	sed -i 's/MXFPackage packages\[2\] = {};/MXFPackage packages\[2\] = {{0}};/' libavformat/mxfenc.c
	./configure --toolchain=msvc $(ffmpeg_options $abs1 $2 $3 $4 $5) \
		> "$abs1/share/doc/ffmpeg/configure.txt" || (tail -30 config.log && exit 1)
	cat "$abs1/share/doc/ffmpeg/configure.txt"
	#tail -30 config.log  # for debugging
	make
	make install
	# fix extension of static libraries
	if [ "$3" = "static" ]
	then
		pushd "$abs1/lib/"
		for file in *.a; do mv "$file" "${file/.a/.lib}"; done
		popd
	fi
	# move import libraries to lib folder
	if [ "$3" = "shared" ]
	then
		pushd "$abs1/bin/"
		for file in *.lib; do mv "$file" ../lib/; done
		popd
	fi
	popd
}

# PREFIX RUNTIME_LIBRARY CONFIGURATION
x264_options() {
	echo -n " --prefix=$1"
	echo -n " --disable-cli"
	echo -n " --enable-static"
	echo -n " --extra-cflags=$(cflags_runtime $2 $3)"
}

# PREFIX RUNTIME_LIBRARY CONFIGURATION
function build_x264() {
	# find absolute path for prefix
	local abs1=$(readlink -f $1)

	pushd x264
	# use latest config.guess to ensure that we can detect msys2
	curl "http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD" > config.guess
	# hotpatch configure script so we get the right compiler, compiler_style, and compiler flags
	sed -i 's/host_os = mingw/host_os = msys/' configure
	CC=cl ./configure $(x264_options $abs1 $2 $3) || (tail -30 config.log && exit 1)
	make
	make install
	INCLUDE="$INCLUDE;$(cygpath -w $abs1/include)"
	LIB="$LIB;$(cygpath -w $abs1/lib)"
	popd
}

function make_all() {
	local license
	local visual_studio
	local linkage
	local runtime
	local configuration
	local platform
	local "${@}"
	# ensure link.exe is the one from msvc
	mv /usr/bin/link /usr/bin/link1
	which link
	# ensure cl.exe can be called
	which cl
	cl
	if [ "$license" = "GPL2" ] || [ "$license" = "GPL3" ]
	then
		# LICENSE VISUAL_STUDIO LINKAGE RUNTIME_LIBRARY CONFIGURATION PLATFORM
		local x264_prefix=$(target_id "x264" "GPL2" "$visual_studio" "static" "$runtime" "$configuration" "$platform")
		# PREFIX RUNTIME_LIBRARY
		#build_x264 "$x264_prefix" "$runtime" "$configuration"
	fi
	# LICENSE VISUAL_STUDIO LINKAGE RUNTIME_LIBRARY CONFIGURATION PLATFORM
	local ffmpeg_prefix=$(target_id "ffmpeg" "$license" "$visual_studio" "$linkage" "$runtime" "$configuration" "$platform")
	# PREFIX LICENSE LINKAGE RUNTIME_LIBRARY CONFIGURATION
	#build_ffmpeg "$ffmpeg_prefix" "$license" "$linkage" "$runtime" "$configuration"
	mkdir "$ffmpeg_prefix" # TODO remove
	make_zip folder="$ffmpeg_prefix"
	mv /usr/bin/link1 /usr/bin/link
}

set -x
# bash starts in msys home folder, so first go to project folder
cd $(cygpath "$APPVEYOR_BUILD_FOLDER")
make_all \
	license="$LICENSE" \
	visual_studio="$APPVEYOR_BUILD_WORKER_IMAGE" \
	linkage="$LINKAGE" \
	runtime="$RUNTIME_LIBRARY" \
	configuration="$Configuration" \
	platform="$Platform"