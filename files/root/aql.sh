#!/bin/sh

argc() { argc=$#; }

# System default values (as extracted previously)
system_default_aql_txq_limit_low=1500
system_default_aql_txq_limit_high=5000
system_default_aql_threshold=12000
system_default_fq_limit=8192
system_default_fq_quantum=300
system_default_fq_memory_limit=33554432

# Script default values (for manual adjustments)
script_default_aql_txq_limit_low=1500
script_default_aql_txq_limit_high=5000
script_default_aql_threshold=12000
script_default_fq_limit=10240
script_default_fq_quantum=256
script_default_fq_memory_limit=33554432

# Function to display usage dynamically based on defaults
usage() {
  echo "Usage: $0 [reset | AQL_LOW [AQL_HIGH] [AQL_THRESHOLD] [FQ_LIMIT] [FQ_QUANTUM] [FQ_MEMORY_LIMIT]]"
  echo
  echo "Arguments:"
  echo "  reset             : Reset all values to system defaults."
  echo "  AQL_LOW           : AQL low value (e.g., 'latency', 'balanced', 'bandwidth', or an integer)."
  echo "                      Default: ${script_default_aql_txq_limit_low}."
  echo "  AQL_HIGH          : AQL high value (optional, defaults to AQL_LOW)."
  echo "                      Default: ${script_default_aql_txq_limit_high}."
  echo "  AQL_THRESHOLD     : AQL threshold (optional)."
  echo "                      Default: ${script_default_aql_threshold}."
  echo "  FQ_LIMIT          : FQ-CoDel limit (optional). Size of all queues managed by FQ_CoDel instance. It is the hard limit on the real queue size in packets."
  echo "                      Default: ${script_default_fq_limit}."
  echo "  FQ_QUANTUM        : FQ-CoDel quantum (optional). Maximum number of bytes to dequeue for transmission at one time."
  echo "                      Default: ${script_default_fq_quantum}."
  echo "  FQ_MEMORY_LIMIT   : FQ-CoDel memory limit (optional)."
  echo "                      Default: ${script_default_fq_memory_limit}."
  echo
}

# Show current values for all PHY interfaces
show_current_values() {
  for phy in /sys/kernel/debug/ieee80211/phy*; do
    echo "Current configuration for $phy:"
    pre_fq_quantum=$(grep 'fq_quantum' "$phy/aqm" | awk '/fq_quantum/ {print $3}')
    pre_aql_low=$(awk 'NR > 1 && $1 == "VO" {print $2}' "$phy/aql_txq_limit")
    pre_aql_high=$(awk 'NR > 1 && $1 == "VO" {print $3}' "$phy/aql_txq_limit")
    pre_aql_threshold=$(cat "$phy/aql_threshold" 2>/dev/null || echo "N/A")
    pre_fq_limit=$(grep 'fq_limit' "$phy/aqm" | awk '{print $3}')
    pre_fq_memory_limit=$(grep 'fq_memory_limit' "$phy/aqm" | awk '{print $3}')

    echo "  AQL TXQ Low: ${pre_aql_low:-N/A}"
    echo "  AQL TXQ High: ${pre_aql_high:-N/A}"
    echo "  AQL Threshold: ${pre_aql_threshold:-N/A}"
    echo "  FQ Limit: ${pre_fq_limit:-N/A}"
    echo "  FQ Quantum: ${pre_fq_quantum:-N/A}"
    echo "  FQ Memory Limit: ${pre_fq_memory_limit:-N/A}"
    echo
  done
}

# Compare and show changes
show_changes() {
  local phy="$1"

  post_fq_quantum=$(grep 'fq_quantum' "$phy/aqm" | awk '/fq_quantum/ {print $3}')
  post_aql_low=$(awk 'NR > 1 && $1 == "VO" {print $2}' "$phy/aql_txq_limit")
  post_aql_high=$(awk 'NR > 1 && $1 == "VO" {print $3}' "$phy/aql_txq_limit")
  post_aql_threshold=$(cat "$phy/aql_threshold" 2>/dev/null || echo "N/A")
  post_fq_limit=$(grep 'fq_limit' "$phy/aqm" | awk '{print $3}')
  post_fq_memory_limit=$(grep 'fq_memory_limit' "$phy/aqm" | awk '{print $3}')

  # Show only changed values
  echo "Changes for $phy:"
  [ "$pre_aql_low" != "$post_aql_low" ] && echo "  AQL TXQ Low: $pre_aql_low -> $post_aql_low"
  [ "$pre_aql_high" != "$post_aql_high" ] && echo "  AQL TXQ High: $pre_aql_high -> $post_aql_high"
  [ "$pre_aql_threshold" != "$post_aql_threshold" ] && echo "  AQL Threshold: $pre_aql_threshold -> $post_aql_threshold"
  [ "$pre_fq_limit" != "$post_fq_limit" ] && echo "  FQ Limit: $pre_fq_limit -> $post_fq_limit"
  [ "$pre_fq_quantum" != "$post_fq_quantum" ] && echo "  FQ Quantum: $pre_fq_quantum -> $post_fq_quantum"
  [ "$pre_fq_memory_limit" != "$post_fq_memory_limit" ] && echo "  FQ Memory Limit: $pre_fq_memory_limit -> $post_fq_memory_limit"
}

# Ensure at least one argument is provided or show current values
if [ "$#" -eq 0 ]; then
  usage
  echo "No parameters provided. Displaying current configuration values for all PHY interfaces..."
  echo
  show_current_values
  exit 0
fi

# Handle reset argument
if [ "$1" = "reset" ]; then
  echo "Resetting all values to system defaults..."
  for phy in /sys/kernel/debug/ieee80211/phy*; do
    (
      cd "$phy" || exit

      # Apply system default AQL values
      for ac in 0 1 2 3; do
        echo "$ac $system_default_aql_txq_limit_low $system_default_aql_txq_limit_high" > "$phy/aql_txq_limit"
      done
      echo "$system_default_aql_threshold" > "$phy/aql_threshold"

      # Apply system default FQ-CoDel values
      echo "fq_limit $system_default_fq_limit" > "$phy/aqm"
      echo "fq_quantum $system_default_fq_quantum" > "$phy/aqm"
      echo "fq_memory_limit $system_default_fq_memory_limit" > "$phy/aqm"
    )
  done
  echo "Reset completed to system defaults."
  exit 0
fi

# Function to resolve AQL values
resolve_aql_value() {
  case $(echo "$1" | awk '{print tolower($0)}') in
    latency) echo 1500 ;;
    balanced) echo 5000 ;;
    bandwidth) echo 15000 ;;
    *)
      if [ "$1" -eq "$1" ] 2>/dev/null; then
        echo "$1"
      else
        echo "Error: Invalid AQL preference '$1'. Enter 'latency', 'balanced', 'bandwidth', or an integer value." >&2
        exit 1
      fi
      ;;
  esac
}

