#!/bin/sh

# Since musl's s390x port only supports static linking for now, all of these below softwares are statically linked too.
# Dynamic linking will be supported as soon as upstream developers provide one.

# TODO
# 1. Test with APKLUA (including cross-compiling lua, and modifying apk-tools/src/Makefile
# 2. To resume the script at certain steps, do something like $ touch extracted or $ touch built


set -ex
if [ "$#" -ne 2 ]; then
	echo "Usage		: deps.sh CROSS_BASE_DIR CROSS_TRIPLET"
	echo "Example	: deps.sh /opt/cross/toolchains s390x-linux-musl"
	exit 0
else
	CROSS_BASE_DIR="$1"
	CROSS_TRIPLET="$2"
fi
CROSS_PREFIX="$CROSS_BASE_DIR/bin/$CROSS_TRIPLET-"

###############################################################################
BUSYBOX_VER="1_25_stable"
APK_TOOLS_VER="2.6.7"
LIBFETCH_VER="2.33"
OPENSSL_VER="1.0.2h"
ZLIB_VER="1.2.8"
LUAAPK="no"
#LUAAPK="yes"
if [ "$LUAAPK" = "yes" ]; then
	LUA_VER="5.2.4"
fi

BASE=$PWD
SRC=$BASE/src
BUILD=$BASE/build
mkdir -p $SRC $SRC/deps $SRC/tarballs
mkdir -p $BUILD/busybox-$BUSYBOX_VER
mkdir -p $BUILD/apk-tools-$APK_TOOLS_VER
mkdir -p $BUILD/deps/libfetch-$LIBFETCH_VER/lib
mkdir -p $BUILD/deps/libfetch-$LIBFETCH_VER/include
mkdir -p $BUILD/deps/openssl-$OPENSSL_VER
mkdir -p $BUILD/deps/zlib-$ZLIB_VER
if [ "$LUAAPK" = "yes" ]; then
	mkdir -p $BUILD/deps/lua-$LUA_VER
fi


# 1.	busybox
cd $SRC
git clone git://git.busybox.net/busybox -b $BUSYBOX_VER busybox-$BUSYBOX_VER
cd busybox-$BUSYBOX_VER
make ARCH=s390x defconfig
sed -e 's@.*CONFIG_CROSS_COMPILER_PREFIX.*@'CONFIG_CROSS_COMPILER_PREFIX=\""$CROSS_PREFIX"\"'@' -i .config
sed -e 's@.*CONFIG_PREFIX.*@'CONFIG_PREFIX=\""$BUILD/busybox-$BUSYBOX_VER"\"'@' -i .config
sed -e 's/.*CONFIG_STATIC.*/CONFIG_STATIC=y/' -i .config
make ARCH=s390x
make install


# 2.	apk-tools dependencies

# 2.1	deps/openssl
wget -c https://www.openssl.org/source/openssl-$OPENSSL_VER.tar.gz -O $SRC/tarballs/openssl-$OPENSSL_VER.tar.gz
cd $SRC/deps
gzip -dc $SRC/tarballs/openssl-$OPENSSL_VER.tar.gz | tar xvf -
cd $SRC/deps/openssl-$OPENSSL_VER
./Configure linux64-s390x --openssldir=$BUILD/deps/openssl-$OPENSSL_VER \
	--cross-compile-prefix=$CROSS_PREFIX -L$CROSS_BASE_DIR/$CROSS_TRIPLET/lib \
	no-ssl2 no-ssl3 no-shared no-zlib enable-unit-test enable-tlsext
make depend
make
make install

# 2.2	deps/zlib
wget -c http://zlib.net/zlib-$ZLIB_VER.tar.gz -O $SRC/tarballs/zlib-$ZLIB_VER.tar.gz
cd $SRC/deps
gzip -dc $SRC/tarballs/zlib-$ZLIB_VER.tar.gz | tar xvf -
cd $SRC/deps/zlib-$ZLIB_VER
CROSS_PREFIX=$CROSS_PREFIX CC=${CROSS_PREFIX}gcc ./configure --prefix=$BUILD/deps/zlib-$ZLIB_VER --static
make static
make install

