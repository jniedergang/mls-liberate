# liberate.sh - Conversion Enterprise Linux vers SUSE Liberty Linux

**Version**: 1.3.1

[English version below](#english-version)

---

## Description

**liberate.sh** est un script shell qui automatise la conversion de distributions Enterprise Linux (Rocky, AlmaLinux, Oracle Linux, CentOS, RHEL, EuroLinux) vers **SUSE Liberty Linux** ou **SLES Expanded Support**.

Ce script est basé sur la [liberate-formula](https://github.com/SUSE/liberate-formula) Salt, avec des fonctionnalités étendues pour une meilleure gestion des sauvegardes et restaurations.

## Fonctionnalités

- **Détection automatique** de l'OS et de la version (7, 8, 9)
- **Configuration automatique des dépôts SUSE** (`--setup-repos`)
- **Sauvegarde complète** avant migration :
  - Capture des RPMs des paquets de release originaux
  - Configuration des dépôts
  - Liste de tous les paquets installés
- **Sauvegarde standalone interactive** (`--backup`) : choix y/n par élément
- **Restauration complète** vers l'OS original
- **Restauration granulaire** : repos, paquets release, fichiers, config
- **Restauration interactive** (`--restore-select`) : vue d'ensemble du backup, sélection du backup si multiples, choix y/n par élément
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
- **Dépôts SUSE** : configurés automatiquement via `--setup-repos`, ou manuellement ([Documentation SUSE](https://www.suse.com/support/kb/doc/?id=000019587))
- **Espace disque** : minimum 100 Mo pour les sauvegardes
- Connectivité réseau aux dépôts

## Avertissements

> ⚠️ **Précautions importantes avant migration**

- **Tester en environnement non-production** d'abord
- **S'assurer de la connectivité réseau** aux dépôts SUSE
- **Vérifier l'espace disque disponible** (minimum 100 Mo)
- **Ne pas interrompre** le processus de migration une fois démarré
- **Créer une sauvegarde système complète** avant la migration (snapshot VM, backup, etc.)

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

### Gestion des sauvegardes

```bash
# Sauvegarde interactive (choix y/n par élément)
sudo ./liberate.sh --backup -v

# Lister les sauvegardes disponibles
sudo ./liberate.sh --list-backups

# Exporter une sauvegarde (pour transfert vers un autre système)
sudo ./liberate.sh --export-backup latest

# Importer une sauvegarde
sudo ./liberate.sh --import-backup liberate-backup-20240115_103045.tar.gz
```

### Éléments sauvegardés

Lors d'une migration classique, tous les éléments sont sauvegardés automatiquement.
Avec `--backup`, chaque élément peut être inclus ou exclu individuellement (prompts y/n).

| Élément | Description | Contenu |
|---------|-------------|---------|
| Liste des paquets | `rpm -qa` complet du système | `packages.list` |
| Dépôts | Fichiers `/etc/yum.repos.d/*.repo` | `repos/` |
| Fichiers release | `/etc/os-release`, `/etc/redhat-release`, etc. | `release-files/` |
| Configuration dnf/yum | `/etc/dnf/dnf.conf`, `/etc/yum.conf`, `protected.d/` | `dnf-yum-config/` |
| RPMs release | Paquets release originaux (download) | `rpms/` |
| Fichiers supprimés | Fichiers qui seront supprimés lors de la migration | `deleted-files/` |

Le fichier `metadata.json` est toujours créé et contient les métadonnées du système ainsi que la liste des éléments effectivement sauvegardés (`backed_up_elements`).

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

# Mode interactif : sélection du backup + choix y/n par élément
sudo ./liberate.sh --restore-select

# Restauration granulaire depuis une sauvegarde spécifique
sudo ./liberate.sh --restore-repos 20240115_103045
```

### Comparaison des modes de restauration

| Mode | Supprime SUSE | Restaure repos | Restaure fichiers supprimés | Restaure paquet release | Restaure config |
|------|:-------------:|:--------------:|:---------------------------:|:-----------------------:|:---------------:|
| `--restore` | oui | oui | oui | oui | oui |
| `--restore-minimal` | non | non | oui | oui | non |
| `--rollback` | non | oui | non | non | non |
| `--restore-repos` | non | oui | non | non | non |
| `--restore-release` | non | non | non | oui | non |
| `--restore-files` | non | non | oui | non | non |
| `--restore-config` | non | non | non | non | oui |
| `--restore-select` | choix | choix | choix | choix | choix |

## Options

| Option | Description |
|--------|-------------|
| `--reinstall-packages` | Réinstalle tous les paquets depuis les dépôts SUSE |
| `--install-logos` | Installe les paquets de logos/branding SUSE |
| `--setup-repos` | Configure automatiquement les dépôts SUSE |
| `--dry-run` | Affiche les commandes sans les exécuter |
| `--backup` | Sauvegarde standalone interactive (choix y/n par élément) |
| `--no-backup` | Désactive la sauvegarde automatique |
| `--backup-dir <path>` | Répertoire de backup (défaut: /var/lib/liberate/backups) |
| `--list-backups` | Liste les sauvegardes disponibles |
| `--restore [name]` | Restauration complète vers l'OS original |
| `--restore-minimal [name]` | Restauration minimale (fichiers + paquet release) |
| `--restore-repos [name]` | Restaurer uniquement les dépôts |
| `--restore-release [name]` | Restaurer uniquement les paquets release |
| `--restore-files [name]` | Restaurer uniquement les fichiers supprimés |
| `--restore-config [name]` | Restaurer uniquement la configuration dnf/yum |
| `--restore-select [name]` | Restauration interactive (sélection backup + y/n par élément) |
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

## Codes de sortie

| Code | Signification |
|------|---------------|
| 0 | Succès |
| 1 | Erreur (consulter /var/log/liberate.log) |

## Troubleshooting

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

### Conseils de dépannage

1. **Consulter les logs** : `/var/log/liberate.log` contient les détails de toutes les opérations
2. **Mode verbose** : Utiliser `--verbose` pour obtenir plus d'informations
3. **Mode dry-run** : Utiliser `--dry-run` pour tester sans modifier le système
4. **Vérifier les dépôts** : `dnf repolist` ou `yum repolist` pour vérifier la configuration

## Exemple de workflow complet

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

## Licence

MIT License

---

# English Version

**Version**: 1.3.1

---

## Description

**liberate.sh** is a shell script that automates the conversion of Enterprise Linux distributions (Rocky, AlmaLinux, Oracle Linux, CentOS, RHEL, EuroLinux) to **SUSE Liberty Linux** or **SLES Expanded Support**.

This script is based on the [liberate-formula](https://github.com/SUSE/liberate-formula) Salt formula, with extended features for better backup and restore management.

## Features

- **Automatic detection** of OS and version (7, 8, 9)
- **Automatic SUSE repository configuration** (`--setup-repos`)
- **Complete backup** before migration:
  - Captures original release package RPMs
  - Repository configuration
  - List of all installed packages
- **Standalone interactive backup** (`--backup`): y/n choice per element
- **Full restore** to original OS
- **Granular restore**: repos, release packages, files, config
- **Interactive restore** (`--restore-select`): backup overview, backup selector if multiple, y/n choice per element
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
- **SUSE repositories**: automatically configured via `--setup-repos`, or manually ([SUSE Documentation](https://www.suse.com/support/kb/doc/?id=000019587))
- **Disk space**: minimum 100 MB for backups
- Network connectivity to repositories

## Warnings

> ⚠️ **Important precautions before migration**

- **Test in a non-production environment** first
- **Ensure network connectivity** to SUSE repositories
- **Check available disk space** (minimum 100 MB)
- **Do not interrupt** the migration process once started
- **Create a full system backup** before migration (VM snapshot, backup, etc.)

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
# Interactive backup (y/n per element)
sudo ./liberate.sh --backup -v

# List available backups
sudo ./liberate.sh --list-backups

# Export a backup (for transfer to another system)
sudo ./liberate.sh --export-backup latest

# Import a backup
sudo ./liberate.sh --import-backup liberate-backup-20240115_103045.tar.gz
```

### Backup Elements

During a standard migration, all elements are backed up automatically.
With `--backup`, each element can be included or excluded individually (y/n prompts).

| Element | Description | Content |
|---------|-------------|---------|
| Package list | Full `rpm -qa` of the system | `packages.list` |
| Repositories | `/etc/yum.repos.d/*.repo` files | `repos/` |
| Release files | `/etc/os-release`, `/etc/redhat-release`, etc. | `release-files/` |
| dnf/yum config | `/etc/dnf/dnf.conf`, `/etc/yum.conf`, `protected.d/` | `dnf-yum-config/` |
| Release RPMs | Original release packages (downloaded) | `rpms/` |
| Deleted files | Files that will be deleted during migration | `deleted-files/` |

The `metadata.json` file is always created and contains system metadata along with the list of elements actually backed up (`backed_up_elements`).

### SUSE Repository Setup

```bash
# Automatic repository configuration (detects EL7/8/9)
sudo ./liberate.sh --setup-repos

# Force reconfiguration (overwrites existing repos)
sudo ./liberate.sh --setup-repos --force

# Preview configuration
sudo ./liberate.sh --setup-repos --dry-run -v
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

# Interactive mode: backup selector + y/n per element
sudo ./liberate.sh --restore-select

# Granular restore from a specific backup
sudo ./liberate.sh --restore-repos 20240115_103045
```

### Restore Modes Comparison

| Mode | Removes SUSE | Restores repos | Restores deleted files | Restores release package | Restores config |
|------|:------------:|:--------------:|:----------------------:|:------------------------:|:---------------:|
| `--restore` | yes | yes | yes | yes | yes |
| `--restore-minimal` | no | no | yes | yes | no |
| `--rollback` | no | yes | no | no | no |
| `--restore-repos` | no | yes | no | no | no |
| `--restore-release` | no | no | no | yes | no |
| `--restore-files` | no | no | yes | no | no |
| `--restore-config` | no | no | no | no | yes |
| `--restore-select` | choice | choice | choice | choice | choice |

## Options

| Option | Description |
|--------|-------------|
| `--reinstall-packages` | Reinstall all packages from SUSE repositories |
| `--install-logos` | Install SUSE logos/branding packages |
| `--setup-repos` | Automatically configure SUSE repositories |
| `--dry-run` | Show commands without executing them |
| `--backup` | Standalone interactive backup (y/n per element) |
| `--no-backup` | Disable automatic backup |
| `--backup-dir <path>` | Backup directory (default: /var/lib/liberate/backups) |
| `--list-backups` | List available backups |
| `--restore [name]` | Full restore to original OS |
| `--restore-minimal [name]` | Minimal restore (files + release package) |
| `--restore-repos [name]` | Restore only repositories |
| `--restore-release [name]` | Restore only release packages |
| `--restore-files [name]` | Restore only deleted files |
| `--restore-config [name]` | Restore only dnf/yum configuration |
| `--restore-select [name]` | Interactive restore (backup selector + y/n per element) |
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

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (check /var/log/liberate.log) |

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

### Troubleshooting Tips

1. **Check the logs**: `/var/log/liberate.log` contains details of all operations
2. **Verbose mode**: Use `--verbose` for more information
3. **Dry-run mode**: Use `--dry-run` to test without modifying the system
4. **Check repositories**: `dnf repolist` or `yum repolist` to verify configuration

## Complete Workflow Example

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

## License

MIT License

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Authors

- Based on [SUSE liberate-formula](https://github.com/SUSE/liberate-formula)
- Shell script implementation with extended features
