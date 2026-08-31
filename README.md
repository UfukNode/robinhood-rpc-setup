# Robinhood Chain RPC Node Setup Guide

Turkish guide: [TR-Rehber.md](TR-Rehber.md)

This guide explains how to run your own Robinhood Chain RPC node. Configuration files come from
Robinhood's CDN, the Docker image is pinned to the version in the official documentation, and
snapshot metadata comes from Arbitrum's snapshot index. Before starting, the script verifies the
configuration chain ID, parent chain and Rollup address, as well as the snapshot status, URL and
SHA-256 checksum.

The included `script.sh` performs the installation in one guided flow using the selected network
and the Ethereum L1 endpoints you provide.

---

## Overview

| Property | Value |
| --- | --- |
| Network | Robinhood Chain Mainnet |
| Chain ID | 4663 |
| Type | Arbitrum Nitro L2 settling on Ethereum |
| Official documentation | https://docs.robinhood.com/chain/run-a-full-node/ |
| Public RPC | https://rpc.mainnet.chain.robinhood.com |
| Explorer | https://robinhoodchain.blockscout.com |

---

## System Requirements

| Requirement | Details |
| --- | --- |
| RAM | 64 GB minimum, 128 GB recommended |
| Storage | Locally attached NVMe; twice the current chain size plus 20% free space |
| Operating system | Ubuntu 22.04 or 24.04 |
| Docker | Installed automatically when missing |
| Ethereum L1 | One execution RPC and one beacon endpoint; both are required |
| Historical L1 data | Execution must serve historical `eth_getLogs`; beacon must serve historical blobs |

Latest completed `pruned` snapshots found in the Arbitrum index on August 31, 2026:

| Network | Date | Download size |
| --- | --- | --- |
| Mainnet | 2026-08-26 | 466 GB |
| Testnet | 2026-08-28 | 233 GB |

These are compressed download sizes, not the final on-disk database size. The official
documentation requires several terabytes and `(2 x current chain size) + 20%` free space. Do not
start with a disk that only barely fits the archive. The default `pruned` snapshot is suitable for
normal RPC use. Workloads that require historical block state need an archive node, which the
Robinhood documentation says must sync from genesis.

---

## Ethereum L1 Connection

This section comes first because L1 access is a major part of the cost and is often omitted from
setup guides.

Robinhood Chain posts data to Ethereum as blobs. Your node needs two separate Ethereum endpoints:

1. **L1 execution RPC**, a standard Ethereum JSON-RPC endpoint.
2. **L1 beacon RPC**, which provides the blob data that is not available through execution RPC.

If you operate your own synced Ethereum execution and beacon nodes, you can use those. Otherwise,
you need a provider that offers both endpoint types. Some RPC providers do not expose the Beacon
API, so confirm this before purchasing a plan.

Your execution endpoint must also answer `eth_getLogs` queries for the old Ethereum blocks where
the Robinhood Rollup contracts were deployed. This does not necessarily require operating your own
Ethereum archive-state node, but the provider must not block historical log requests. The following
provider response was reproduced during a real installation:

```text
ERROR error initializing database
err="failed getting delayed messages ...: 403 Forbidden:
     Archive requests require a personal token"
```

Before installation, the script checks the L1 chain ID, a historical log query at the Rollup
deployment block and basic Beacon API connectivity. A successful `/eth/v1/node/version` response
does not prove that the provider retains old blobs. Confirm historical blob availability for your
provider plan separately.

If you prefer one provider for both endpoints, Alchemy offers Ethereum execution and beacon APIs:
https://www.alchemy.com/rpc/ethereum

Free public endpoints can change quotas and historical-data policies without notice. Initial sync
produces a large number of L1 requests, so this guide does not recommend a fixed free endpoint. Use
your own fully synced Ethereum execution and beacon nodes, or an authenticated provider that
explicitly supports historical logs and blobs.

Nitro may print the execution URL at INFO level. If the URL contains an API key, it can appear in
`journalctl` as well. Restrict keys by IP and quota, do not publish raw log screenshots, and rotate
any key that is accidentally exposed.

---

## Choosing a Server

Check the actual hardware rather than relying on the provider name: a modern 8+ core CPU, at least
64 GB RAM, locally attached NVMe and several terabytes of expandable storage. Network storage, HDDs
and low-IOPS shared VPS plans can make synchronization extremely slow even when their advertised
capacity looks sufficient.

---

## 1. Connect to the Server

```bash
ssh root@[SERVER_IP]
```

Replace `[SERVER_IP]` with the IP address of your server.

Windows users can first follow this WSL installation guide:
https://x.com/UfukDegen/status/1944066889346429338

---

## 2. Download the Script

