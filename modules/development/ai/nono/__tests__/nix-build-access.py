from datetime import timedelta
import json

machine.start()
machine.wait_for_unit("multi-user.target")
machine.wait_for_unit("nix-daemon.socket")
machine.succeed("test -S /nix/var/nix/daemon-socket/socket")
machine.succeed("su - tester -c 'test ! -w /nix/var/nix/daemon-socket'")

# Wheel still permits sudo outside Pi, but no longer grants trusted daemon access.
normal = json.loads(machine.succeed("su - tester -c 'nix store info --json --store daemon'"))
assert normal["trusted"] is False, normal
root = json.loads(machine.succeed("nix store info --json --store daemon"))
assert root["trusted"] is True, root
assert machine.succeed("su - tester -c 'sudo -n id -u'").strip() == "0"
machine.succeed("su - tester -c 'test -r /etc/pi-host-only-marker'")
machine.succeed("su -s /bin/sh nixbld1 -c 'test -r /etc/pi-host-only-marker'")
machine.succeed("su - tester -c 'test -x /run/current-system/bin/switch-to-configuration'")
system_profile = machine.succeed("readlink -f /nix/var/nix/profiles/system").strip()
active_system = machine.succeed("readlink -f /run/current-system").strip()
machine.succeed("test -e /run/pi-system-activation; rm /run/pi-system-activation")
machine.succeed("su - tester -c 'mkdir -p ~/work ~/.pi ~/.npm/_cacache ~/.npm/_logs'")

result = machine.succeed(
    "su - tester -c 'cd ~/work && "
    "nono run --profile /etc/nono/pi.json "
    "--allow-cwd --no-audit --no-rollback -- node /etc/pi-nix-build-probe.mjs'",
    timeout=timedelta(seconds=120),
)
report = json.loads(result.strip())
assert report == {
    "trusted": False,
    "builds": 3,
    "sandboxOverride": "ineffective",
    "noChroot": "denied",
    "normalDaemon": "untrusted",
    "privilegeElevation": "denied",
    "systemProfile": "denied",
    "activation": "denied",
}, report
assert machine.succeed("readlink -f /nix/var/nix/profiles/system").strip() == system_profile
assert machine.succeed("readlink -f /run/current-system").strip() == active_system
machine.succeed("test ! -e /run/pi-system-activation")
print(json.dumps(report, sort_keys=True))
