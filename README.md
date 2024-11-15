# discord-flatpak-rpc-bridge

Enables the use of Discord's Rich Presence (RPC) in Flatpak applications when
your Discord client is running as a native (host) application.

This is achieved by creating a bridge between the native Discord application's
RPC socket and the special RPC path required by various Flatpak applications.

The bridge is necessary because you *cannot* map the host's Discord RPC socket
into Flatpaks directly, since Flatpak *doesn't support* mapping host files that
constantly disappear and reappear (which the normal Host RPC socket does whenever
you close or reopen Discord).

Having this bridge will ensure that all Flatpaks with Discord RPC support work
with your native Discord client without needing *any* non-standard modifications.

Note: Always refer to your Flatpak app's documentation to see if they provide any
extra instructions for enabling Discord RPC. Our bridge provides the necessary
RPC socket, but it's up to the Flatpak applications to actually *use it.*


## Supported Applications

- Discord Native.
- [Vesktop](https://github.com/Vencord/Vesktop) Native.
- [arRPC](https://github.com/OpenAsar/arrpc) Native (and all other alternative
  Discord clients based on arRPC).
- Any other third-party clients that use the standard Discord RPC socket path.
- Ensure that Discord RPC is enabled in your client. The official client always
  provides it, whereas Vesktop for example has it under "Vesktop Settings: Enable
  Rich Presence via arRPC".
- You must also enable "Activity Privacy: Share your detected activities with
  others", otherwise Discord won't display the received Rich Presence status.


## Unsupported Usage

- Do **NOT** use *any* Flatpak-based Discord clients if you're using this bridge,
  since those clients will attempt to use the same socket paths as this bridge.
- Absolutely *zero* support will be given for such usage, because it makes no
  sense and there is no sane way to reconcile the socket path conflicts!
- In case of multi-user systems where some people might use native Discord and
  others might use the Flatpak variant, you should read the FAQ regarding how
  to enable per-user bridge startup control, and only enable socket bridging
  for the users that actually run native Discord clients.


## Installation

- Requires a systemd-based Linux distro (which is 99.9% of distros these days).
  If you don't know, then you're definitely using a systemd-based distro.
- Clone [this repository](https://github.com/Arcitec/discord-flatpak-rpc-bridge)
  or [download the latest code manually](https://github.com/Arcitec/discord-flatpak-rpc-bridge/archive/refs/heads/main.zip).
- Run the installation process.
```sh
./install.sh
```
- The bridge service is now installed and automatically enabled on startup for
  every user on your system. It also *immediately* starts for your current user.
- You can now use your native Discord client and your Flatpak apps without any
  more worries or issues. Have fun!


## Uninstalling

- If you've enabled manual startup mode (see FAQ below), then you should first
  remove any manually created startup links. This isn't necessary if you haven't
  done any of those steps.
- Then run the uninstaller, which will disable and completely remove the service.
```sh
./install.sh -u
```
- The service will also automatically stop for the *currently active* user.
- Note: If multiple users are simultaneously logged into your system, they should
  either log out or restart the machine, which will stop their running services
  too.


## Frequently Asked Questions

### Can I disable the automatic socket startup at user login?

- Sure. If you prefer to manage it per-user, or start it manually for some reason,
  then it's very easy to disable the "start automatically on all user logins" flag.
- First disable the automatic system-wide user startup, by switching to "manual
  startup mode". This gives you total control over which users start the bridge.
```sh
./install.sh -m
```
- Now you can use the per-user startup toggles. They have no effect if automatic
  startup mode is active, which is why you had to switch to manual mode first.
- The other options are described below.
- Enable bridge startup for the currently active user.
```sh
./install.sh -e
```
- Warning: If you ever remove the bridge from your computer, you must remember
  to disable all of your manually enabled user startups before uninstalling the
  bridge, or you will be left with dangling per-user systemd startup links.
- Disable bridge startup for the currently active user. This only removes the
  per-user startup link created by the `-e` flag, and has no effect if there isn't
  any per-user link already. Most notably, it *cannot* disable startup for users
  if system-wide automatic startup for all users is active (see `-m` for that).
```sh
./install.sh -d
```
- Enable automatic startup for all users again (the default mode and is already
  active after every installation). This takes precedence over all per-user
  startup toggles and means that every user will always auto-start the bridge
  on login. This reverses the `-m` action.
```sh
./install.sh -a
```
- If you actually want to start the connection socket manually without even having
  auto-start for your currently active user (for some insane reason), then you
  need to switch to manual mode with `-m` as described above, and then run the
  following command every time you want to manually start the socket.
```sh
systemctl --user start discord-flatpak-rpc-bridge.socket
```
- Always remember that automatic startup is the officially intended method, and
  uses no system resources at all until something connects to the socket, which
  means that there's usually no good reason to disable automatic startup. The
  ability to disable automatic startup is mostly intended for when *someone* on
  your computer uses a Flatpak-based Discord client while others use native
  clients, in which case the Flatpak-based users should not be using the bridge
  at all, since Flatpak Discord clients will attempt to create the exact same
  sockets as this bridge.


### How does it work?

- Native Discord RPC lives at `/run/user/1000/discord-ipc-0`, which is problematic
  because we cannot map `--filesystem=xdg-run/discord-ipc-0` into Flatpaks for
  many, many reasons.
- First of all, since it's a file, Flatpak will only map that host-file if it
  exists at the *exact moment* when the Flatpak is started. Furthermore, Flatpak
  doesn't support removing and/or creating that file on the Host *while* the
  Flatpak app is running. Flatpak mapping of *files* is a one-time startup mapping.
- That's an extremely serious problem, because Discord/arRPC will *constantly*
  delete and re-create that socket file whenever you close or start the Discord
  client.
- This means that you must first start your Discord client (to create the Host
  RPC socket file), and *then* start your Flatpak apps, and then *NEVER CLOSE*
  Discord, since the connection would immediately be broken and would not be
  re-established until you close and reopen all Flatpaks again to re-map the
  latest Host RPC socket file.
- Secondly, all Flatpak apps are being told to use a certain startup wrapper
  script to support Discord RPC. And that commonly used wrapper will delete your
  `/run/user/1000/discord-ipc-0` file inside of the Flatpak and instead symlink
  it to `/run/user/1000/app/com.discordapp.Discord/discord-ipc-0`, which means
  that even *if* you map the host's `discord-ipc-0` file, it will immediately
  be replaced (inside the Flatpak) by a symlink to another location instead.
- Thirdly, since `/run/user/1000/discord-ipc-0` already exists inside Flatpak
  apps due to the aforementioned wrapper script they all use, it actually shadows
  the `--filesystem=xdg-run/discord-ipc-0` command's file, meaning that nothing
  gets mapped into the Flatpak. The Flatpak will only see its own pre-existing
  symlink at that location.
- Lastly, we *cannot* map the entire `--filesystem=xdg-run` as some kind of blunt
  "map the entire host directory so that we can detect socket-files appearing and
  disappearing" workaround, because Flatpak *forbids* mapping `xdg-run` itself.
- In other words, you should *forget* trying to map `/run/user/1000/discord-ipc-0`
  from the Host directly into your Flatpak apps. It's *NEVER* going to happen.
- So how does our Discord Flatpak RPC Bridge solve these problems?
- Well, since there's already an established Flatpak standard where all Flatpaks
  attempt to use the [Discord Flatpak's](https://flathub.org/apps/com.discordapp.Discord)
  exported RPC path, we can immediately plug into their system by establishing
  a bridge between the expected Discord Flatpak RPC socket location and your
  real, native Host RPC socket.
- The nice thing about their solution is that it uses a special directory on the
  host which contains all RPC socket files, which means that all Flatpaks are
  already pre-configured to access that path, *and* since it's a directory, it
  fully supports the vanishing and re-appearance of socket files (when your client
  closes and reopens), since mapped directories always reflect the host's contents
  in realtime.
- Our bridge sets up a systemd "trigger socket" at the following location:
  `/run/user/1000/app/com.discordapp.Discord/discord-ipc-0`.
- The first time that any application connects to that socket, it triggers our
  "proxy service" systemd unit and tells it to launch. That service bridges the
  UNIX socket connection between the "Discord Flatpak RPC socket" and the true
  Discord RPC socket at `/run/user/1000/discord-ipc-0` on your host.
- To be more specific, only a single socket proxy service will be running, and
  it handles *all* multi-application connections between the two bridged sockets.
- Furthermore, this bridge fully supports the appearance and disappearance of
  the Host's target socket at `/run/user/1000/discord-ipc-0`, meaning that you're
  welcome to close and reopen your native Discord client as much as you want
  without ever losing the socket connection for your running Flatpak apps.
- If anything attempts to connect to the Flatpak socket location while Discord
  isn't running, meaning when the true `/run/user/1000/discord-ipc-0` socket
  doesn't exist, then the connection will simply be refused exactly as intended,
  but will begin working again the moment you launch the Discord client again.
  That's the exact same behavior as the native Discord client and native RPC apps,
  so as long as your apps are correctly written to support the Discord RPC socket
  periodically becoming unavailable (which naturally happens whenever you close
  Discord), then they'll reconnect as soon as Discord RPC is available again.
- The bridge is fully multi-user aware. Each user gets their own bridge at their
  personal `$XDG_RUNTIME_DIR` locations, and the bridge process only launches when
  a user actually attempts to use a Flatpak app that connects to Discord's RPC,
  meaning that it's incredibly resource-efficient too.
- If you want even more details, read the source-code comments of the systemd
  units and the installer.


### It still doesn't work with "Flatpak App X".

- Then *that Flatpak* is misconfigured. I can't do anything about that!
- Tell the author of the Flatpak to add support for the official Discord Flatpak's
  RPC connection method, which is described on the [Discord Flatpak Wiki](https://github.com/flathub/com.discordapp.Discord/wiki/Rich-Precense-(discord-rpc)#flatpak-applications),
  where there's a list of "suggested changes". All Flatpaks that want to support
  Discord RPC need to perform those steps to get access to the RPC socket.
- You can use [Flatseal](https://flathub.org/apps/com.github.tchx84.Flatseal)
  to inspect the Flatpak app's permissions. If they have given themselves access
  to `xdg-run/app/com.discordapp.Discord:create`, then it's a good indication that
  they've *probably* configured their launch-wrapper or app code correctly too.
- Warning: It's *not enough* to just add access to that directory. All Flatpak apps
  need further adaptations. Checking for the permission is just meant as a quick
  way for *you* to see if the author *appears* to have done the required preparations,
  since Flatpak apps will *never* be able to connect to Discord RPC without that
  permission.
- Note: In some cases, Flatpak app authors have disabled Discord RPC permissions
  by default (since many people view it as unnecessary). They'll often provide
  instructions for how to enable the necessary permissions manually. Always check
  their official Flatpak instructions for help. The information is often placed
  in the application's Flathub manifest repository or their official development
  repository, usually in their readme, wiki, or in their past tickets.
- Any reports about specific Flatpak app problems on this repository will lead
  to a ban from making any further tickets.
