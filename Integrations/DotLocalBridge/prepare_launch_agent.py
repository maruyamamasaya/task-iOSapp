"""Print a reviewable launchd plist. Does not install, enable or modify user state."""
import pathlib, plistlib, sys
root = pathlib.Path.home()/'Library/Application Support/CalendarTaskApp/DotLocalRelay'
value = {
    'Label': 'local.CalendarTaskApp.DotLocalRelay',
    'ProgramArguments': [sys.executable, str(root/'service/run_approved_relay.py'), '--foreground'],
    'WorkingDirectory': str(root/'service'),
    'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 30,
    'ProcessType': 'Background', 'Umask': 0o077,
    # All diagnostics go through the bounded application logger. launchd stderr is discarded.
    'StandardOutPath': '/dev/null', 'StandardErrorPath': '/dev/null',
}
sys.stdout.buffer.write(plistlib.dumps(value))
