cd ../..

call ./psdk --util=plugin build cc-pokemon-boss-system

call ./psdk --util=plugin load

copy scripts\cc-pokemon-boss-system.psdkplug scripts\cc-pokemon-boss-system\ /Y

call ./psdk debug skip_title