# 2.3	deps/libfetch
wget -c https://sources.archlinux.org/other/libfetch/libfetch-$LIBFETCH_VER.tar.gz -O $SRC/tarballs/libfetch-$LIBFETCH_VER.tar.gz
cd $SRC/deps
gzip -dc $SRC/tarballs/libfetch-$LIBFETCH_VER.tar.gz | tar xvf -
cd libfetch-$LIBFETCH_VER
mv Makefile Makefile.libfetch.origin
wget -c "http://git.alpinelinux.org/cgit/aports/plain/main/libfetch/Makefile?h=3.3-stable" -O Makefile.alpine
cp Makefile.alpine Makefile
sed -e 's@.*prefix =.*@prefix = '"$BUILD/deps/libfetch-$LIBFETCH_VER"'@' -i Makefile
sed -e 's@.*CFLAGS.*-DWITH_SSL.*@CFLAGS+='-I"$BUILD/deps/openssl-$OPENSSL_VER/include -DWITH_SSL"'@' -i Makefile
sed -e 's@.*LDFLAGS.*-lssl.*-lcrypto.*@LDLAGS:='-L"$BUILD/deps/openssl-$OPENSSL_VER/lib -lssl -lcrypto"'@' -i Makefile
sed -e 's@.*CC =.*@CC = '"$CROSS_PREFIX"gcc'@' -i Makefile
sed -e 's@.*LD =.*@LD = '"$CROSS_PREFIX"gcc'@' -i Makefile
sed -e 's@.*AR =.*@AR = '"$CROSS_PREFIX"ar'@' -i Makefile
sed -e 's@.*RANLIB =.*@RANLIB = '"$CROSS_PREFIX"ranlib'@' -i Makefile
make libfetch.a
cp -p libfetch.a $BUILD/deps/libfetch-$LIBFETCH_VER/lib/
cp -p fetch.h $BUILD/deps/libfetch-$LIBFETCH_VER/include/

# 2.4	deps/lua5.2
if [ "$LUAAPK" = "yes" ]; then
	echo
fi

# 2.5	pkg-config workarounds
export PKG_CONFIG_PATH=$BUILD/deps/zlib-$ZLIB_VER/lib/pkgconfig:$BUILD/deps/openssl-$OPENSSL_VER/lib/pkgconfig:$PKG_CONFIG_PATH
if [ "$LUAAPK" = "yes" ]; then
	export PKG_CONFIG_PATH=$BUILD/deps/lua-$LUA_VER/lib::$PKG_CONFIG_PATH
fi
echo export PKG_CONFIG_PATH=$PKG_CONFIG_PATH >> $HOME/.profile


# 3.	apk-tools
wget -c http://git.alpinelinux.org/cgit/apk-tools/snapshot/apk-tools-$APK_TOOLS_VER.tar.bz2 -O $SRC/tarballs/apk-tools-$APK_TOOLS_VER.tar.bz2
cd $SRC
bzip2 -dc $SRC/tarballs/apk-tools-$APK_TOOLS_VER.tar.bz2 | tar xvf -
cd apk-tools-$APK_TOOLS_VER

sed -i -e 's:-Werror::' Make.rules
sed -e 's@.*CROSS_COMPILE.*?=.*@CROSS_COMPILE='" $CROSS_PREFIX"'@' -i Make.rules
sed -e 's@.*CFLAGS.*-g.*-O2.*@CFLAGS='" -g -O2 -I$BUILD/deps/libfetch-$LIBFETCH_VER/include"'@' -i Make.rules

sed -e 's@.*DESTDIR.*:=.*@DESTDIR='" $BUILD/apk-tools-$APK_TOOLS_VER"'@' -i Makefile
echo "" >> Makefile
echo "#DEBUG : run \$ make print-CC" >> Makefile
echo "print-%  : ; @echo \$* = \$(\$*)" >> Makefile

if [ "$LUAAPK" = "yes" ]; then
	sed -e 's@.*LUAAPK.*?=.*@LUAAPK=yes@' -i src/Makefile
	sed -e 's@.*LUA_LIBDIR.*usr.*lua.*@LUA_LIBDIR='" $BUILD/deps/lua-$LUA_VER/lib"'@' -i src/Makefile	
else
	sed -e 's@.*LUAAPK.*?=.*@LUAAPK=@' -i src/Makefile
fi

export myslash="\\\\"
sed -e 's@.*LIBS_apk.static.*-Wl.*@LIBS_apk.static='"$CROSS_BASE_DIR/$CROSS_TRIPLET/lib/libdl.a"'@' -i src/Makefile
sed -e 's@.*LIBS.*libfetch.a.*@LIBS:='" $BUILD/deps/libfetch-$LIBFETCH_VER/lib/libfetch.a $myslash"'@' -i src/Makefile
sed -e 's@.*PKG_CONFIG.*libs.*@'"    $BUILD/deps/zlib-$ZLIB_VER/lib/libz.a $BUILD/deps/openssl-$OPENSSL_VER/lib/libssl.a $myslash"'@' -i src/Makefile
sed -e 's@.*-Wl.*--no-as-needed.*@'"    $BUILD/deps/openssl-$OPENSSL_VER/lib/libcrypto.a"'@' -i src/Makefile
unset myslash

cp $BASE/apk-tools-s390x.patch $SRC/apk-tools-$APK_TOOLS_VER/
patch -p1 < apk-tools-s390x.patch

make VERBOSE=1 static
make install

