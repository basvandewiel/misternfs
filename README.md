# misternfs
NFS support for MiSTer. This repository contains supporting scripts for use once the
MiSTer's Linux kernel gets NFS client support compiled in.

The script is based off the CIFS scripts already present in the project and modifications
as made by misterfpga.org user RealLarry.

The purpose of this repository is to eventually disappear so that the script can be adopted
into the mainline MiSTer project and live on there.

## Installing the script

Place the ```nfs_mount.sh``` and ```nfs_unmount.sh``` scripts inside your MiSTer's ```/media/fat/Scripts``` 
directory. You can run it from there through the OSD or from a (remote) Linux shell as you see fit.

## What it does: ..here be dragons

These two scripts do what they say on the box: mount and unmount your NFS-provided network storage. When
the sanity checks work out, the actual mount works as follows.

  1. The script mounts your ```SERVER_PATH``` onto ```/tmp/nfs_mount``` on your MiSTer.
  2. It then looks for directories inside your ```/tmp/nfs_mount``` and compares them to the directories
     you have in ```/media/fat```.
  3. If it finds directories that appear in both location, the NFS-version gets mounted on top of the
     existing directory in ```/media/fat```.

### Wait.. what!?

Let's say you have a directory on your NAS named ```/storage/MiSTer``` that you export over NFS, then
that will end up mounted at ```/tmp/nfs_mount``` on your MiSTer and that will be that if it's empty.

If you have a ```games``` directory *inside* your ```/storage/MiSTer``` on the NAS, then the script will
pick up on that. If and *only* if you *also* have an pre-existing ```/media/fat/games``` directory, the
remote version will be mounted *on top of* your existing ```/media/fat/games```.

This goes for any and all directories that appear in *both* places at the time time script runs, which is once
at system boot and/or on demand when you run it from a shell or the MiSTer's OSD.

This trick permits you to keep your cores on the SD-card by not having ```/media/fat/_Arcade``` etc. on
your NAS. If it's not found on your NAS, then the directory won't be overlaid with anything and just left
alone as-is on your SD-card.

You can use this to keep a small-ish ```/media/fat/games``` directory on your SD-card for portable gaming fun,
while having the entire history of retrogaming and a plethora of Windows 95 installations on your NAS at home
by overlaying ```/media/fat/games``` via NFS.

## Configuration

The preferred method for configuring the script is through an INI file that sits in the same
directory as the main script itself and is named ```nfs_mount.ini```. In this file you can
define a number of variables of which ```SERVER``` and ```SERVER_PATH``` are mandatory.

| Variable name  | Default   | Description |
|----------------|-----------|-------------|
| SERVER         | Undefined | DNS-name or IP-address of your NFS-server. |
| SERVER_PATH    | Undefined | The remote directory to mount onto your MiSTer. |
| SERVER_TIMEOUT | 60        | Number of seconds to wait for both IP-connectivity and the NFS-server to become reachable. |
| MOUNT_AT_BOOT  | yes       | Set to "yes" if you want this script to run at every startup of your MiSTer. |
| MOUNT_OPTIONS  | "noatime" | Client-side mount options for your NFS-mount. |
| WOL            | "no       | WakeOnLAN: set to "yes" to send a wake-up packet to your NFS-server to wake it up. |

An example for the contents of a valid INI file would be:

```
SERVER="192.168.0.4"
SERVER_PATH="/storage/mister"
MOUNT_AT_BOOT="yes"
MOUNT_OPTIONS="noatime,ro"
```

This example would try to mount the ```/storage/mister``` path from a server that lives at
IP-address ```192.168.0.4```. It'd install scripts to run at every boot and the MOUNT_OPTIONS
mount the directory as read-only (see below).

You can also modify the script itself, but that'll get clobbered when you update the script.
Using an INI file keeps the script and its configuration separate, which is good practice.

Just to be 100% clear here: you *must* define ```SERVER``` and ```SERVER_PATH``` yourself. The other
variables all have sensible defaults set.

## Troubleshooting

This script is entirely silent on the MiSTer's console. For troubleshooting, have a look at the syslog file in
```/var/log/messages```. The script logs status messages there.

## Concerning NFS: more dragons

The NFS protocol is ancient and it was conceived in the days of big-iron UNIX machines in
well-tended datacenters where grey-haired veteran geeks would carefully nurture, cultivate
and sacrifice the occasional goat to them. This is quite a different backdrop from a retro
computing appliance that simulates consumer devices which would habitually be turned off
and on again as legitimate troubleshooting steps without batting an eyelash.

### When to use NFS

Using the NFS protocol on your MiSTer allows you to use files that sit on your NAS or another
Linux/UNIX compatible device like a Raspberry Pi. The main advantage of NFS over all other options
is that it comes included with most Linux and other UNIX-like operating systems, unlike Samba for
example. NFS is also arguably more light-weight than Samba, which matters in case you're using an
old Raspberry Pi or similar board as a server. If you know and love UNIX, you'll feel more at home
with NFS than you do with Samba/CIFS.

### When not to use NFS

Don't use NFS if you don't already know what it is and have it running in your network. Really, it's
hardly worth the trouble and CIFS will service you just fine for your MiSTer needs. NFS should
be treated as an option for those who already know why they want to use it, which obviously includes
curious tinkerers. This is not a threat by any means, but do consider yourself warned.

## Potential issues

By virtue of being an old UNIX file-sharing protocol, you're exposing your MiSTer to the old world that
began with teletypes and punch cards. You'll need to be more careful with it than you'd be when using just
the plain local SD card or you'll run into issues that may seem hard to debug at first. Here's a few
pointers.

### Case sensitivity

