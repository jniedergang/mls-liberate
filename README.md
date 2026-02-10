# liberate.sh - Conversion Enterprise Linux vers SUSE Liberty Linux

**Version**: 1.6.1

[English version below](#english-version)

---

## Table des matières

1. [Introduction](#introduction) — Description, fonctionnalités, distributions supportées
2. [Démarrage rapide](#démarrage-rapide) — Prérequis, installation, workflow complet
3. [Migration](#migration) — Migration basique, dépôts SUSE, dry-run/interactif
4. [Sauvegarde](#sauvegarde) — Créer, éléments, structure, export/import
5. [Restauration](#restauration) — Complète, minimale, granulaire, interactive
6. [Référence](#référence) — Options, fichiers, codes de sortie
7. [Dépannage](#dépannage) — Erreurs courantes, conseils
8. [Licence](#licence)

---

## Introduction

### Description

**liberate.sh** est un script shell qui automatise la conversion de distributions Enterprise Linux (Rocky, AlmaLinux, Oracle Linux, CentOS, RHEL, EuroLinux) vers **SUSE Liberty Linux** ou **SLES Expanded Support**.

Ce script est basé sur la [liberate-formula](https://github.com/SUSE/liberate-formula) Salt, avec des fonctionnalités étendues pour une meilleure gestion des sauvegardes et restaurations.

### Fonctionnalités

- [**Détection automatique**](#distributions-supportées) de l'OS et de la version (7, 8, 9)
- [**Configuration automatique des dépôts SUSE**](#configuration-des-dépôts-suse) (`--setup-repos`)
- [**Sauvegarde complète**](#créer-une-sauvegarde) avant migration avec capture des RPMs, dépôts, paquets
- [**Sauvegarde standalone interactive**](#éléments-sauvegardés) (`--backup`) : choix y/n par élément
- [**Restauration complète**](#restauration-complète) vers l'OS original
- [**Restauration granulaire**](#restauration-granulaire) : repos, paquets release, fichiers, config
- [**Restauration interactive**](#restauration-interactive) (`--restore-select`) : vue d'ensemble du backup, sélection du backup, choix y/n par élément
- [**Portabilité des backups**](#lister-exporter-importer) (export/import en archive)
- [**Mode dry-run et interactif**](#mode-dry-run-et-interactif) pour prévisualiser ou confirmer les changements
- [**Rapports de migration**](#workflow-complet) détaillés

### Distributions supportées

| Distribution | Version 7 | Version 8 | Version 9 |
|--------------|:---------:|:---------:|:---------:|
| Rocky Linux  | -         | ✓         | ✓         |
| AlmaLinux    | -         | ✓         | ✓         |
| Oracle Linux | ✓         | ✓         | ✓         |
| CentOS       | ✓         | ✓ (Stream)| ✓ (Stream)|
| RHEL         | ✓         | ✓         | ✓         |
| EuroLinux    | ✓         | ✓         | ✓         |

---

## Démarrage rapide

### Prérequis

- **Droits root** requis
- **dnf** ou **yum** installé
- **Espace disque** : minimum 100 Mo pour les sauvegardes
- **Dépôts SUSE** (uniquement pour la migration) : configurés automatiquement via `--setup-repos`, ou manuellement ([Documentation SUSE](https://www.suse.com/support/kb/doc/?id=000019587)). Non requis pour les opérations de sauvegarde et restauration (voir [Utilisation sans dépôts SUSE](#utilisation-sans-dépôts-suse))

### Utilisation sans dépôts SUSE

Le script peut être utilisé partiellement sans que les dépôts SUSE soient configurés. Cela permet de préparer un système avant d'avoir accès aux dépôts.

| Fonctionnalité | Sans dépôts SUSE | Avec dépôts SUSE |
|---|:---:|:---:|
| `--backup` (sauvegarde) | oui | oui |
| `--list-backups` | oui | oui |
| `--export-backup` / `--import-backup` | oui | oui |
| `--restore-select` / `--restore-*` | oui | oui |
| `--setup-repos` | oui (crée les fichiers .repo) | - |
| Migration (commande par défaut) | non | oui |
| `--reinstall-packages` | non | oui |
| Téléchargement des RPMs release dans le backup | non (liste uniquement) | oui |

> **Note** : sans dépôts SUSE, le backup ne pourra pas télécharger les RPMs release originaux (`rpms/` restera vide). La liste des paquets sera néanmoins sauvegardée dans `release-packages.list`, ce qui permet une restauration manuelle ultérieure.

### Avertissements

> **Précautions importantes avant migration**

- **Tester en environnement non-production** d'abord
- **S'assurer de la connectivité réseau** aux dépôts SUSE
- **Vérifier l'espace disque disponible** (minimum 100 Mo)
- **Ne pas interrompre** le processus de migration une fois démarré
- **Créer une sauvegarde système complète** avant la migration (snapshot VM, backup, etc.)

### Installation

```bash
# Télécharger le script
curl -O https://raw.githubusercontent.com/jniedergang/mls-liberate/master/liberate.sh

# Rendre exécutable
chmod +x liberate.sh
```

### Workflow complet

```bash
# 1. Configurer les dépôts SUSE
sudo ./liberate.sh --setup-repos

# 2. Effectuer la migration
sudo ./liberate.sh --interactive --verbose

# 3. Vérifier la migration
cat /etc/os-release
rpm -q sll-release

# 4. (Optionnel) Si besoin de restaurer
sudo ./liberate.sh --restore
```

---

## Migration

### Migration basique

```bash
# Migration avec sauvegarde automatique
sudo ./liberate.sh

# Migration avec réinstallation de tous les paquets
sudo ./liberate.sh --reinstall-packages

# Migration avec logos SUSE
sudo ./liberate.sh --install-logos
```

### Configuration des dépôts SUSE

```bash
# Configuration automatique des dépôts (détecte EL7/8/9)
sudo ./liberate.sh --setup-repos

# Forcer la reconfiguration (écrase les repos existants)
sudo ./liberate.sh --setup-repos --force

# Prévisualiser la configuration
sudo ./liberate.sh --setup-repos --dry-run -v
```

Le script configure automatiquement :
- **EL9** : dépôts SUSE Liberty Linux (SLL) dans `/etc/yum.repos.d/sll.repo`
- **EL7/8** : dépôts SLES Expanded Support dans `/etc/yum.repos.d/sles_es.repo`

> **Avec SUSE Multi-Linux Manager (MLM)** : si les dépôts SLL sont déjà configurés via MLM (`susemanager:channels.repo`), créez un fichier `/etc/yum.repos.d/sll.repo` vide (commentaire uniquement) pour que le script détecte les dépôts existants. L'option `--repo-url` n'est pas nécessaire.
> L'URL par défaut (`repo.suse.de`) est un miroir interne SUSE non accessible publiquement.

### Mode dry-run et interactif

```bash
# Prévisualiser toutes les actions sans rien modifier
sudo ./liberate.sh --dry-run --verbose

# Migration avec confirmation à chaque étape
sudo ./liberate.sh --interactive --verbose

# Combiner les deux pour une exploration complète
sudo ./liberate.sh --interactive --dry-run -v
```

- `--dry-run` : affiche les commandes sans les exécuter
- `--interactive` : demande confirmation avant chaque action importante
- `--verbose` / `-v` : affiche les messages INFO et la sortie des commandes

---

## Sauvegarde

### Créer une sauvegarde

```bash
# Sauvegarde interactive (choix y/n par élément)
sudo ./liberate.sh --backup -v

# Sauvegarde automatique (tous les éléments, lors de la migration)
sudo ./liberate.sh
```

Lors d'une migration classique, tous les éléments sont sauvegardés automatiquement.
Avec `--backup`, chaque élément peut être inclus ou exclu individuellement (prompts y/n).

### Éléments sauvegardés

| Élément | Description | Contenu |
|---------|-------------|---------|
| Liste des paquets | `rpm -qa` complet du système | `packages.list` |
| Dépôts | Fichiers `/etc/yum.repos.d/*.repo` | `repos/` |
| Fichiers release | `/etc/os-release`, `/etc/redhat-release`, etc. | `release-files/` |
| Configuration dnf/yum | `/etc/dnf/dnf.conf`, `/etc/yum.conf`, `protected.d/` | `dnf-yum-config/` |
| RPMs release | Paquets release originaux (download) | `rpms/` |
| Fichiers supprimés | Fichiers qui seront supprimés lors de la migration | `deleted-files/` |

Le fichier `metadata.json` est toujours créé et contient les métadonnées du système ainsi que la liste des éléments effectivement sauvegardés (`backed_up_elements`).

### Structure d'un backup

```
/var/lib/liberate/backups/<timestamp>/
├── rpms/                      # RPMs des paquets de release
│   ├── rocky-release-*.rpm
│   └── SHA256SUMS
├── deleted-files/             # Fichiers supprimés lors de la migration
│   ├── usr/share/redhat-release/
│   ├── usr/lib/os-release     # Cible du symlink /etc/os-release
│   └── etc/dnf/protected.d/redhat-release.conf
├── repos/                     # Fichiers .repo
├── release-files/             # /etc/os-release, etc.
├── dnf-yum-config/            # Configuration dnf/yum
├── packages.list              # Liste de tous les paquets
├── release-packages.list      # Liste des paquets de release
├── release-packages-info.txt  # Infos détaillées des paquets
├── deleted-files.manifest     # Liste des fichiers supprimés
└── metadata.json              # Métadonnées du système
```

### Lister, exporter, importer

```bash
# Lister les sauvegardes disponibles
sudo ./liberate.sh --list-backups

# Exporter une sauvegarde (sélection interactive)
sudo ./liberate.sh --export-backup

# Exporter une sauvegarde spécifique
sudo ./liberate.sh --export-backup latest

# Importer une sauvegarde
sudo ./liberate.sh --import-backup liberate-backup-20240115_103045.tar.gz
```

---

## Restauration

### Restauration complète

```bash
# Restauration complète vers l'OS original (utilise la dernière sauvegarde)
sudo ./liberate.sh --restore

# Restauration depuis une sauvegarde spécifique
sudo ./liberate.sh --restore 20240115_103045

# Restauration partielle (repos uniquement)
sudo ./liberate.sh --rollback
```

### Restauration minimale

```bash
# Supprime les paquets SUSE, restaure fichiers supprimés + paquet release
sudo ./liberate.sh --restore-minimal
```

### Restauration granulaire

```bash
# Restaurer uniquement les dépôts
sudo ./liberate.sh --restore-repos

# Restaurer uniquement les paquets release (RPMs)
sudo ./liberate.sh --restore-release

# Restaurer uniquement les fichiers supprimés
sudo ./liberate.sh --restore-files

# Restaurer uniquement la configuration dnf/yum
sudo ./liberate.sh --restore-config

# Restauration granulaire depuis une sauvegarde spécifique
sudo ./liberate.sh --restore-repos 20240115_103045
```

### Restauration interactive

```bash
# Sélection du backup + choix y/n par élément
sudo ./liberate.sh --restore-select
```

Affiche une vue d'ensemble du backup sélectionné (contenu, taille, état du système), puis propose chaque action individuellement. Les éléments vides sont ignorés automatiquement.

### Notes sur la restauration

- Les fichiers de dépôts SUSE (`sll.repo`, `sles_es.repo`) présents dans le backup sont **automatiquement filtrés** lors de la restauration pour éviter les conflits RPM (obsoletes)
- `/usr/lib/os-release` (cible du symlink `/etc/os-release`) est sauvegardé et restauré correctement
- L'ordre de restauration garantit que les paquets SUSE sont supprimés **avant** la réinstallation des paquets release d'origine
- Si les dépôts SUSE (MLM, RMT) sont encore actifs, ils sont désactivés pendant l'installation des paquets d'origine

### Comparaison des modes de restauration

| Mode | Supprime SUSE | Restaure repos | Restaure fichiers supprimés | Restaure paquet release | Restaure config |
|------|:-------------:|:--------------:|:---------------------------:|:-----------------------:|:---------------:|
| `--restore` | oui | oui | oui | oui | oui |
| `--restore-minimal` | oui | non | oui | oui | non |
| `--rollback` | non | oui | non | non | non |
| `--restore-repos` | non | oui | non | non | non |
| `--restore-release` | non | non | non | oui | non |
| `--restore-files` | non | non | oui | non | non |
| `--restore-config` | non | non | non | non | oui |
| `--restore-select` | choix | choix | choix | choix | choix |

---

## Référence

### Options

| Option | Description |
|--------|-------------|
| **Migration** | |
| `--reinstall-packages` | Réinstalle tous les paquets depuis les dépôts SUSE |
| `--install-logos` | Installe les paquets de logos/branding SUSE |
| `--setup-repos` | Configure automatiquement les dépôts SUSE |
| `--repo-url <url>` | URL de base des dépôts SUSE (défaut: https://repo.suse.de) |
| **Sauvegarde** | |
| `--backup` | Sauvegarde standalone interactive (choix y/n par élément) |
| `--no-backup` | Désactive la sauvegarde automatique |
| `--backup-dir <path>` | Répertoire de backup (défaut: /var/lib/liberate/backups) |
| `--list-backups` | Liste les sauvegardes disponibles |
| `--export-backup [name]` | Exporte une sauvegarde en archive (sélection interactive si pas de nom) |
| `--import-backup <file>` | Importe une sauvegarde depuis une archive |
| **Restauration** | |
| `--restore [name]` | Restauration complète vers l'OS original |
| `--restore-minimal [name]` | Restauration minimale (supprime SUSE + fichiers + paquet release) |
| `--restore-repos [name]` | Restaurer uniquement les dépôts |
| `--restore-release [name]` | Restaurer uniquement les paquets release |
| `--restore-files [name]` | Restaurer uniquement les fichiers supprimés |
| `--restore-config [name]` | Restaurer uniquement la configuration dnf/yum |
| `--restore-select [name]` | Restauration interactive (sélection backup + y/n par élément) |
| `--rollback` | Restauration partielle (repos uniquement) |
| **Général** | |
| `--interactive` | Mode interactif avec confirmations |
| `--dry-run` | Affiche les commandes sans les exécuter |
| `--force` | Force la migration même si déjà libéré |
| `--report` | Génère un rapport de migration détaillé |
| `--verbose, -v` | Affiche les détails des opérations |
| `--help, -h` | Affiche l'aide |

### Fichiers créés

| Fichier | Description |
|---------|-------------|
| `/etc/sysconfig/liberated` | Marqueur de migration |
| `/var/log/liberate.log` | Log principal |
| `/var/log/dnf_sll_migration.log` | Log de réinstallation (EL9) |
| `/var/log/yum_sles_es_migration.log` | Log de réinstallation (EL7/8) |

### Codes de sortie

| Code | Signification |
|------|---------------|
| 0 | Succès |
| 1 | Erreur (consulter /var/log/liberate.log) |

---

## Dépannage

### Erreurs courantes

| Message d'erreur | Cause | Solution |
|------------------|-------|----------|
| `This script must be run as root` | Script exécuté sans privilèges root | Exécuter avec `sudo ./liberate.sh` |
| `Unsupported distribution: xxx` | Distribution non prise en charge | Vérifier la liste des distributions supportées |
| `System already liberated` | Migration déjà effectuée | Utiliser `--force` pour ré-exécuter |
| `Insufficient disk space` | Espace disque insuffisant | Libérer au moins 100 Mo |
| `SUSE repos not configured` | Dépôts SUSE manquants | Configurer les dépôts avant migration |
| `Backup not found` | Sauvegarde introuvable | Vérifier avec `--list-backups` |
| `Failed to download packages` | Problème réseau | Vérifier la connectivité aux dépôts |
| `Could not resolve host: repo.suse.de` | URL par défaut inaccessible | Utiliser `--repo-url` ou configurer les dépôts via MLM/RMT |

### Conseils de dépannage

1. **Consulter les logs** : `/var/log/liberate.log` contient les détails de toutes les opérations
2. **Mode verbose** : Utiliser `--verbose` pour obtenir plus d'informations
3. **Mode dry-run** : Utiliser `--dry-run` pour tester sans modifier le système
4. **Vérifier les dépôts** : `dnf repolist` ou `yum repolist` pour vérifier la configuration

---

## Licence

MIT License

---
---

# English Version

**Version**: 1.6.1

---

## Table of Contents

1. [Introduction](#introduction-1) — Description, features, supported distributions
2. [Getting Started](#getting-started) — Prerequisites, installation, complete workflow
3. [Migration](#migration-1) — Basic migration, SUSE repos, dry-run/interactive
4. [Backup](#backup) — Create, elements, structure, export/import
5. [Restore](#restore) — Full, minimal, granular, interactive
6. [Reference](#reference) — Options, files, exit codes
7. [Troubleshooting](#troubleshooting) — Common errors, tips
8. [License](#license)

---

## Introduction

### Description

**liberate.sh** is a shell script that automates the conversion of Enterprise Linux distributions (Rocky, AlmaLinux, Oracle Linux, CentOS, RHEL, EuroLinux) to **SUSE Liberty Linux** or **SLES Expanded Support**.

This script is based on the [liberate-formula](https://github.com/SUSE/liberate-formula) Salt formula, with extended features for better backup and restore management.

### Features

- [**Automatic detection**](#supported-distributions) of OS and version (7, 8, 9)
- [**Automatic SUSE repository configuration**](#suse-repository-setup) (`--setup-repos`)
- [**Complete backup**](#create-a-backup) before migration with RPM capture, repos, packages
- [**Standalone interactive backup**](#backup-elements) (`--backup`): y/n choice per element
- [**Full restore**](#full-restore) to original OS
- [**Granular restore**](#granular-restore): repos, release packages, files, config
- [**Interactive restore**](#interactive-restore) (`--restore-select`): backup overview, backup selector, y/n choice per element
- [**Backup portability**](#list-export-import) (export/import as archive)
- [**Dry-run and interactive modes**](#dry-run-and-interactive-modes) to preview or confirm changes
- [**Detailed migration reports**](#complete-workflow)

### Supported Distributions

| Distribution | Version 7 | Version 8 | Version 9 |
|--------------|:---------:|:---------:|:---------:|
| Rocky Linux  | -         | ✓         | ✓         |
| AlmaLinux    | -         | ✓         | ✓         |
| Oracle Linux | ✓         | ✓         | ✓         |
| CentOS       | ✓         | ✓ (Stream)| ✓ (Stream)|
| RHEL         | ✓         | ✓         | ✓         |
| EuroLinux    | ✓         | ✓         | ✓         |

---

## Getting Started

### Prerequisites

- **Root privileges** required
- **dnf** or **yum** installed
- **Disk space**: minimum 100 MB for backups
- **SUSE repositories** (migration only): automatically configured via `--setup-repos`, or manually ([SUSE Documentation](https://www.suse.com/support/kb/doc/?id=000019587)). Not required for backup and restore operations (see [Usage Without SUSE Repositories](#usage-without-suse-repositories))

### Usage Without SUSE Repositories

The script can be partially used without SUSE repositories being configured. This allows preparing a system before repository access is available.

| Feature | Without SUSE repos | With SUSE repos |
|---|:---:|:---:|
| `--backup` (backup) | yes | yes |
| `--list-backups` | yes | yes |
| `--export-backup` / `--import-backup` | yes | yes |
| `--restore-select` / `--restore-*` | yes | yes |
| `--setup-repos` | yes (creates .repo files) | - |
| Migration (default command) | no | yes |
| `--reinstall-packages` | no | yes |
| Release RPM download in backup | no (list only) | yes |

> **Note**: without SUSE repositories, the backup cannot download original release RPMs (`rpms/` will remain empty). The package list will still be saved in `release-packages.list`, allowing manual restore later.

### Warnings

> **Important precautions before migration**

- **Test in a non-production environment** first
- **Ensure network connectivity** to SUSE repositories
- **Check available disk space** (minimum 100 MB)
- **Do not interrupt** the migration process once started
- **Create a full system backup** before migration (VM snapshot, backup, etc.)

### Installation

```bash
# Download the script
curl -O https://raw.githubusercontent.com/jniedergang/mls-liberate/master/liberate.sh

# Make executable
chmod +x liberate.sh
```

### Complete Workflow

```bash
# 1. Configure SUSE repositories
sudo ./liberate.sh --setup-repos

# 2. Perform migration
sudo ./liberate.sh --interactive --verbose

# 3. Verify migration
cat /etc/os-release
rpm -q sll-release

# 4. (Optional) If you need to restore
sudo ./liberate.sh --restore
```

---

## Migration

### Basic Migration

```bash
# Migration with automatic backup
sudo ./liberate.sh

# Migration with reinstallation of all packages
sudo ./liberate.sh --reinstall-packages

# Migration with SUSE logos
sudo ./liberate.sh --install-logos
```

### SUSE Repository Setup

```bash
# Automatic repository configuration (detects EL7/8/9)
sudo ./liberate.sh --setup-repos

# Force reconfiguration (overwrites existing repos)
sudo ./liberate.sh --setup-repos --force

# Preview configuration
sudo ./liberate.sh --setup-repos --dry-run -v
```

The script automatically configures:
- **EL9**: SUSE Liberty Linux (SLL) repos in `/etc/yum.repos.d/sll.repo`
- **EL7/8**: SLES Expanded Support repos in `/etc/yum.repos.d/sles_es.repo`

> **With SUSE Multi-Linux Manager (MLM)**: if SLL repos are already configured via MLM (`susemanager:channels.repo`), create an empty `/etc/yum.repos.d/sll.repo` file (comment only) so the script detects existing repos. The `--repo-url` option is not needed.
> The default URL (`repo.suse.de`) is an internal SUSE mirror not publicly accessible.

### Dry-run and Interactive Modes

```bash
# Preview all actions without making changes
sudo ./liberate.sh --dry-run --verbose

# Migration with confirmation at each step
sudo ./liberate.sh --interactive --verbose

# Combine both for full exploration
sudo ./liberate.sh --interactive --dry-run -v
```

- `--dry-run`: shows commands without executing them
- `--interactive`: asks for confirmation before each important action
- `--verbose` / `-v`: displays INFO messages and command output

---

## Backup

### Create a Backup

```bash
# Interactive backup (y/n per element)
sudo ./liberate.sh --backup -v

# Automatic backup (all elements, during migration)
sudo ./liberate.sh
```

During a standard migration, all elements are backed up automatically.
With `--backup`, each element can be included or excluded individually (y/n prompts).

### Backup Elements

| Element | Description | Content |
|---------|-------------|---------|
| Package list | Full `rpm -qa` of the system | `packages.list` |
| Repositories | `/etc/yum.repos.d/*.repo` files | `repos/` |
| Release files | `/etc/os-release`, `/etc/redhat-release`, etc. | `release-files/` |
| dnf/yum config | `/etc/dnf/dnf.conf`, `/etc/yum.conf`, `protected.d/` | `dnf-yum-config/` |
| Release RPMs | Original release packages (downloaded) | `rpms/` |
| Deleted files | Files that will be deleted during migration | `deleted-files/` |

The `metadata.json` file is always created and contains system metadata along with the list of elements actually backed up (`backed_up_elements`).

### Backup Structure

```
/var/lib/liberate/backups/<timestamp>/
├── rpms/                      # Release package RPMs
│   ├── rocky-release-*.rpm
│   └── SHA256SUMS
├── deleted-files/             # Files deleted during migration
│   ├── usr/share/redhat-release/
│   ├── usr/lib/os-release     # Symlink target for /etc/os-release
│   └── etc/dnf/protected.d/redhat-release.conf
├── repos/                     # .repo files
├── release-files/             # /etc/os-release, etc.
├── dnf-yum-config/            # dnf/yum configuration
├── packages.list              # List of all packages
├── release-packages.list      # List of release packages
├── release-packages-info.txt  # Detailed package info
├── deleted-files.manifest     # List of deleted files
└── metadata.json              # System metadata
```

### List, Export, Import

```bash
# List available backups
sudo ./liberate.sh --list-backups

# Export a backup (interactive selector)
sudo ./liberate.sh --export-backup

# Export a specific backup
sudo ./liberate.sh --export-backup latest

# Import a backup
sudo ./liberate.sh --import-backup liberate-backup-20240115_103045.tar.gz
```

---

## Restore

### Full Restore

```bash
# Full restore to original OS (uses latest backup)
sudo ./liberate.sh --restore

# Restore from a specific backup
sudo ./liberate.sh --restore 20240115_103045

# Partial restore (repos only)
sudo ./liberate.sh --rollback
```

### Minimal Restore

```bash
# Removes SUSE packages, restores deleted files + release package
sudo ./liberate.sh --restore-minimal
```

### Granular Restore

```bash
# Restore only repositories
sudo ./liberate.sh --restore-repos

# Restore only release packages (RPMs)
sudo ./liberate.sh --restore-release

# Restore only deleted files
sudo ./liberate.sh --restore-files

# Restore only dnf/yum configuration
sudo ./liberate.sh --restore-config

# Granular restore from a specific backup
sudo ./liberate.sh --restore-repos 20240115_103045
```

### Interactive Restore

```bash
# Backup selector + y/n per element
sudo ./liberate.sh --restore-select
```

Displays an overview of the selected backup (contents, sizes, system state), then prompts for each action individually. Empty elements are automatically skipped.

### Restore Notes

- SUSE repository files (`sll.repo`, `sles_es.repo`) present in the backup are **automatically filtered out** during restore to avoid RPM conflicts (obsoletes)
- `/usr/lib/os-release` (symlink target of `/etc/os-release`) is properly backed up and restored
- Restore order ensures SUSE packages are removed **before** reinstalling original release packages
- If SUSE repos (MLM, RMT) are still active, they are disabled during original package installation

### Restore Modes Comparison

| Mode | Removes SUSE | Restores repos | Restores deleted files | Restores release package | Restores config |
|------|:------------:|:--------------:|:----------------------:|:------------------------:|:---------------:|
| `--restore` | yes | yes | yes | yes | yes |
| `--restore-minimal` | yes | no | yes | yes | no |
| `--rollback` | no | yes | no | no | no |
| `--restore-repos` | no | yes | no | no | no |
| `--restore-release` | no | no | no | yes | no |
| `--restore-files` | no | no | yes | no | no |
| `--restore-config` | no | no | no | no | yes |
| `--restore-select` | choice | choice | choice | choice | choice |

---

## Reference

### Options

| Option | Description |
|--------|-------------|
| **Migration** | |
| `--reinstall-packages` | Reinstall all packages from SUSE repositories |
| `--install-logos` | Install SUSE logos/branding packages |
| `--setup-repos` | Automatically configure SUSE repositories |
| `--repo-url <url>` | Base URL for SUSE repos (default: https://repo.suse.de) |
| **Backup** | |
| `--backup` | Standalone interactive backup (y/n per element) |
| `--no-backup` | Disable automatic backup |
| `--backup-dir <path>` | Backup directory (default: /var/lib/liberate/backups) |
| `--list-backups` | List available backups |
| `--export-backup [name]` | Export a backup as archive (interactive selector if no name) |
| `--import-backup <file>` | Import a backup from archive |
| **Restore** | |
| `--restore [name]` | Full restore to original OS |
| `--restore-minimal [name]` | Minimal restore (removes SUSE + files + release package) |
| `--restore-repos [name]` | Restore only repositories |
| `--restore-release [name]` | Restore only release packages |
| `--restore-files [name]` | Restore only deleted files |
| `--restore-config [name]` | Restore only dnf/yum configuration |
| `--restore-select [name]` | Interactive restore (backup selector + y/n per element) |
| `--rollback` | Partial restore (repos only) |
| **General** | |
| `--interactive` | Interactive mode with confirmations |
| `--dry-run` | Show commands without executing them |
| `--force` | Force migration even if already liberated |
| `--report` | Generate detailed migration report |
| `--verbose, -v` | Show operation details |
| `--help, -h` | Show help |

### Files Created

| File | Description |
|------|-------------|
| `/etc/sysconfig/liberated` | Migration marker |
| `/var/log/liberate.log` | Main log |
| `/var/log/dnf_sll_migration.log` | Reinstall log (EL9) |
| `/var/log/yum_sles_es_migration.log` | Reinstall log (EL7/8) |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (check /var/log/liberate.log) |

---

## Troubleshooting

### Common Errors

| Error Message | Cause | Solution |
|---------------|-------|----------|
| `This script must be run as root` | Script run without root privileges | Run with `sudo ./liberate.sh` |
| `Unsupported distribution: xxx` | Distribution not supported | Check the list of supported distributions |
| `System already liberated` | Migration already performed | Use `--force` to re-run |
| `Insufficient disk space` | Not enough disk space | Free at least 100 MB |
| `SUSE repos not configured` | Missing SUSE repositories | Configure repositories before migration |
| `Backup not found` | Backup not found | Check with `--list-backups` |
| `Failed to download packages` | Network issue | Check connectivity to repositories |
| `Could not resolve host: repo.suse.de` | Default URL not accessible | Use `--repo-url` or configure repos via MLM/RMT |

### Troubleshooting Tips

1. **Check the logs**: `/var/log/liberate.log` contains details of all operations
2. **Verbose mode**: Use `--verbose` for more information
3. **Dry-run mode**: Use `--dry-run` to test without modifying the system
4. **Check repositories**: `dnf repolist` or `yum repolist` to verify configuration

---

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Authors

- Based on [SUSE liberate-formula](https://github.com/SUSE/liberate-formula)
- Shell script implementation with extended features
