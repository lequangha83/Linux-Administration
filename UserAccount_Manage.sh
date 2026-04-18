#!/bin/bash

# Ensure script is run as root
if [[ "${EUID}" -ne 0 ]]; then
  echo "[-] Please run this script as root (e.g., sudo ./manage_user.sh)"
  exit 1
fi

# Prompt for username
read -p "Enter the username to manage: " USERNAME

# Check if the user exists
if ! id "$USERNAME" &>/dev/null; then
  echo "[-] User '$USERNAME' does not exist on this system!"
  exit 1
fi

echo "--------------------------------------------------"
# 1. Check if the user is locked
SYS_STATUS=$(passwd -S "$USERNAME" | awk '{print $2}')

if [[ "$SYS_STATUS" == "L" || "$SYS_STATUS" == "LK" ]]; then
  echo "[-] Status: User '$USERNAME' is currently LOCKED."
  
  # 2. Proceed to unlock
  echo "[+] Proceeding to unlock the user account..."
  usermod -U "$USERNAME"
  
  # Check status again after unlocking
  NEW_STATUS=$(passwd -S "$USERNAME" | awk '{print $2}')
  if [[ "$NEW_STATUS" == "P" || "$NEW_STATUS" == "PS" || "$NEW_STATUS" == "NP" ]]; then
    echo "[+] User unlocked successfully!"
  else
    echo "[-] Unlock process might have failed. Please check manually."
  fi
else
  echo "[+] Status: User '$USERNAME' is NOT locked."
fi
echo "--------------------------------------------------"

# 3. Check if the user is a service account -> Popup
if command -v whiptail &> /dev/null; then
  if whiptail --title "Account Classification" --yesno "Is '$USERNAME' a Service Account?" 10 60; then
    IS_SERVICE="yes"
  else
    IS_SERVICE="no"
  fi
else
  read -p "[?] Is '$USERNAME' a Service Account? (yes/no): " IS_SERVICE
fi

echo "--------------------------------------------------"
if [[ "$IS_SERVICE" == "yes" || "$IS_SERVICE" == "y" ]]; then
  
  # 4. Handle Service Account Focus
  echo "[!] Confirmed: SERVICE ACCOUNT"
  read -s -p "Enter reset password for the Service Account: " NEW_PASS
  echo
  
  # Change password securely via chpasswd
  echo "$USERNAME:$NEW_PASS" | chpasswd
  
  # Configure "never expire" using 'chage':
  echo "[+] Configuring 'Never Expire' password settings..."
  chage -m 0 -M 99999 -I -1 -E -1 "$USERNAME"
  echo "[+] Reset password and 'Never Expire' settings applied successfully."

elif [[ "$IS_SERVICE" == "no" || "$IS_SERVICE" == "n" ]]; then
  
  # 5. Handle Normal Account Focus
  echo "[!] Confirmed: NORMAL ACCOUNT"
  read -s -p "Enter new password for the Normal Account: " NEW_PASS
  echo
  
  # Change password securely
  echo "$USERNAME:$NEW_PASS" | chpasswd
  echo "[+] Password changed successfully for the normal account."
  
  # Configure to expire in 90 days (-M 90) and warn continuously 14 days prior (-W 14)
  echo "[+] Configuring password expiration: 90 days max, 14 days warning..."
  chage -M 90 -W 14 "$USERNAME"
  echo "[+] Expiration configuration applied successfully."
  
  # Define root automatic notification script
  ROOT_NOTIFIER="/etc/profile.d/check_expiring_users.sh"
  
  # Automatically inject login notification hook for root users (If not already created)
  if [ ! -f "$ROOT_NOTIFIER" ]; then
    echo "[+] Creating root notification hook at $ROOT_NOTIFIER..."
    cat << 'EOF' > "$ROOT_NOTIFIER"
#!/bin/bash
# Only display warning if the current logged in user is ROOT
if [[ "${EUID}" -eq 0 && -x /usr/bin/chage ]]; then
  expiring_users=0
  output_msg=""
  
  # Fetch all standard interactive users (usually UID >= 1000)
  for u in $(getent passwd | awk -F: '$3 >= 1000 && $3 != 65534 {print $1}'); do
    EXP_DATE=$(LANG=C chage -l "$u" | grep -i "password expires" | cut -d: -f2 | xargs)
    
    if [[ "$EXP_DATE" != "never" && -n "$EXP_DATE" ]]; then
      EXP_SECS=$(date -d "$EXP_DATE" +%s 2>/dev/null)
      if [[ $? -eq 0 ]]; then
        NOW_SECS=$(date +%s)
        DIFF_DAYS=$(( (EXP_SECS - NOW_SECS) / 86400 ))
        
        # Check if expiration is within 14 days
        if [[ $DIFF_DAYS -le 14 && $DIFF_DAYS -ge 0 ]]; then
          output_msg="$output_msg- User '$u' expires in $DIFF_DAYS days ($EXP_DATE)\n"
          ((expiring_users++))
        elif [[ $DIFF_DAYS -lt 0 ]]; then
          output_msg="$output_msg- User '$u' HAS EXPIRED!\n"
          ((expiring_users++))
        fi
      fi
    fi
  done
  
  # Print the red alert if there's any user hitting the 14-day mark
  if [[ $expiring_users -gt 0 ]]; then
    echo -e "\e[1;31m==================================================\e[0m"
    echo -e "\e[1;31m[!] ROOT NOTIFICATION: EXPIRING ACCOUNTS DETECTED\e[0m"
    echo -e "$output_msg"
    echo -e "\e[1;31m==================================================\e[0m"
  fi
fi
EOF
    chmod +x "$ROOT_NOTIFIER"
  fi

else
  echo "[-] Invalid response. Exiting program."
  exit 1
fi
echo "--------------------------------------------------"

# 6. Check expiration info using chage -l
echo "[!] SECURITY / EXPIRATION STATUS for user '$USERNAME':"
chage -l "$USERNAME"
echo "--------------------------------------------------"