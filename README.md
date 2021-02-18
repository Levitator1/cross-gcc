Cross GCC Notes and Scripts
===========================

A simple guide on how to build a gcc cross-compiler targeting another existing system, potentially having a different architecture, and providing
its own libc. The example provided is for compiling from an x86_64 host system and targeting a Raspberry Pi Zero W running Raspbian, but
it should work for other systems as long as you know the target triplet. In this case it was surprisingly necessary to specify
hardware floating-point for the target because apparently that alters the ABI or the binary format. I think it would have been
reasonable to expect that a software-float binary should run fine despite the presence of the vector unit on the Zero, but
that doesn't seem to be the case. Maybe there is some clash between the software implementation and stubs used to calculate
on hardware. Who knows.

Anyway, this method expects you to have some means of acquiring headers and libraries for your target system to construct a sysroot. Probably the
simplest way to do that is to install (via apt-get or other package manager, etc.) all of the libraries and headers you need on an example of the target
system. Now you have a target filesystem tree containing a live installation of libc and other libraries, if you wish,
like GTK and so forth. There are two scripts provided to facilitate copying the relevant sysroot files from a live system. 

Note that I simply chose the latest version of each dependency package which was available at the time, and found this particular
configuration to work. There's probably any number of other dependency combinations that will also work.

# Step 0: Clone the project and create a working directory
	git clone https://github.com/Levitator1/cross-gcc.git
	mkdir cross-gcc-build
	cd cross-gcc-build

# Step 1: Build a target binutils:

	tar -xvf ~/Downloads/binutils-2.36.1.tar.xz
	mkdir build-binutils
	cd build-binutils
	../binutils-2.36.1/configure --prefix=$HOME/arm-tools --target=arm-linux-gnueabihf --program-suffix=-arm-linux-gnueabihf
	make -j `nproc`
	make install

"--prefix" is a common autconf option which allows you to specify a directory tree into which to perform the install. Usually this is implicitly "/"
for a system-wide install. In our case, we install local to the current user. You can thus point the makefile's install target at $HOME/arm-tools, and then add $HOME/arm-tools to your PATH environment variable, and then call programs installed there
as if they were installed normally. Assuming you use bash, see the bash documentation to see how to ensure that PATH gets updated upon shell initialization.
A command like this should suffice:

	PATH=$HOME/arm-tools:$HOME

The string "arm-linux-gnueabihf" is called a "triplet" in GNU parlance and is used to specify a particular system environment.
Here is some documentation on what these triplets mean: https://www.gnu.org/savannah-checkouts/gnu/autoconf/manual/autoconf-2.70/autoconf.html 
In our case, we are building for an existing system, so we copy the triplet which that system uses and specify it as our cross-compiler's target
system. To ask the target system what its GNU triplet is, do:

	gcc -dumpmachine

- "arm": is the target architecture. The Raspberry Pi Zero uses a processor running the armv6 instruction set, so we specify "arm". 
	Other examples of valid arch strings are "i386" for the 32-bit PC, or "x86_64" for 64-bit PCs

- "linux": is the system vendor. I'm not sure what the exact implications are, but this is the correct string for
	specifying Debian or Raspbian, and probably most proper Linux distributions except for stuff such as Android, which is its own thing

- "gnu": I guess this specifies the binary environment, and it influences things like the file format, and whether you get COFF or ELF, or some other
	system-specific binary format. It can be other things like "mingw64" or "cygwin".

- "eabi": This is an embedded version of the ABI. An ABI is the set of conventions used in implementing software interfaces at the machine code level.
		EABI just means that it's a version of the ABI which is optimized for small embedded systems, which is what the Pi Zero is.

- "hf": This means "hard float". The Pi Zero has a hardware vector unit which serves as a hardware floating point unit. The GCC build script does not
	know what "hf" means, so it is necessary to specify additionally, to use hard float. This is explained in Step 6.

You can consult the contents of "config.sub" in an autoconf source tree to see examples of supported triplet elements. Most GNU packages use
autoconf as their build system. Again, though, we are targeting an existing system, so we will just dumbly copy whatever the target's native
compiler was built with.

# Step 2: Build libgmp

	cd ..
	tar -xvf ~/Downloads/gmp-6.2.1.tar.lz
	mkdir build-gmp
	cd build-gmp
	../gmp-6.2.1/configure --prefix=$HOME/arm-tools --build=nehalem-pc-linux-gnu
	make -j `nproc`
	make install

Here, --build refers to the host system on which the cross-compiler will run. Normally, I would say "x86_64-linux-gnu" here because it is the
general architecture for ordinary 64-bit amd64 PCs. However, I found that the build script for gmp recognizes my sub-architecture with more specificity than usual.
It notices that I am running a Nehalem-series processor, which is probably valid for most 64-bit PCs built less than a decade ago. This enables optimizations.
If you are not sure what to use, then you can use the "arch" command, and that will tell you the architecture for which your system was built, though not necessarily
the most specific architecture optimized for your hardware. i386 and moreso x86_64 are probably by far the most common. Also, it seems that not all "configure" scripts
recognize the optimized architecture strings. Arch strings are kind of magical, and you can let "configure" detect them on its own by ommitting settings, and then
you can reconfigure with correct settings, or you can dig through "config.sub" to find special options.