```bash
git clone https://github.com/UfukNode/robinhood-rpc-setup.git
cd robinhood-rpc-setup
chmod +x script.sh
```

![Clone the repository and make the script executable](assets/en/screenshot-01-repository-setup.png)

---

## 3. Start the Installation

```bash
sudo ./script.sh
```

---

## 4. Language and Installation Options

The script first asks you to choose a language. All subsequent prompts and help messages use the
selected language.

![Select English in the setup script](assets/en/screenshot-02-language-selection.png)

The script then:

- Checks RAM and disk capacity and warns when they are insufficient.
- Installs Docker when it is missing.
- Tests the supplied L1 endpoints and stops if they use the wrong network.
- Downloads Robinhood configuration files and verifies the chain ID, parent chain and Rollup address.
- Selects the latest completed snapshot from the Arbitrum index and verifies its checksum.
- Creates and starts a systemd service named `robinhood-rpc`.

![System, L1, configuration and snapshot preflight checks](assets/en/screenshot-03-preflight-checks.png)

Snapshot sizes change over time. The script prints the current size before starting. Nitro performs
the actual download, which can take several hours.

When setup finishes, the service, firewall and local RPC details are shown together:

![Completed Robinhood RPC installation](assets/en/screenshot-04-installation-complete.png)

---

## 5. Follow the Logs

```bash
journalctl -u robinhood-rpc -f
```

At startup, the log shows the Nitro version, L1 connection and initial snapshot URL:

![Live Robinhood RPC service logs](assets/en/screenshot-05-live-logs.png)

Once `HTTP server started` and `WebSocket enabled` appear, the RPC server is listening.

During the first hours, the block number may not move because Nitro is downloading and extracting
the snapshot. This is normal while download progress continues.

The HTTP and WebSocket servers may not start until the snapshot has been downloaded and imported.
During this phase, no response on port `8547` is not by itself an error. Follow the
`transferred ... bytes` progress in the logs.

---

## 6. Check Synchronization

```bash
curl -s -X POST http://127.0.0.1:8547 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_syncing","params":[]}'
```

Synchronization is complete when the result is `false`.

Check the current block number:

```bash
curl -s -X POST http://127.0.0.1:8547 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'
```

Confirm that the node uses the correct chain:

```bash
curl -s -X POST http://127.0.0.1:8547 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
```

Example verification after synchronization completes:

![Verify synchronization and the Robinhood Chain ID](assets/en/screenshot-06-rpc-verification.png)

`0x1237` is hexadecimal for **4663**, the Robinhood Chain ID. A different result means the node is
using the wrong configuration.

Compare the node's latest block with the explorer:
https://robinhoodchain.blockscout.com

---

## 7. Use the RPC

After synchronization, the local endpoints are:

```text
HTTP       : http://127.0.0.1:8547
WebSocket  : ws://127.0.0.1:8548
Chain ID   : 4663
Gas token  : ETH
```

The safest way to use them remotely is an SSH tunnel. Run this command on your own computer:

```bash
ssh -L 8547:127.0.0.1:8547 -L 8548:127.0.0.1:8548 root@[SERVER_IP]
```

While the tunnel is open, `http://127.0.0.1:8547` on your computer connects to the node without
opening a public RPC port.

If another server needs permanent access, first enable UFW with a default incoming policy of
`deny`, then restrict RPC access to that server's IP:

```bash
sudo ./script.sh --expose-rpc yes --allowed-ip [YOUR_IP] \
  --l1-rpc [L1_RPC_URL] --l1-beacon [BEACON_URL]
```

- Replace `[YOUR_IP]` with the address allowed to connect.
- Without an allowed IP, the RPC can be exposed to the entire internet. The script asks for an
  additional confirmation before doing this.
- For a public production RPC, add TLS, authentication and rate limiting through Nginx or Caddy.

---

## Commands

| Command | Description |
| --- | --- |
| `journalctl -u robinhood-rpc -f` | Follow live logs |
| `systemctl status robinhood-rpc` | Show service status |
| `systemctl stop robinhood-rpc` | Stop the node |
| `systemctl start robinhood-rpc` | Start the node |
| `systemctl restart robinhood-rpc` | Restart the node |
| `sudo ./script.sh --uninstall` | Remove service and configuration; preserve chain data |
| `sudo ./script.sh --help` | Show every script option |

---

## Script Options

