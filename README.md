# liberate.sh - Conversion Enterprise Linux vers SUSE Liberty Linux

[English version below](#english-version)

---

## Description

**liberate.sh** est un script shell qui automatise la conversion de distributions Enterprise Linux (Rocky, AlmaLinux, Oracle Linux, CentOS, RHEL, EuroLinux) vers **SUSE Liberty Linux** ou **SLES Expanded Support**.

Ce script est basé sur la [liberate-formula](https://github.com/SUSE/liberate-formula) Salt, avec des fonctionnalités étendues pour une meilleure gestion des sauvegardes et restaurations.

## Fonctionnalités

- **Détection automatique** de l'OS et de la version (7, 8, 9)
- **Sauvegarde complète** avant migration :
  - Capture des RPMs des paquets de release originaux
  - Configuration des dépôts
  - Liste de tous les paquets installés
- **Restauration complète** vers l'OS original
- **Portabilité des backups** (export/import en archive)
- **Mode dry-run** pour prévisualiser les changements
- **Mode interactif** avec confirmations
- **Rapports de migration** détaillés

## Distributions supportées

| Distribution | Version 7 | Version 8 | Version 9 |
|--------------|:---------:|:---------:|:---------:|
| Rocky Linux  | -         | ✓         | ✓         |
| AlmaLinux    | -         | ✓         | ✓         |
| Oracle Linux | ✓         | ✓         | ✓         |
| CentOS       | ✓         | ✓ (Stream)| ✓ (Stream)|
| RHEL         | ✓         | ✓         | ✓         |
| EuroLinux    | ✓         | ✓         | ✓         |

## Prérequis

- **Droits root** requis
- **Dépôts SUSE** configurés avant l'exécution
- **Espace disque** : minimum 100 Mo pour les sauvegardes
- Connectivité réseau aux dépôts

## Installation

```bash
# Télécharger le script
curl -O https://raw.githubusercontent.com/jniedergang/mls-liberate/master/liberate.sh

# Rendre exécutable
chmod +x liberate.sh
```

## Utilisation

### Migration basique

```bash
# Migration avec sauvegarde automatique
sudo ./liberate.sh

# Migration avec réinstallation de tous les paquets
sudo ./liberate.sh --reinstall-packages

# Migration avec logos SUSE
sudo ./liberate.sh --install-logos

# Prévisualiser sans exécuter
sudo ./liberate.sh --dry-run --verbose
```

### Gestion des sauvegardes

```bash
# Lister les sauvegardes disponibles
sudo ./liberate.sh --list-backups

# Exporter une sauvegarde (pour transfert vers un autre système)
sudo ./liberate.sh --export-backup latest

# Importer une sauvegarde
sudo ./liberate.sh --import-backup liberate-backup-20240115_103045.tar.gz
```

### Restauration

```bash
# Restauration complète vers l'OS original (utilise la dernière sauvegarde)
sudo ./liberate.sh --restore

# Restauration minimale (fichiers supprimés + paquet release uniquement)
# Ne supprime PAS les paquets SUSE
sudo ./liberate.sh --restore-minimal

# Restauration depuis une sauvegarde spécifique
sudo ./liberate.sh --restore 20240115_103045

# Restauration partielle (repos uniquement)
sudo ./liberate.sh --rollback
```

## Options

| Option | Description |
|--------|-------------|
| `--reinstall-packages` | Réinstalle tous les paquets depuis les dépôts SUSE |
| `--install-logos` | Installe les paquets de logos/branding SUSE |
| `--dry-run` | Affiche les commandes sans les exécuter |
| `--no-backup` | Désactive la sauvegarde automatique |
| `--backup-dir <path>` | Répertoire de backup (défaut: /var/lib/liberate/backups) |
| `--list-backups` | Liste les sauvegardes disponibles |
| `--restore [name]` | Restauration complète vers l'OS original |
| `--restore-minimal [name]` | Restauration minimale (fichiers + paquet release) |
| `--rollback` | Restauration partielle (repos uniquement) |
| `--export-backup <name>` | Exporte une sauvegarde en archive |
| `--import-backup <file>` | Importe une sauvegarde depuis une archive |
| `--interactive` | Mode interactif avec confirmations |
| `--force` | Force la migration même si déjà libéré |
| `--report` | Génère un rapport de migration détaillé |
| `--verbose, -v` | Affiche les détails des opérations |
| `--help, -h` | Affiche l'aide |

## Structure des sauvegardes

```
/var/lib/liberate/backups/<timestamp>/
├── rpms/                      # RPMs des paquets de release
│   ├── rocky-release-*.rpm
│   └── SHA256SUMS
├── deleted-files/             # Fichiers supprimés lors de la migration
│   ├── usr/share/redhat-release/
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

## Fichiers créés

| Fichier | Description |
|---------|-------------|
| `/etc/sysconfig/liberated` | Marqueur de migration |
| `/var/log/liberate.log` | Log principal |
| `/var/log/dnf_sll_migration.log` | Log de réinstallation (EL9) |
| `/var/log/yum_sles_es_migration.log` | Log de réinstallation (EL7/8) |

## Exemple de workflow complet

```bash
# 1. Configurer les dépôts SUSE (non géré par ce script)
# ... configuration des repos SUSE ...

# 2. Effectuer la migration
sudo ./liberate.sh --interactive --verbose

# 3. Vérifier la migration
cat /etc/os-release
rpm -q sll-release

# 4. (Optionnel) Si besoin de restaurer
sudo ./liberate.sh --restore
```

## Licence

MIT License

---

# English Version

---

## Description

**liberate.sh** is a shell script that automates the conversion of Enterprise Linux distributions (Rocky, AlmaLinux, Oracle Linux, CentOS, RHEL, EuroLinux) to **SUSE Liberty Linux** or **SLES Expanded Support**.

This script is based on the [liberate-formula](https://github.com/SUSE/liberate-formula) Salt formula, with extended features for better backup and restore management.

## Features

- **Automatic detection** of OS and version (7, 8, 9)
- **Complete backup** before migration:
  - Captures original release package RPMs
  - Repository configuration
  - List of all installed packages
- **Full restore** to original OS
- **Backup portability** (export/import as archive)
- **Dry-run mode** to preview changes
- **Interactive mode** with confirmations
- **Detailed migration reports**

## Supported Distributions

| Distribution | Version 7 | Version 8 | Version 9 |
|--------------|:---------:|:---------:|:---------:|
| Rocky Linux  | -         | ✓         | ✓         |
| AlmaLinux    | -         | ✓         | ✓         |
| Oracle Linux | ✓         | ✓         | ✓         |
| CentOS       | ✓         | ✓ (Stream)| ✓ (Stream)|
| RHEL         | ✓         | ✓         | ✓         |
| EuroLinux    | ✓         | ✓         | ✓         |

## Prerequisites

- **Root privileges** required
- **SUSE repositories** must be configured before running
- **Disk space**: minimum 100 MB for backups
- Network connectivity to repositories

## Installation

```bash
# Download the script
curl -O https://raw.githubusercontent.com/jniedergang/mls-liberate/master/liberate.sh

# Make executable
chmod +x liberate.sh
```

## Usage

### Basic Migration

```bash
# Migration with automatic backup
sudo ./liberate.sh

# Migration with reinstallation of all packages
sudo ./liberate.sh --reinstall-packages

# Migration with SUSE logos
sudo ./liberate.sh --install-logos

# Preview without executing
sudo ./liberate.sh --dry-run --verbose
```

### Backup Management

```bash
# List available backups
sudo ./liberate.sh --list-backups

# Export a backup (for transfer to another system)
sudo ./liberate.sh --export-backup latest

# Import a backup
sudo ./liberate.sh --import-backup liberate-backup-20240115_103045.tar.gz
```

### Restore

```bash
# Full restore to original OS (uses latest backup)
sudo ./liberate.sh --restore

# Minimal restore (deleted files + release package only)
# Does NOT remove SUSE packages
sudo ./liberate.sh --restore-minimal

# Restore from a specific backup
sudo ./liberate.sh --restore 20240115_103045

# Partial restore (repos only)
sudo ./liberate.sh --rollback
```

## Options

| Option | Description |
|--------|-------------|
| `--reinstall-packages` | Reinstall all packages from SUSE repositories |
| `--install-logos` | Install SUSE logos/branding packages |
| `--dry-run` | Show commands without executing them |
| `--no-backup` | Disable automatic backup |
| `--backup-dir <path>` | Backup directory (default: /var/lib/liberate/backups) |
| `--list-backups` | List available backups |
| `--restore [name]` | Full restore to original OS |
| `--restore-minimal [name]` | Minimal restore (files + release package) |
| `--rollback` | Partial restore (repos only) |
| `--export-backup <name>` | Export a backup as archive |
| `--import-backup <file>` | Import a backup from archive |
| `--interactive` | Interactive mode with confirmations |
| `--force` | Force migration even if already liberated |
| `--report` | Generate detailed migration report |
| `--verbose, -v` | Show operation details |
| `--help, -h` | Show help |

## Backup Structure

```
/var/lib/liberate/backups/<timestamp>/
├── rpms/                      # Release package RPMs
│   ├── rocky-release-*.rpm
│   └── SHA256SUMS
├── deleted-files/             # Files deleted during migration
│   ├── usr/share/redhat-release/
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

## Files Created

| File | Description |
|------|-------------|
| `/etc/sysconfig/liberated` | Migration marker |
| `/var/log/liberate.log` | Main log |
| `/var/log/dnf_sll_migration.log` | Reinstall log (EL9) |
| `/var/log/yum_sles_es_migration.log` | Reinstall log (EL7/8) |

## Complete Workflow Example

```bash
# 1. Configure SUSE repositories (not managed by this script)
# ... SUSE repo configuration ...

# 2. Perform migration
sudo ./liberate.sh --interactive --verbose

# 3. Verify migration
cat /etc/os-release
rpm -q sll-release

# 4. (Optional) If you need to restore
sudo ./liberate.sh --restore
```

## License

MIT License

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Authors

- Based on [SUSE liberate-formula](https://github.com/SUSE/liberate-formula)
- Shell script implementation with extended features
