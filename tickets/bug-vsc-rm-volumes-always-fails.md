# `vsc rm-volumes` can never succeed

`cmd_rm_volumes` (`vsc:259`) removes volumes while the owning container still
exists. Docker refuses to delete a volume referenced by *any* container, running
or stopped, so every removal fails with `could not remove (still in use?)`.

The precondition is already documented at `vsc:248` ("Requires the volume to be
free ... so the owning container must be gone first") but nothing enforces it.

## Fix

Either remove the container first (like `cmd_destroy` does), or detect that the
container still exists and fail with a message that says so.
