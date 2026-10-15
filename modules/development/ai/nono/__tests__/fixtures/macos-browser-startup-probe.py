import ctypes as c
import os
import sys

if sys.argv[1:] == ["--compile"]:
    sandbox = c.CDLL("/usr/lib/libsandbox.dylib")
    sandbox.sandbox_compile_string.argtypes = [c.c_char_p, c.c_void_p, c.POINTER(c.c_char_p)]
    sandbox.sandbox_compile_string.restype = c.c_void_p
    sandbox.sandbox_free_profile.argtypes = [c.c_void_p]
    sandbox.sandbox_free_error.argtypes = [c.c_void_p]
    error = c.c_char_p()
    profile = sandbox.sandbox_compile_string(sys.stdin.buffer.read(), None, c.byref(error))
    try:
        assert profile, error.value.decode() if error.value else "Seatbelt compilation failed"
    finally:
        if profile:
            sandbox.sandbox_free_profile(profile)
        if error.value:
            sandbox.sandbox_free_error(error)
    print("Seatbelt rules compiled")
    sys.exit(0)

io = c.CDLL("/System/Library/Frameworks/IOKit.framework/IOKit")
system = c.CDLL("/usr/lib/libSystem.B.dylib")
callback_type = c.CFUNCTYPE(None, c.c_void_p, c.c_uint32, c.c_uint32, c.c_void_p)
callback = callback_type(lambda *_: None)
port = c.c_void_p()
notifier = c.c_uint32()
io.IORegisterForSystemPower.argtypes = [
    c.c_void_p, c.POINTER(c.c_void_p), callback_type, c.POINTER(c.c_uint32)
]
io.IORegisterForSystemPower.restype = c.c_uint32
io.IODeregisterForSystemPower.argtypes = [c.POINTER(c.c_uint32)]
io.IONotificationPortGetRunLoopSource.argtypes = [c.c_void_p]
io.IONotificationPortGetRunLoopSource.restype = c.c_void_p
io.IONotificationPortDestroy.argtypes = [c.c_void_p]
io.IOServiceClose.argtypes = [c.c_uint32]

connection = io.IORegisterForSystemPower(None, c.byref(port), callback, c.byref(notifier))
try:
    assert connection and port.value, "IORegisterForSystemPower denied: Chromium would dereference a null notification port"
    assert io.IONotificationPortGetRunLoopSource(port), "IOKit notification run-loop source is null"
finally:
    # Do not attach the source to a run loop: the probe must not handle or delay sleep.
    if notifier.value:
        io.IODeregisterForSystemPower(c.byref(notifier))
    if port.value:
        io.IONotificationPortDestroy(port)
    if connection:
        io.IOServiceClose(connection)

bootstrap_port = c.c_uint32.in_dll(system, "bootstrap_port").value
task = c.c_uint32.in_dll(system, "mach_task_self_").value
system.bootstrap_check_in.argtypes = [c.c_uint32, c.c_char_p, c.POINTER(c.c_uint32)]
system.bootstrap_check_in.restype = c.c_int
system.mach_port_destroy.argtypes = [c.c_uint32, c.c_uint32]
system.mach_port_destroy.restype = c.c_int


def register(name):
    receive = c.c_uint32()
    result = system.bootstrap_check_in(bootstrap_port, name.encode(), c.byref(receive))
    if receive.value:
        assert system.mach_port_destroy(task, receive.value) == 0
    return result


for bundle in ["org.chromium.Chromium", "com.google.Chrome", "com.google.chrome.for.testing"]:
    name = f"{bundle}.MachPortRendezvousServer.{os.getpid()}"
    result = register(name)
    assert result == 0, f"Chromium Mach rendezvous denied: {name}: {result}"

for name in [
    f"com.example.pi-test.{os.getpid()}",
    f"org.chromium.Chromium.UnrelatedService.{os.getpid()}",
    f"org.chromium.Chromium.MachPortRendezvousServer.{os.getpid()}.extra",
    f"extra.org.chromium.Chromium.MachPortRendezvousServer.{os.getpid()}",
]:
    result = register(name)
    assert result == 1100, f"Unrelated Mach registration was not denied: {name}: {result}"

assert len(sys.argv) == 3, "Expected private-key and browser-cookie fixture paths"
for path in sys.argv[1:]:
    try:
        with open(path, "rb"):
            pass
    except PermissionError:
        continue
    raise AssertionError(f"Private fixture unexpectedly readable: {path}")

print("browser startup capabilities verified")
