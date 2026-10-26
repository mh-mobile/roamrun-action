# RoamRun install and launch

A GitHub Action that installs an `.ipa` on your iPhone or iPad and launches it, from a job, over
Tailscale, with [roamrunctl](https://github.com/mh-mobile/RoamRun/tree/main/Rust/roamrunctl). The
device stays where it is (at home, at the office); the job reaches it through your tailnet.

It does one of two things, as [RoamRun's CI guide](https://github.com/mh-mobile/RoamRun/blob/main/docs/ci.md)
describes them:

- **`key`**: roamrunctl runs on the runner, with the device's pairing from a secret. Nothing of yours
  runs while the job does.
- **`relay`**: a machine of yours beside the device runs `roamrunctl mcp --http` and keeps the
  device's key; the job sends it the `.ipa` and the relay installs and launches.

The job joins the tailnet first, with [tailscale/github-action](https://github.com/tailscale/github-action).
The guide covers the setup: the Tailscale tag and OAuth client, the pairing for CI, and the relay.

## Usage

With the key on the runner:

```yaml
- uses: tailscale/github-action@v4
  with:
    oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
    oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
    tags: tag:ci
- uses: mh-mobile/roamrun-action@v1
  with:
    key: ${{ secrets.ROAMRUN_CI_KEY }}
    ipa: build/MyApp.ipa
```

Through a relay:

```yaml
- uses: tailscale/github-action@v4
  with:
    oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
    oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
    tags: tag:ci
- uses: mh-mobile/roamrun-action@v1
  with:
    relay: 100.x.y.z:9090
    token: ${{ secrets.RELAY_TOKEN }}
    device: phone
    ipa: build/MyApp.ipa
```

The `.ipa` has to be signed for the device (a development or ad hoc profile that lists it).
One device takes one install at a time: give jobs that install on it a
[concurrency](https://docs.github.com/actions/using-jobs/using-concurrency) group, as the guide shows.

## Inputs

| Input | |
|---|---|
| `key` | The device's pairing, a secret: a file `roamrun key create` wrote, or one `roamrunctl pair control` saved. Give this or `relay`. |
| `relay` | The relay's address and port, as `roamrunctl mcp --http` printed them. Give this or `key`. |
| `token` | With `relay`, the relay's token, a secret. |
| `device` | With `relay`, the device as the relay names it (required). With `key`, the name it is saved under on the runner (default `device`). |
| `ipa` | The `.ipa` to install. Without it, only `bundle-id` is launched. |
| `bundle-id` | The app to launch. Without it, the app the `.ipa` holds is launched. |
| `launch` | `false` to install only. Default `true`. |
| `timeout` | With `relay`, the most seconds to wait for the install. By default, what the relay gives the upload and the install, and a minute more. |
| `roamrunctl-version` | The roamrunctl release to use. Default `0.11.0`. With `relay`, the relay runs 0.10.0 or later. |

## What it does

1. Checks the inputs, and stops with a message before anything is downloaded or sent.
2. Downloads roamrunctl for the runner (Linux or macOS, x86_64 or arm64) from RoamRun's release,
   checks it against the release's `roamrunctl-SHA256SUMS`, and unpacks it into a folder of its own
   under the runner's temporary folder.
3. With `key`: `roamrunctl key import -` reads the key from standard input into that folder. Then
   `roamrunctl install … --launch` (or `install`, or `launch`).
   With `relay`: `roamrunctl install … --relay <relay> --launch`. roamrunctl uploads the `.ipa`,
   checks the sha256 the relay answers, waits for the install by the id the relay gives it, and
   launches.
4. Removes that folder, the key's file with it, whether the step passed or not.

Windows runners aren't supported. roamrunctl's messages show in the job's log; the key and the
token don't.

## On macOS runners

On macOS, tailscale/github-action points the system's DNS at `100.100.100.100` when the tailnet
has MagicDNS on. On the tailnet this was tried with, github.com then stopped resolving, so nothing
could be downloaded from GitHub (that tailnet's DNS settings weren't looked into). This action reaches
the device and the relay by their addresses, not by name, so the runner's own DNS can be put back
right after the Tailscale step:

```yaml
- uses: tailscale/github-action@v4
  with:
    oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
    oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
    tags: tag:ci
- if: runner.os == 'macOS'
  run: sudo networksetup -setdnsservers Ethernet Empty
```

`networksetup` is macOS's own tool for network settings. `-setdnsservers Ethernet Empty` clears
the DNS servers set by hand for the network service `Ethernet` (the runner's wired connection on
`macos-15`; `networksetup -listallnetworkservices` lists them on another image), so macOS goes
back to the ones its network gave it. The runner allows `sudo` without a password. After this,
public names such as github.com resolve again, and Tailscale names (MagicDNS) don't.

## What was tried

On 2026-10-24 (UTC), from a private repository, with this action at d74fce6 (v1.0.0 adds only this section) and
roamrunctl 0.9.0, on an iPhone 15 Pro (iOS 27.0) at home, unlocked, the runner joined with
tailscale/github-action@v4 and the tag `tag:ci`; a 1 MB development-signed `.ipa`:

| Runner | Way | Result |
|---|---|---|
| `ubuntu-24.04` | `key` (a file `roamrun key create` wrote), `ipa` | installed and launched |
| `ubuntu-24.04` | `key` (a file `roamrunctl pair control` saved on Linux), `bundle-id` | launched |
| `macos-15` (arm64), with the DNS line above | the same two | the same |
| `ubuntu-24.04` | `relay` (a MacBook Pro beside the device, roamrunctl 0.9.0) | installed (5 s) and launched |

On 2026-10-26 (UTC), with this action at 07dd4d1 (its default roamrunctl 0.11.0; v1.1.0 adds only
this paragraph and the relay's minimum above), on an iPhone Duo, the runner joined with a signed
auth key on a tailnet with Tailnet Lock:

| Runner | Way | Result |
|---|---|---|
| `ubuntu-24.04` | `relay` (a MacBook Pro, roamrunctl 0.11.0) | installed (6 s) and launched |
| `ubuntu-24.04` | `relay` (the same MacBook Pro, roamrunctl 0.10.0) | installed (5 s) and launched |

`key` wasn't run with 0.11.0, nor a relay of 0.9.0 with it.

`launch: false`, and the three ways of `ipa` / `bundle-id`, ran from a Mac with the action's script
against the same device. Not tried: `ubuntu-24.04-arm` and `macos-15-intel` runners, `timeout`,
self-hosted runners, an iPad, a larger `.ipa`.

## License

MIT
