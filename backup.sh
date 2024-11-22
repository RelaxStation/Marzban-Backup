#!/bin/bash

# Bot token
# Prompting the user for the bot token and storing it in variable tk
echo "Version 0.1.3"
while [[ -z "$tk" ]]; do
    echo "Bot token: "
    read -r tk
    if [[ $tk == $'\0' ]]; then
        echo "Invalid input. Token cannot be empty."
        unset tk
    fi
done

# Chat id
# Prompting the user for the Chat ID and storing it in variable chatid
while [[ -z "$chatid" ]]; do
    echo "Chat id: "
    read -r chatid
    if [[ $chatid == $'\0' ]]; then
        echo "Invalid input. Chat id cannot be empty."
        unset chatid
    elif [[ ! $chatid =~ ^\-?[0-9]+$ ]]; then
        echo "${chatid} is not a number."
        unset chatid
    fi
done

# Caption
# Prompting the user for a caption for the backup file and storing it in variable caption
echo "Caption (for example, your domain, to identify the database file more easily): "
read -r caption

# Cronjob
# Setting up a schedule to run this script periodically
while true; do
    echo "Cronjob (minutes and hours) (e.g : 30 6 or 0 12) : "
    read -r minute hour
    if [[ $minute == 0 ]] && [[ $hour == 0 ]]; then
        cron_time="* * * * *"
        break
    elif [[ $minute == 0 ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]]; then
        cron_time="0 */${hour} * * *"
        break
    elif [[ $hour == 0 ]] && [[ $minute =~ ^[0-9]+$ ]] && [[ $minute -lt 60 ]]; then
        cron_time="*/${minute} * * * *"
        break
    elif [[ $minute =~ ^[0-9]+$ ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]] && [[ $minute -lt 60 ]]; then
        cron_time="*/${minute} */${hour} * * *"
        break
    else
        echo "Invalid input, please enter a valid cronjob format (minutes and hours, e.g: 0 6 or 30 12)"
    fi
done

# x-ui or marzban or hiddify
# Prompting the user for the type of software to backup and storing it in variable xmh
while [[ -z "$xmh" ]]; do
    echo "x-ui or marzban or hiddify? [x/m/h] : "
    read -r xmh
    if [[ $xmh == $'\0' ]]; then
        echo "Invalid input. Please choose x, m or h."
        unset xmh
    elif [[ ! $xmh =~ ^[xmh]$ ]]; then
        echo "${xmh} is not a valid option. Please choose x, m or h."
        unset xmh
    fi
done

while [[ -z "$crontabs" ]]; do
    echo "Would you like the previous crontabs to be cleared? [y/n] : "
    read -r crontabs
    if [[ $crontabs == $'\0' ]]; then
        echo "Invalid input. Please choose y or n."
        unset crontabs
    elif [[ ! $crontabs =~ ^[yn]$ ]]; then
        echo "${crontabs} is not a valid option. Please choose y or n."
        unset crontabs
    fi
done

if [[ "$crontabs" == "y" ]]; then
    # Remove existing cron jobs related to PanelBackup
    sudo crontab -l | grep -vE '/root/PanelBackup.+\.sh' | crontab -
fi

# m backup
# Creating a backup file for Marzban software and storing it in PanelBackup.zip
if [[ "$xmh" == "m" ]]; then

    if dir=$(find /opt /root -type d -iname "marzban" -print -quit); then
        echo "The folder exists at $dir"
    else
        echo "The folder does not exist."
        exit 1
    fi

    if [ -d "/var/lib/marzban/mysql" ]; then

        sed -i -e 's/\s*=\s*/=/' -e 's/\s*:\s*/:/' -e 's/^\s*//' /opt/marzban/.env

        docker exec marzban-mysql-1 bash -c "mkdir -p /var/lib/mysql/db-backup"
        source /opt/marzban/.env

        cat > "/var/lib/marzban/mysql/PanelBackup.sh" <<EOL
#!/bin/bash

USER="root"
PASSWORD="$MYSQL_ROOT_PASSWORD"

databases=\$(mysql --user=\$USER --password=\$PASSWORD -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)

for db in \$databases; do
    if [[ "\$db" != "information_schema" ]] && [[ "\$db" != "mysql" ]] && [[ "\$db" != "performance_schema" ]] && [[ "\$db" != "sys" ]] ; then
        echo "Dumping database: \$db"
        mysqldump --force --opt --user=\$USER --password=\$PASSWORD --databases \$db > /var/lib/mysql/db-backup/\$db.sql
    fi