| Option | Purpose |
| --- | --- |
| `--lang tr\|en` | Interface language; prompts when omitted |
| `--network mainnet\|testnet` | Network to install; defaults to mainnet |
| `--l1-rpc <url>` | Required Ethereum execution RPC endpoint |
| `--l1-beacon <url>` | Required Ethereum beacon endpoint |
| `--dry-run` | Run checks without installing Docker or the node service |
| `--expose-rpc yes` | Bind RPC to the network |
| `--allowed-ip <ip>` | Allow only this IP when RPC is exposed |
| `--rpc-port <port>` | Change HTTP port; defaults to 8547 |
| `--ws-port <port>` | Change WebSocket port; defaults to 8548 |
| `--data-dir <path>` | Data and configuration root; defaults to `/root/rh` |
| `--snapshot-type <type>` | `pruned`, `full-path` or `archive-path`; safely stops on multipart snapshots |
| `--forwarding-target <url>` | Transaction forwarding target; defaults to the official sequencer. Use `null` for read-only |
| `--no-snapshot` | Sync from genesis without a snapshot; takes much longer |
| `--non-interactive` | Disable prompts |
| `--uninstall` | Remove the service and configuration without deleting chain data |

---

## Recommendations

- Run `--dry-run` before downloading hundreds of gigabytes.
- Use `--data-dir` when chain data should live on a separate NVMe volume.
- Do not expose RPC to the entire internet. Restrict it with `--allowed-ip` when remote access is
  required.
- The compressed archive and extracted database coexist during import. Size the disk for both.
- Systemd restarts the node after an unexpected exit. Repeated restarts usually indicate an L1 or
  disk problem; inspect the logs.
- Testnet requires Sepolia execution and beacon endpoints. The script rejects the wrong L1 network.
- Do not use free public L1 endpoints. A chain ID check can pass while historical data or sync quota
  remains insufficient.

---

## Troubleshooting

**"The L1 execution URL did not answer"**

The URL may be incorrect, the provider may be unavailable, or the key may be invalid:

```bash
curl -s -X POST [L1_RPC_URL] -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
```

**"Wrong L1: that URL returned chainId ..."**

Mainnet requires Ethereum Mainnet endpoints. Testnet requires Sepolia endpoints.

**"The L1 beacon URL did not answer"**

Your provider may not expose the Beacon API:

```bash
curl -s [BEACON_URL]/eth/v1/node/version
```

**"Archive requests require a personal token" or a similar 403 response**

The execution provider is blocking historical log requests. This does not necessarily mean you
must run an Ethereum archive-state node; the provider must allow historical `eth_getLogs`. Test the
Robinhood Mainnet Rollup deployment block with:

```bash
curl -s -X POST [L1_RPC_URL] -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_getLogs","params":[{"address":"0x23A19d23e89166adedbDcB432518AB01e4272D94","fromBlock":"0x17d61be","toBlock":"0x17d61be"}]}'
```

**"ForwardingTarget not set and not sequencer"**

The script supplies the required flag automatically. The command in the official guide omits it,
but the tested image does not start without a forwarding target. For a manual setup, add:

```text
--execution.forwarding-target=https://sequencer.mainnet.chain.robinhood.com
```

**"no space left on device"**

The snapshot is hundreds of gigabytes while compressed, and the archive and extracted database
coexist during import. Check `df -h` and follow Nitro's disk-capacity formula instead of relying only
on the compressed download size.

**"stream error: INTERNAL_ERROR" or "attempt 1 failed: unexpected EOF"**

Both messages indicate that the snapshot CDN closed a long transfer. Nitro's downloader supports
HTTP Range requests and resumes from the existing file. The error alone does not mean data loss if
the file continues to grow.

The script sets `GODEBUG=http2client=0` so Nitro downloads the snapshot over HTTP/1.1. It also uses a
persistent `snapshot-download` directory outside the database. A service restart resumes from the
same byte. After import succeeds and RPC responds, the `robinhood-rpc-snapshot-cleanup` service
removes the downloaded archive.

Monitor the file size with:

```bash
watch -n 10 'du -h /root/rh/robinhood-nitro-data/snapshot-download/'
```

**"found unexpected files in database directory, including: tmp"**

An older script version downloaded the snapshot into Nitro's database `tmp` directory. If the
service stopped during download, that directory blocked the next startup. The current script uses a
separate persistent `snapshot-download` directory, so new installations do not create this failure.

**Logs show `/home/user/.arbitrum/...`**

This is expected. Although the Robinhood documentation uses `/home/nitro`, the pinned
`v3.11.2-3599aca` image was verified to run as `uid=1000(user)` with `HOME=/home/user`; the image does
not contain `/home/nitro`. The script mounts the host data directory at `/home/user/.arbitrum` and
grants UID 1000 write access. Using the old mount path placed data in Docker's temporary layer, which
was lost with the container.

**The service keeps restarting**

```bash
journalctl -u robinhood-rpc -n 100 --no-pager
```

The most common causes are an unavailable L1 endpoint or a full disk.

---

Source: [Official Robinhood Chain documentation](https://docs.robinhood.com/chain/run-a-full-node/)

Author: [@UfukDegen](https://x.com/UfukDegen)