MiSTer runs Linux, which is generally case-sensitive but not in the MiSTer's default case using just
the SD-card for storage. The SD-card is formatted using exFAT, which is case-insensitive. NFS, on the
other hand, generally has a Linux/UNIX backing store which *does* care about case. This means that on
your SD-card ```NeoGeo``` and ```NEOGEO``` are the same thing, while they're quite distinct via NFS.

Ensure that you test your update scripts etc. carefully before moving your stuff over to an NFS-based
network share.

### Mounting NFS may take a while

The ```SERVER_TIMEOUT``` value is used in two places, accumulating to a total timeout value of twice the number
of seconds you define for it. By default this means it can take up to two minutes for your MiSTer to have NFS
mounted and ready to go. These timeouts are *not blocking* to the rest of the system's startup process, so you
may get some glitchy behavior there if you have overlapping directories with differing contents. The contents
of the ```/media/fat``` hierarchy may suddenly appear different from how it after NFS gets mounted.

The mount should take hardly any time at all if your NFS-server is already up before you start your MiSTer,
but you could be in for a surprise if you're using the ```WOL``` flag for instance and your NFS-server needs
to boot up while your MiSTer proceeds to load from its SD-card. This is an advanced use case, so don't try
this if you're not comfortable with it.. or open a thread on the MiSTerFPGA.org forum and aks for guidance.


### Can't write to my network share

The MiSTer device runs everything as the ```root``` user. This is perfectly valid for an appliance
that has no concept of security contexts within its own operating system. For all intents and purposes,
the MiSTer doesn't concern itself with permissions: root can always do everything it wants, which is
the user-friendly option for a device like this.

NFS, by default, is not that forgiving because it was born in big datacenters where the resident 
greybeards did care passionately about who could do what to their precious files. By virtue of
this, the default for NFS servers is to tell the MiSTer's ```root``` user to go play a fiddle 
in a field somewhere instead of trying to write to the server's files as ```root``` no less.

MiSTer's ```root``` user will be mapped to the server's ```nobody``` user by default, which will most
likely mean a world of pain for MiSTer users: you can hardly access anything, let alone write to any
files from your MiSTer.

In order to change this, you can do one of generally two things:

  - Adjust the ```/etc/exports``` file on your server so that ```root``` on a client gets mapped to
    ```root``` on the server as well. All NFS-servers are different so there's no one-size-fits-all
    recipe to give for this. Consult the manual for your specific NFS-server of NAS device. Look for
    terms like 'maproot' or 'root squash'.
  - Look up the specific user and group that ```root``` gets mapped to and change the permissions on
    your server's file system so that this mapped user, usually ```nobody```, is allowed the proper
    access to both files and directories.

## Still can't write to my network share

Your server may have exported the directory itself as read-only. In that case the NFS-server will go
full-on Gandalf at your MiSTer: you shall not pass, not even if you are ```root```. Have a good look
at your ```/etc/exports``` file on the server, look for ```ro``` in the export definiton of the path
you are trying to mount and get rid of it.

## Can't write to this particular file

What if all files are fine except this one file or directory? That's almost always a permissions issue
combined with the ```root``` user being mapped to something else on the server. The files that refuse
to play ball are generally owned by the wrong user on the server's side, or they have the wrong
permissions set on them.

You're dealing with the dark underbelly of the 1970's world of UNIX here. Learn it, it's fun! Or use
something like a USB-drive or a bigger SD-card instead.

## Combinations with USB and CIFS storage

MiSTer provides alternative options for storage next to NFS. At the time of this writing, these options
have not been unified into any kind of Grand Unifying Storage Architecture for the MiSTer so this is
the observed behavior from initial testing.

USB trumps everything. When you attach USB-storage, its contents get overlaid onto everything else
including CIFS and NFS storage options.

CIFS and NFS do coexist fairly peacefully since they both have different mechanics of exposing their
contents to the user. The NFS-script overlays the NFS mounts onto the existing structures on the SD-card,
while CIFS exposes its own ```cifs``` directory which the cores prefer when they detect it, giving you
the option of navigating to the SD-card directory structures that sit alongside it.

At this point in time, these items are simply facts of life. If/when NFS sees any significat uptake it'd
probably be a good idea to unify alternative storage options into a predictable mechanism. For now the
user should note that these differences exist.

## General wonkiness after turning my MiSTer off

As mentioned before, NFS comes from datacenters where one does not simply power off a machine. NFS
was designed against a background of sysadmins knowing what they're doing and performing a clean
shutdown at the end of their session.

MiSTer, on the other hand, is an appliance. The computers it simulates have no notion of a clean
shutdown procedure. Back in the 1980's we just flipped the switch and that was it.

While the NFS-server will survive if you do this, chances are that some wonky behaviour ensues if
you turn it back on again very quickly. NFS simply wasn't made with this usage pattern in mind and
any problems have to do with files being "open" from the server's perspective and remaining that way
in the face of the client simply falling off the face of the planet.

These dangling references don't happen very often, but they do happen and they can corrupt any files
that *the NFS-server* thinks you were still writing to when you turned your MiSTer off.

You can prevent this whole issue from occurring by only using read-only mounts, which is perfectly
fine for immutable things like arcade ROM's and the like. It won't go over very well for hard disk
images for cores like PCXT/AO486 or Amiga. Those simulated machines expect their drives to be
writable at all times and things get hairy if they're not.

This is a fact of life when using a datacenter protocol with an appliance and will also happen if
you rudely hang up a CIFS server, so there's no real recourse against this. You really should always
call the ```nfs_unmount.sh``` script from the ```Scripts``` folder before shutting down your MiSTer. 
The ```MOUNT_AT_BOOT``` flag installs a script that cleanly unmounts your NFS share upon clean
system shutdown. The main problem with that is that clean system shutdowns are so rare on MiSTer.
