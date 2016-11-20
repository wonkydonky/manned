#!/bin/sh

# The order of inserting the files into the tar is not fully deterministic this
# way.  The tests will fail quite badly if a hardlink is considered the
# "original" version.


# simpletest.tar.gz

mkdir simple
echo Hi >simple/file
touch -d '2016-11-20 08:44:02+01:00' simple/file
ln -s file simple/link
ln simple/file simple/hardlink
mkfifo simple/fifo
badfn=`echo 'Héllö.txt' | iconv -t ISO-8859-1`
touch $badfn
tar -czf simpletest.tar.gz simple $badfn
rm -rf $badfn simple



# rawtest.gz.xz.bzip2

echo "File contents!" | gzip | xz | bzip2 >rawtest.gz.xz.bzip2


# testarchive.tar.xz

mkdir man
cd man

mkdir man1
mkdir man3
mkdir man6
ln -s man3 mans

echo 'Hello World' >man3/helloworld.3
echo 'Not a very interesting file' >notinteresting
echo 'Potentially interesting file' >possiblyinteresting

ln man3/helloworld.3 man6/hardlink.6

ln -s ../man3/helloworld.3 man1/symlinkbefore.1
ln -s ../man3/helloworld.3 man6/symlinkafter.6

ln -s notadir/../../man3/helloworld.3 man1/badsymlink1.1
ln -s man3/helloworld.3 man1/badsymlink2.1
ln -s ../man3/helloworld.3/. man1/badsymlink3.1
ln -s ../man3/helloworld.3/../helloworld.3 man1/badsymlink4.1
ln -s ../man1/symlinkbefore.1/../../man1/helloworld.3 man1/badsymlink5.1

ln -s symlinkbefore.1 man1/doublesymlink1.1
ln -s ../mans/helloworld.3 man1/doublesymlink2.1
ln -s ../mans/../man1/symlinkbefore.1 man1/triplesymlink.1
ln -s infinitesymlink.1 man1/infinitesymlink.1

ln -s ../possiblyinteresting man3/needreread.3
ln -s ../possiblyinteresting man6/needreread.6

cd ..
rm -f testarchive.tar
tar -cf testarchive.tar man/
rm -r man/

mkdir man
echo 'Overwritten file' >man/possiblyinteresting
tar -rf testarchive.tar man/
rm -r man/

rm -f testarchive.tar.xz
xz testarchive.tar
