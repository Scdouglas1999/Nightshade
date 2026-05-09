# Linux Environment Probe

- Linux build environment available: `false`
- WSL usable: `false`
- Docker usable: `false`
- Scope: host environment only; this does not build Nightshade for Linux.

## Command Results

| Check | Exit | Required | Command |
| --- | ---: | --- | --- |
| `wsl_status` | 0 | no | `wsl.exe --status` |
| `wsl_list` | 0 | no | `wsl.exe -l -v` |
| `wsl_ubuntu_uname` | -1 | yes | `wsl.exe -d Ubuntu -- uname -a` |
| `docker_version` | 1 | no | `docker version` |
| `docker_context_ls` | 0 | no | `docker context ls` |

## `wsl_status`

Exit code: `0`

Stdout:

```text
Default Distribution: Ubuntu
Default Version: 2
```

Stderr:

```text

```

## `wsl_list`

Exit code: `0`

Stdout:

```text
NAME              STATE           VERSION
* Ubuntu            Stopped         2
  docker-desktop    Stopped         2
```

Stderr:

```text

```

## `wsl_ubuntu_uname`

Exit code: `-1`

Stdout:

```text
Failed to attach disk 'C:\Users\scdou\AppData\Local\wsl\{5f0d72bf-1c39-43a6-bb42-5512156d0383}\ext4.vhdx' to WSL2: The system cannot find the file specified. 
Error code: Wsl/Service/CreateInstance/MountDisk/HCS/ERROR_FILE_NOT_FOUND
```

Stderr:

```text

```

## `docker_version`

Exit code: `1`

Stdout:

```text
Client:
 Version:           29.1.3
 API version:       1.52
 Go version:        go1.25.5
 Git commit:        f52814d
 Built:             Fri Dec 12 14:51:52 2025
 OS/Arch:           windows/amd64
 Context:           desktop-linux
```

Stderr:

```text
failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine; check if the path is correct and if the daemon is running: open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified.
```

## `docker_context_ls`

Exit code: `0`

Stdout:

```text
NAME              DESCRIPTION                               DOCKER ENDPOINT                             ERROR
default           Current DOCKER_HOST based configuration   npipe:////./pipe/docker_engine              
desktop-linux *   Docker Desktop                            npipe:////./pipe/dockerDesktopLinuxEngine
```

Stderr:

```text

```