We don't specify a target here, because this library is for use on the build host and it is target agnostic. It's just a math library gcc needs.

# Step 3: build libmpfr
	cd ..
	tar -xvf ~/Downloads/mpfr-4.1.0.tar.xz	
	mkdir build-mpfr
	cd build-mpfr
	../mpfr-4.1.0/configure --prefix=$HOME/arm-tools --build=x86_64-pc-linux-gnu
	make -j `nproc`
	make install

# Step 4: build libmpc
	cd ..
	tar -xvf ~/Downloads/mpc-1.2.0
	mkdir build-mpc
	cd build-mpc
	../mpc-1.2.0/configure --prefix=$HOME/arm-tools --build=x86_64-pc-linux-gnu --with-mpfr=$HOME/arm-tools --with-gmp=$HOME/arm-tools
	make -j `nproc`
	make install

# Step 5: Populate sysroot via rsync/ssh copying from a live example of the target system
	cd ..
	../gcc-cross/sync.sh sshuser@targetmachine ~/arm-sysroot
	../gcc-cross/fix_links.sh ~/arm-sysroot

We ssh over to a live target machine and pull /lib, /usr/lib, and /usr/include so that the cross compiler sees the same target libraries and
headers as if it were installed on the target system. /lib/modules is excluded to try to save some time and space.

Then, we run fix_links.sh, which finds each symbolic link in the sysroot, and if it is absolute, and if there exists a corresponding valid target file
in the local tree, then it is relinked to that file (instead of its absolute location from the remote system), and it is made relative so that the
tree can be moved around without breaking the links. So, for example,

	/home/you/arm-sysroot/usr/lib/libwhatever.so -> /usr/lib/whatever.6.so (broken link or wrong file)
		becomes
	/home/you/arm_sysroot/usr/lib/libwhatever.so -> whatever.6.so (valid)
	

# Step 6: build gcc
	cd ..
	tar -xvf ~/Downloads/
	mkdir build-gcc
	cd build-gcc
	../gcc/configure --prefix=$HOME/arm-tools --host=x86_64-linux-gnu --target=arm-linux-gnueabihf --with-gmp=$HOME/arm-tools --with-mpc=$HOME/arm-tools --with-mpfr=$HOME/arm-tools --enable-languages=c,c++ --with-sysroot=$HOME/arm-sysroot/root --libdir=$HOME/arm-tools/usr/lib/arm-linux-gnueabihf --with-headers=$HOME/arm-tools/usr/include/arm-linux-gnueabihf:$HOME/arm-sysroot/root/usr/include --with-cpu=arm1176jzf-s --with-float=hard
	make -j `nproc` all-gcc
	make install


The host can be automatically detected by "configure", however I'm not sure that the build script will correctly infer a cross-compiler build unless you specify --host.
So, if you are unsure what --host triplet to use, then you can, again, consult "gcc -dumpmachine", but this time on the local machine.

## ARM-Specific Notes
Note "--with-cpu" and "--with-float". These switches fix the provided settings into the cross-compiler as defaults. These are necessary to compile for the Raspberry Pi Zero (W).
The CPU setting probably specifies numerous details and features, mostly for the benefit of the assembler, which are specific to the processor core used in the chip which
is actually a Broadcom product. Internally, it uses a processing unit from ARM called an arm1176jzf-s, which in turn is based on the armv6 instruction set. This cpu switch
adds specific details about which particular arm processor to build for. We specify hardware floating point because this processor  has a vector unit, and it seems as though
the software implementation is not compatible with the hardware implementation, or perhaps not interoperable with other binaries linked for hard float. Incidentally, Raspbian is little-endian, but it seems as though that gets accounted for somewhere,
perhaps by default.

# Step 7: build the gcc support library

Note that we skip building libc because it is an invariant on the target system. We do not want to build our own libc only to wind up with a subtly different version
which is subtly incompatible. The gcc support library provides a bridge between the executables the compiler produces and libc. It is mostly in charge of bootstrapping
libc and shutting it down when the program exits. This includes implicitly linked runtime artifacts such as crt1.o and crti.o, etc.

	make -j `nproc` all-target-libgcc
	make install-target-libgcc

# Step 8: build libstdc++

Among other potential reasons, the compiler may offer a different feature set than the system's native compiler (differing versions of standards conformance, etc),
so it needs its own C++ standard library. The library seems to be included in the compiler source, so they seem to be tightly coupled. I think I would use a compiler
only with the exact same build's corresponding libstdc++.

	make -j `nproc`
	make install

# Test!

Now, compile something with "arm-linux-gnueabihf-g++" (or use whatever target triplet is appropriate). Use "-static-libstdc++" so as to avoid initially having to worry
about the dynamic linker locating the new C++ runtime. Copy the resulting executable to the target machine, and it should run. If it doesn't, you can try compiling a C
program instead, as that will eliminate the C++ library as a variable. If you get "invalid instruction", then you probably got one of the CPU paramaeters wrong and 
generated invalid code for the hardware.
