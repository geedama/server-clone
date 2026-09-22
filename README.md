# Codex server clone

Scripts for moving the `cooper` user's Codex installation, Codex Web, and
Hysteria/3proxy/PAC setup to a fresh Ubuntu x86_64 server.

Backup assets are encrypted with `age` before they are uploaded. The script
repository contains no credentials or backup data.

## Publish a backup

```bash
./publish.sh
```

Enter and safely retain the encryption passphrase when prompted.

## Restore the latest backup

The private backup repository requires a fine-grained GitHub token with only
`Contents: read` permission. The installer prompts for both that token and the
backup passphrase; neither should be included in the command line.

```bash
git clone https://github.com/geedama/server-clone.git
sudo ./server-clone/install.sh --target-ip 38.47.121.14
```

The retained proxy certificate is valid for `proxy.local`, not the new IP.
Client DNS or hosts files must map `proxy.local` to the target server IP.
