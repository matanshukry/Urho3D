#
# Copyright (c) 2008-2013 the Urho3D project.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

# Define helpers
msg() {
    echo -e "\n$1\n================================================================================"
}

post_cmake() {
    # Check if xmlstarlet software package is available for fixing the generated Eclipse project setting
    if [ $HAS_XMLSTARLET ]; then
        # Common fixes for all builds
        #
        # Remove build type from project name
        # Replace deprecated GNU gmake Error Parser with newer version (6.0 -> 7.0)
        #
        xmlstarlet ed -P -L \
            -u "/projectDescription/name/text()" -x "concat(substring-before(., '-Release'), substring-before(., '-Debug'), substring-before(., '-RelWithDebInfo'))" \
            -u "/projectDescription/buildSpec/buildCommand/arguments/dictionary/value[../key/text() = 'org.eclipse.cdt.core.errorOutputParser']" -x "concat('org.eclipse.cdt.core.GmakeErrorParser', substring-after(., 'org.eclipse.cdt.core.MakeErrorParser'))" \
            $1/.project

        # Build-specific fixes
        if [ $1 == "android-Build" ]; then
            # For Android build, add the Android and Java nature to the project setting as it would be done by Eclipse during project import
            # This fix avoids the step to reimport the project everytime the Eclipse project setting is regenerated by cmake_gcc.sh invocation
            echo -- Add Android and Java nature to Eclipse project setting files in $( pwd )/$1

            #
            # Add natures (Android nature must be inserted as first nature)
            #
            xmlstarlet ed -P -L \
                -i "/projectDescription/natures/nature[1]" -t elem -n nature -v "com.android.ide.eclipse.adt.AndroidNature" \
                -s "/projectDescription/natures" -t elem -n nature -v "org.eclipse.jdt.core.javanature" \
                $1/.project
            #
            # Add build commands
            #
            for c in com.android.ide.eclipse.adt.ResourceManagerBuilder com.android.ide.eclipse.adt.PreCompilerBuilder org.eclipse.jdt.core.javabuilder com.android.ide.eclipse.adt.ApkBuilder; do
                xmlstarlet ed -P -L \
                    -s "/projectDescription/buildSpec" -t elem -n buildCommandNew -v "" \
                    -s "/projectDescription/buildSpec/buildCommandNew" -t elem -n name -v $c \
                    -s "/projectDescription/buildSpec/buildCommandNew" -t elem -n arguments -v "" \
                    -r "/projectDescription/buildSpec/buildCommandNew" -v "buildCommand" \
                    $1/.project
            done

        elif [ $1 == "raspi-Build" ]; then
            # For Raspberry Pi build, do nothing
            :

        else
            # For native build, move the Eclipse project setting files back to Source folder to fix source code versioning
            echo -- Eclipse project setting files have been relocated to: $( pwd )/Source
            for f in .project .cproject; do mv $1/$f Source; done

            #
            # Replace [Source directory] linked resource to [Build] instead
            # Modify build argument to first change directory to Build folder
            #
            xmlstarlet ed -P -L \
                -u "/projectDescription/linkedResources/link/name/text()[. = '[Source directory]']" -v "[Build]" \
                -u "/projectDescription/linkedResources/link/location[../name/text() = '[Build]']" -v "$( pwd )/$1" \
                -u "/projectDescription/buildSpec/buildCommand/arguments/dictionary/value[../key/text() = 'org.eclipse.cdt.make.core.build.arguments']" -x "concat('-C ../$1 ', .)" \
                Source/.project
            #
            # Fix source path entry to Source folder and modify its filter condition
            # Fix output path entry to [Build] linked resource and modify its filter condition
            #
            xmlstarlet ed -P -L \
                -u "/cproject/storageModule/cconfiguration/storageModule/pathentry[@kind = 'src']/@path" -v "" \
                -s "/cproject/storageModule/cconfiguration/storageModule/pathentry[@kind = 'src']" -t attr -n "excluding" -v "[Subprojects]/|[Targets]/" \
                -u "/cproject/storageModule/cconfiguration/storageModule/pathentry[@kind = 'out']/@path" -v "[Build]" \
                -u "/cproject/storageModule/cconfiguration/storageModule/pathentry[@kind = 'out']/@excluding" -x "substring-after(., '[Source directory]/|')" \
                Source/.cproject
        fi
    fi
}

# Ensure we are in project root directory
cd $( dirname $0 )
SOURCE=`pwd`/Source

# Create out-of-source build directory
cmake -E make_directory Build
[ $RASPI_TOOL ] && cmake -E make_directory raspi-Build
[ $ANDROID_NDK ] && cmake -E make_directory android-Build

# Add support for Eclipse IDE
IFS=#
GENERATOR="Unix Makefiles"
[[ $1 =~ ^eclipse$ ]] && GENERATOR="Eclipse CDT4 - Unix Makefiles" && shift && xmlstarlet --version >/dev/null 2>&1 && HAS_XMLSTARLET=1

# Add support for both native and cross-compiling build for Raspberry Pi
[[ $( uname -m ) =~ ^armv6 ]] && PLATFORM="-DRASPI=1"

# Create project with the respective CMake generators
OPT=
msg "Native build" && cmake -E chdir Build cmake $OPT -G $GENERATOR $PLATFORM $@ $SOURCE && post_cmake Build
[ $RASPI_TOOL ] && msg "Raspberry Pi build" && cmake -E chdir raspi-Build cmake $OPT -G $GENERATOR -DRASPI=1 -DCMAKE_TOOLCHAIN_FILE=$SOURCE/CMake/Toolchains/raspberrypi.toolchain.cmake $@ $SOURCE && post_cmake raspi-Build
[ $ANDROID_NDK ] && msg "Android build" && cmake -E chdir android-Build cmake $OPT -G $GENERATOR -DANDROID=1 -DCMAKE_TOOLCHAIN_FILE=$SOURCE/CMake/Toolchains/android.toolchain.cmake -DLIBRARY_OUTPUT_PATH_ROOT=. $@ $SOURCE && post_cmake android-Build
unset IFS

# Assume GCC user uses OpenGL, comment out below sed if this is not true
sed 's/OpenGL/Direct3D9/g' Docs/Doxyfile.in >Doxyfile

# Create symbolic links in the build directories
if [ $ANDROID_NDK ]; then
    for dir in CoreData Data; do
        cmake -E create_symlink ../../../Bin/$dir Source/Android/assets/$dir
    done
    for f in AndroidManifest.xml build.xml project.properties src res assets; do
        cmake -E create_symlink ../Source/Android/$f android-Build/$f
    done
fi

# vi: set ts=4 sw=4 expandtab:
