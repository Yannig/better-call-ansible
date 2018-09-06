#!/bin/bash
# Par défaut, lancement de ansible-playbook
ANSIBLE_CMD=${ANSIBLE_CMD:-ansible-playbook}

function usage {
    echo "Usage: $(basename $0) INVENTORY_PATH PLAYBOOK_PATH ANSIBLE_ARGS"
    echo
    echo "INVENTORY     : Path to the ansible inventory"
    echo "PLAYBOOK_PATH : Path to the ansible playbook"
    echo "ANSIBLE_ARGS  : additional argument for the ansible command"
    echo "                (ex: -e app_name=efluid -u <some_user>)"
}

[ $# -lt 2 ] && usage && exit 1

if ${BETTER_DEBUG:-false}; then echo "$0 $@" ; fi

inventory=$1
shift

# Recuperation variables depuis le chemin de l'inventaire
bunker="$(echo "$inventory" | awk -F/ '{ print $1 }')"
cible="$(echo "$inventory" | awk -F/ '{ print $2 }')"
env_type="$(echo "$inventory" | awk -F/ '{ print $3 }')"
env_name="$(basename "$inventory" '.yml')"
# Verification que les variables sont correcte.
for elt in bunker cible env_type env_name
do
  eval "tmp=\$$elt"
  if [ -z "$tmp" ]; then
    echo "$elt est vide. Nom d'inventaire invalide."
    exit 1
  fi
done

# Recuperation emplacement de travail + positionnement dans le répertoire du script
shell_dir="$(dirname $0)"
shell_dir="$(cd "$shell_dir" && pwd)/"
cd "$shell_dir"
current_dir=$shell_dir

# Verification des paramétres
if [ ! -f "$inventory" ]; then
  if [ -d "$inventory" ]; then
    ${current_dir}/prop2inv.sh "$inventory" "$@"
    exit $?
  fi
  echo "Inventaire introuvable" ; exit 1
fi

inventory_path="$(dirname $inventory)"
inventory_path="$(cd $inventory_path && pwd)"
if [ $? -gt 0 ]; then echo "Erreur d'accès à l'inventaire." ; exit 1 ; fi

default_vars="-e bunker=$bunker -e cible=$cible -e env_type=$env_type -e env_name=$env_name -e env_path=$inventory -e current_dir=$inventory_path"

# Gestion du chiffrement des variables + inventaires multiple
vault_key=""
inventories_options=""
for path in "." $(echo $inventory | sed 's|/| |g')
do
  current_dir="$current_dir/$path"
  if [ -d "$current_dir" ]; then current_dir="$(cd "$current_dir" && pwd)" ; fi
  # Présence d'un fichier key pour ansible vault ?
  if [ -f $current_dir/vault.key ]; then vault_key="$current_dir/vault.key" ; fi
  if [ -f $current_dir/tpl.env.yml ]; then inventories_options="$inventories_options -e @$current_dir/tpl.env.yml" ; fi
done
inventories_options="$inventories_options -i $shell_dir/$bunker/tpl.yml"
inventories_options="$inventories_options -i $shell_dir/$bunker/$cible/tpl.yml"
inventories_options="$inventories_options -i $inventory"
if [ -f "$inventory_path/$env_name.env.yml" ]; then
  inventories_options="$inventories_options -e @$inventory_path/$env_name.env.yml"
fi

# Gestion du chiffrement des mots de passe
ansible_vault_file_options=""
ansible_vault_vault_file_options=""
if [ -f "$inventory.vault.yml" ]; then
  if [ -z "$vault_key" ]; then echo "Erreur : fichier vault présent mais pas de fichier vault.key." ; exit 1 ; fi
  ansible_vault_file_options="--vault-password-file=$vault_key"
  ansible_vault_vault_file_options="-e @$inventory.vault.yml"
fi

set -x
$ANSIBLE_CMD $default_vars $inventories_options $@ $ansible_vault_file_options $ansible_vault_vault_file_options
