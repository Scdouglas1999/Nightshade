# Linux Environment Probe

- Linux build environment available: `true`
- WSL usable: `false`
- Docker usable: `true`
- Scope: host environment only; this does not build Nightshade for Linux.

## Command Results

| Check | Exit | Required | Command |
| --- | ---: | --- | --- |
| `wsl_status` | -1 | no | `wsl.exe --status` |
| `wsl_list` | -1 | no | `wsl.exe -l -v` |
| `wsl_ubuntu_uname` | -1 | yes | `wsl.exe -d Ubuntu -- uname -a` |
| `docker_version` | 0 | no | `docker version` |
| `docker_context_ls` | 0 | no | `docker context ls` |

## `wsl_status`

Exit code: `-1`

Stdout:

```text

```

Stderr:

```text
ProcessException: No such file or directory
  Command: wsl.exe --status
```

## `wsl_list`

Exit code: `-1`

Stdout:

```text

```

Stderr:

```text
ProcessException: No such file or directory
  Command: wsl.exe -l -v
```

## `wsl_ubuntu_uname`

Exit code: `-1`

Stdout:

```text

```

Stderr:

```text
ProcessException: No such file or directory
  Command: wsl.exe -d Ubuntu -- uname -a
```

## `docker_version`

Exit code: `0`

Stdout:

```text
Client:
 Version:           29.5.2
 API version:       1.54
 Go version:        go1.26.3-X:nodwarf5
 Git commit:        79eb04c7d8
 Built:             Mon Jun  1 16:02:50 2026
 OS/Arch:           linux/amd64
 Context:           default

Server:
 Engine:
  Version:          29.5.2
  API version:      1.54 (minimum version 1.40)
  Go version:       go1.26.3-X:nodwarf5
  Git commit:       568f755ebe
  Built:            Mon Jun  1 16:02:50 2026
  OS/Arch:          linux/amd64
  Experimental:     false
 containerd:
  Version:          v2.3.1
  GitCommit:        64b425cf570b3b8dd1d4cc46da7c1fce65c6651a.m
 runc:
  Version:          1.4.2
  GitCommit:        1.4.2-1-0-g1ff2cd2-dirty
 docker-init:
  Version:          0.19.0
  GitCommit:        de40ad0
```

Stderr:

```text

```

## `docker_context_ls`

Exit code: `0`

Stdout:

```text
NAME        DESCRIPTION                               DOCKER ENDPOINT               ERROR
default *   Current DOCKER_HOST based configuration   unix:///var/run/docker.sock
```

Stderr:

```text

```