# Resolve AQL low and high values
aql_txq_limit_low=$(resolve_aql_value "$1")
aql_txq_limit_high=${2:-$aql_txq_limit_low}

# Set optional parameters with defaults
aql_threshold=${3:-$script_default_aql_threshold}
fq_limit=${4:-$script_default_fq_limit}
fq_quantum=${5:-$script_default_fq_quantum}
fq_memory_limit=${6:-$script_default_fq_memory_limit}

# Apply settings and track changes
for phy in /sys/kernel/debug/ieee80211/phy*; do
  pre_fq_quantum=$(grep 'fq_quantum' "$phy/aqm" | awk '/fq_quantum/ {print $3}')
  pre_aql_low=$(awk 'NR > 1 && $1 == "VO" {print $2}' "$phy/aql_txq_limit")
  pre_aql_high=$(awk 'NR > 1 && $1 == "VO" {print $3}' "$phy/aql_txq_limit")
  pre_aql_threshold=$(cat "$phy/aql_threshold" 2>/dev/null || echo "N/A")
  pre_fq_limit=$(grep 'fq_limit' "$phy/aqm" | awk '{print $3}')
  pre_fq_memory_limit=$(grep 'fq_memory_limit' "$phy/aqm" | awk '{print $3}')

  # Apply new settings
  (
    cd "$phy" || exit
    for ac in 0 1 2 3; do
      echo "$ac $aql_txq_limit_low $aql_txq_limit_high" > "$phy/aql_txq_limit"
    done
    echo "$aql_threshold" > "$phy/aql_threshold"
    echo "fq_limit $fq_limit" > "$phy/aqm"
    echo "fq_quantum $fq_quantum" > "$phy/aqm"
    echo "fq_memory_limit $fq_memory_limit" > "$phy/aqm"
  )

  # Show changes
  show_changes "$phy"
done

echo "Configuration applied to all PHY interfaces."