done

EOL
        chmod +x /var/lib/marzban/mysql/PanelBackup.sh

        ZIP=$(cat <<EOF
docker exec marzban-mysql-1 bash -c "/var/lib/mysql/PanelBackup.sh"
zip -r /root/PanelBackup-m.zip /opt/marzban/* /var/lib/marzban/* /opt/marzban/.env -x /var/lib/marzban/mysql/\*
zip -r /root/PanelBackup-m.zip /var/lib/marzban/mysql/db-backup/*
rm -rf /var/lib/marzban/mysql/db-backup/*
EOF
)

    else
        ZIP="zip -r /root/PanelBackup-m.zip ${dir}/* /var/lib/marzban/* /opt/marzban/.env"
    fi

    Notes="Marzban Backup"

# x-ui backup
# Creating a backup file for X-UI software and storing it in PanelBackup.zip
elif [[ "$xmh" == "x" ]]; then

    if dbDir=$(find /etc -type d -iname "x-ui*" -print -quit); then
        echo "The folder exists at $dbDir"
    else
        echo "The folder does not exist."
        exit 1
    fi

    if configDir=$(find /usr/local -type d -iname "x-ui*" -print -quit); then
        echo "The folder exists at $configDir"
    else
        echo "The folder does not exist."
        exit 1
    fi

    ZIP="zip /root/PanelBackup-x.zip ${dbDir}/x-ui.db ${configDir}/config.json"
    Notes="x-ui backup"

# hiddify backup
# Creating a backup file for Hiddify software and storing it in PanelBackup.zip
elif [[ "$xmh" == "h" ]]; then

    if ! find /opt/hiddify-config/hiddify-panel/ -type d -iname "backup" -print -quit; then
        echo "The folder does not exist."
        exit 1
    fi

    ZIP=$(cat <<EOF
cd /opt/hiddify-config/hiddify-panel/
if [ \$(find /opt/hiddify-config/hiddify-panel/backup -type f | wc -l) -gt 100 ]; then
  find /opt/hiddify-config/hiddify-panel/backup -type f -delete
fi
python3 -m hiddifypanel backup
cd /opt/hiddify-config/hiddify-panel/backup
latest_file=\$(ls -t *.json | head -n1)
rm -f /root/PanelBackup-h.zip
zip /root/PanelBackup-h.zip /opt/hiddify-config/hiddify-panel/backup/\$latest_file

EOF
)
    Notes="hiddify backup"
else
    echo "Please choose m or x or h only!"
    exit 1
fi

# Function to trim whitespace
trim() {
    # remove leading and trailing whitespace/lines
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

# Install zip if not already installed
sudo apt install zip -y

# Create the script that will be executed by cron
cat > "/root/PanelBackup-${xmh}.sh" <<EOL
#!/bin/bash

# Calculate current time inside the script
current_time=\$(date +"%d/%m/%Y, %I:%M:%S %p")

# Reconstruct the caption with updated time
caption="${caption}"
Notes="${Notes}"
caption="\${caption}\n\${Notes}\nForked By Boofi Team\nScheduled Backup Created At: \${current_time}"

comment=\$(echo -e "\$caption" | sed 's/<code>//g;s/<\/code>//g')
comment=\$(echo -n "\$comment" | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//')

# Perform the backup
rm -rf /root/PanelBackup-${xmh}.zip
$ZIP
echo -e "\$comment" | zip -z /root/PanelBackup-${xmh}.zip

# Send the backup to Telegram
curl -F chat_id="${chatid}" -F caption="\$comment" -F parse_mode="HTML" -F document=@"/root/PanelBackup-${xmh}.zip" https://api.telegram.org/bot${tk}/sendDocument
EOL

# Make the script executable
chmod +x "/root/PanelBackup-${xmh}.sh"

# Add the cron job to execute the script periodically
{ crontab -l -u root; echo "${cron_time} /bin/bash /root/PanelBackup-${xmh}.sh >/dev/null 2>&1"; } | crontab -u root -

# Run the script immediately
bash "/root/PanelBackup-${xmh}.sh"

# Completion message
echo -e "\nDone\n"
