# GitHub setup — publish this project

Repository: **https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater**

This guide assumes you already created an **empty** repository on GitHub (no README added by GitHub, or you will merge later).

---

## 1. Prerequisites on your machine

```bash
git --version    # any recent git
ssh -T git@github.com   # optional; use HTTPS if SSH is not configured
```

Install git if missing:

```bash
sudo apt install git
```

---

## 2. First-time upload (from your project folder)

```bash
cd /path/to/MaSi-OS-Kernel-Updater   # your local clone or project directory

git init
git branch -M main

git add .
git status    # should NOT list output/ or .cache/ (see .gitignore)

git commit -m "Initial release: SM8550 gaming kernel builder and updater"

git remote add origin https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater.git

git push -u origin main
```

GitHub will ask for credentials:

- **HTTPS:** use a [Personal Access Token](https://github.com/settings/tokens) as password (not your account password).
- **SSH:** use `git@github.com:MaSieS4Fun/MaSi-OS-Kernel-Updater.git` as remote instead of HTTPS.

---

## 3. If GitHub created a README when you made the repo

Your first push may be rejected. Option A (simplest if the GitHub README is empty boilerplate):

```bash
git pull origin main --rebase
# resolve conflicts if any, then:
git push -u origin main
```

Option B — overwrite remote (only if you are sure nothing important is on GitHub):

```bash
git push -u origin main --force
```

---

## 4. Later updates

After you change files locally:

```bash
cd /path/to/MaSi-OS-Kernel-Updater
git add .
git commit -m "Describe your change"
git push
```

---

## 5. What should **not** be committed

Already in `.gitignore`:

- `output/` — built kernels and install bundles  
- `.cache/` — downloaded kernel sources and patches  
- `config/local.conf` — personal overrides  

Do **not** commit full kernel tarballs, `boot/KERNEL` binaries, or personal UUIDs.

`config/golden.config` **should** be committed (project baseline).

`device-tree/vendored/` — commit the vendored DTB slots if you have them; otherwise users run `vendor-dtb-chain.sh` once.

---

## 6. Recommended GitHub repository settings

On GitHub → **Settings** → **General**:

- **Description:** `Gaming kernel builder & updater for SM8550 handhelds (ABL bootimg, Armbian)`
- **Topics:** `sm8550`, `armbian`, `kernel`, `ayn-odin2`, `gaming`, `bootimg`

Optional: enable **Issues** and **Discussions** for community questions.

---

## 7. Clone for other users

```bash
git clone https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater.git
cd MaSi-OS-Kernel-Updater
./make.sh
```

See root [README.md](../README.md) for build dependencies and install steps.
