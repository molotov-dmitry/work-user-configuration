#!/bin/bash

ROOT_PATH="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT_PATH}" || exit 1

#### Functions =================================================================

function join_by
{
    local separator="$1"
    shift
    local result="$( printf "${separator}%s" "$@" )"
    echo "${result:${#separator}}"
}

function prefix_join_by
{
    local IFS="$1"
    shift
    echo "${*/#/dc=}"
}

safestring()
{
    local inputstr="$1"

    echo "${inputstr}" | sed 's/\\/\\\\/g;s/\//\\\//g'
}

utf16escaped()
{
    echo -n "$@" | iconv -t UTF-16BE | xxd -p | tr -d '\n' | while read -n 4 u; do printf '\\x%x' "0x$u"; done | sed 's/\\x20/ /g'
}

getconfigline()
{
    local key="$1"
    local section="$2"
    local file="$3"
    local default="$4"

    if [[ -r "$file" ]]
    then
        local result="$(sed -n "/^[ \t]*\[$(safestring "${section}")\]/,/^[ \t]*\[/s/^[ \t]*$(safestring "${key}")[ \t]*=[ \t]*//p" "${file}")"
    fi

    if [[ -z "$result" ]]
    then
        result="$default"
    fi

    echo "$result"
}

addconfigline()
{
    local key="$1"
    local value="$2"
    local section="$3"
    local file="$4"

    if ! grep -F "[${section}]" "$file" 1>/dev/null 2>/dev/null
    then
        mkdir -p "$(dirname "$file")"

        echo >> "$file"

        echo "[${section}]" >> "$file"
    fi

    sed -i "/^[[:space:]]*\[${section}\][[:space:]]*$/,/^[[:space:]]*\[.*/{/^[[:space:]]*$(safestring "${key}")[[:space:]]*=/d}" "$file"

    sed -i "/\[${section}\]/a $(safestring "${key}=${value}")" "$file"

    if [[ -n "$(tail -c1 "${file}")" ]]
    then
        echo >> "${file}"
    fi
}

function ispkginstalled()
{
    app="$1"

    if dpkg -s "${app}" >/dev/null 2>&1
    then
        return 0
    else
        return 1
    fi
}

function disableautostart()
{
    echo "Configuration completed. You can re-configure accounts by running 'user-ldap-config' command"
    read -p "Press [Enter] to continue"

    mkdir -p "${HOME}/.config/user-ldap-config"
    echo "autostart=false" > "${HOME}/.config/user-ldap-config/setup-done"
}

function gsettingsadd()
{
    category="$1"
    setting="$2"
    value="$3"

    valuelist=$(gsettings get $category $setting | sed "s/\['//g" | sed "s/'\]//g" | sed "s/'\, '/\n/g" | sed '/@as \[\]/d')

    if [[ -n "$(echo "${valuelist}" | grep ^${value}$)" ]]
    then
        return 0
    fi

    if [[ -n "${valuelist}" ]]
    then
        valuelist="${valuelist}
"
    fi

    valuelist="${valuelist}${value}"

    newvalue="[$(echo "$valuelist" | sed "s/^/'/;s/$/'/" | tr '\n' '\t' | sed 's/\t$//' | sed 's/\t/, /g')]"

    gsettings set $category $setting "${newvalue}"

    return $?
}

#### Input credentials =========================================================

while true
do

unset LDAP_LOGIN
unset LDAP_PASSWORD
unset LDAP_EMAIL

while true
do
    read -p 'Configure account? [Y/n] ' NEED_CONFIGURE

    if [[ -z "${NEED_CONFIGURE}" || "${NEED_CONFIGURE,,}" == 'y' ]]
    then
        break
    fi

    if [[ "${NEED_CONFIGURE,,}" == 'n' ]]
    then
        disableautostart
        exit 0
    fi
done

while true
do
    ping -w 1 -c 1 dc01.rczifort.local > /dev/null && break
    echo 'LDAP server unavailable'
done

echo 'LDAP server available'
echo

while [[ -z "${LDAP_LOGIN}" ]]
do
    read -p 'LDAP username: ' LDAP_LOGIN
done

while [[ -z "${LDAP_PASSWORD}" ]]
do
    read -s -p 'LDAP password: ' LDAP_PASSWORD
    echo
done

LDAP_LOGIN="${LDAP_LOGIN%%@*}"

#### ===========================================================================

LDAP_DOMAIN=('rczifort' 'local')
LDAP_FQDN=$(join_by '.' "${LDAP_DOMAIN[@]}")
LDAP_EMAIL="${LDAP_LOGIN}@${LDAP_FQDN}"

LDAP_SEARCHBASE=$(prefix_join_by ',' "${LDAP_DOMAIN[@]}")

DOMAIN_SERVER="dc01.${LDAP_FQDN}"

KERBEROS_FQDN="${LDAP_FQDN^^}"
KERBEROS_EMAIL="${LDAP_LOGIN}@${KERBEROS_FQDN}"

GITLAB_TOKEN='YnHhW11Lf9tvb_JB9zuM'

XMPP_SERVER="chat.${LDAP_FQDN}"
XMPP_EMAIL="${LDAP_LOGIN}@${XMPP_SERVER}"

GITLAB_SERVER="git.${LDAP_FQDN}"
GITLAB_IP="172.16.56.22"

REDMINE_SERVER="redmine.${LDAP_FQDN}"
REDMINE_EMAIL="${LDAP_EMAIL/@/%40}"

EXCHANGE_SERVER="ex01.${LDAP_FQDN}"

SVN_SERVER="172.16.8.81:3690"
SVN_REALM="RCZI DEV SVN"
SVN_REALMSTRING="<svn://${SVN_SERVER}> ${SVN_REALM}"

SMB_SERVER="data.${LDAP_FQDN}"
SMB_IP="172.16.56.23"

AVATAR_COLORS=('D32F2F' 'B71C1C' 'AD1457' 'EC407A' 'AB47BC' '6A1B9A' 'AA00FF' '5E35B1' '3F51B5' '1565C0' '0091EA' '00838F' '00897B' '388E3C' '558B2F' 'E65100' 'BF360C' '795548' '607D8B')
AVATAR_COLORS_COUNT=${#AVATAR_COLORS[@]}

#### Check LDAP login is correct ===============================================

ldapoutput="$(ldapsearch -o ldif-wrap=no -x -u -LLL -H "ldap://$DOMAIN_SERVER" -D "$LDAP_EMAIL" -w "$LDAP_PASSWORD" -b "$LDAP_SEARCHBASE" "(mail=$LDAP_EMAIL)" "cn" "memberOf")"

LDAP_FULLNAME="$(echo "$ldapoutput" | grep '^cn:: ' | cut -d ' ' -f 2 | base64 --decode)"

LDAP_GDM_NAME="$(echo "${LDAP_FULLNAME}" | awk '{print $2,$1}' | sed 's/^ *//' | sed 's/ *$//')"

LDAP_SURNAME="$(echo "${LDAP_FULLNAME}" | awk '{print $1}')"
LDAP_FIRST_NAME="$(echo "${LDAP_FULLNAME}" | awk '{print $2}')"
LDAP_MIDDLE_NAME="$(echo "${LDAP_FULLNAME}" | awk '{print $3}')"

LDAP_FIRST_NAME_LETTER="${LDAP_FIRST_NAME:0:1}"
LDAP_SURNAME_LETTER="${LDAP_SURNAME:0:1}"

LDAP_DEPARTMENT="$(echo "$ldapoutput" | grep '^memberOf:: ' | cut -d ' ' -f 2 | base64 --decode | tr ',' '\n' | cut -d '=' -f 2 | grep '^Отдел' | head -n1)"

if [[ -n "$LDAP_FULLNAME" ]]
then
    break
fi

done

#### Get GitLab user information ===============================================

gitlaboutput="$(wget "https://git.rczifort.local/api/v4/users?username=${LDAP_LOGIN}&access_token=${GITLAB_TOKEN}" --no-check-certificate -qqq -O - &2>/dev/null)"

if [[ -n "${gitlaboutput}" ]]
then

    GITLAB_FULLNAME="$(echo "${gitlaboutput}" | jq -r '.[0]."name"')"
    GITLAB_AVATAR="$(echo "${gitlaboutput}" | jq -r '.[0]."avatar_url"')"

    if [[ "$GITLAB_FULLNAME" == 'null' ]]
    then
        GITLAB_FULLNAME=''
    fi

    if [[ "$GITLAB_AVATAR" == 'null' ]]
    then
        GITLAB_AVATAR=''
    fi

fi

#### Change user name ==========================================================

if [[ -n "$LDAP_GDM_NAME" && "$USER" != 'rczi' ]]
then
    sudo usermod -c "$LDAP_GDM_NAME" "$USER"
fi

#### Generate user icons =======================================================

avatar_chat="${HOME}/.face"
avatar_user="${HOME}/.face"

if [[ "$USER" == 'rczi' ]]
then
    avatar_chat="${HOME}/.purple/avatar.png"
    mkdir -p "$(dirname "$avatar_chat")"
    cp -f /usr/share/pixmaps/rczi.png "$avatar_user"
fi

#### Download avatar from GitLab -----------------------------------------------

if [[ -n "${GITLAB_AVATAR}" ]]
then
    wget -qqq --no-check-certificate "${GITLAB_AVATAR}" -O "$avatar_chat"
fi

#### Generate icon if not downloaded -------------------------------------------

if [[ ! -s "$avatar_chat" ]] && which rsvg-convert >/dev/null
then
    USER_NAME_LETTER="${LDAP_FIRST_NAME_LETTER}"
    INDEX=$(( (RANDOM * RANDOM + RANDOM) % AVATAR_COLORS_COUNT ))
    bgcolor="#${AVATAR_COLORS[$INDEX]}"
    fgfont="Arial"

    if [[ "gpqy" == *"${USER_NAME_LETTER}"* || "аруцд" == *"${USER_NAME_LETTER}"* ]]
    then
        dy=25
    elif [[ "У"  == *"${USER_NAME_LETTER}"* ]]
    then
        dy=40
    elif [[ "${USER_NAME_LETTER}" == "${USER_NAME_LETTER^^}" && "Д" != *"${USER_NAME_LETTER}"* ]]
    then
        dy=35
    else
        dy=30
    fi

    cat << _EOF | rsvg-convert -w 512 -h 512 -f png -o "$avatar_chat"
<svg width="1000" height="1000">
  <circle cx="500" cy="500" r="400" fill="${bgcolor}" />
  <text x="50%" y="50%" text-anchor="middle" fill="white" font-size="500px" dy="0.${dy}em" font-family="${fgfont}">${USER_NAME_LETTER}</text>
</svg>
_EOF
fi

#### Configure account icon ----------------------------------------------------

if [[ -s "$avatar_user" ]]
then
    sudo mkdir -p '/var/lib/AccountsService/icons/'
    sudo cp -f "$avatar_user" "/var/lib/AccountsService/icons/${USER}"

    FUNC="$(declare -f safestring)

$(declare -f addconfigline)"

    sudo bash -c "$FUNC; addconfigline Icon \"/var/lib/AccountsService/icons/${USER}\" User \"/var/lib/AccountsService/users/${USER}\""
fi

#### Configure Git =============================================================

if ispkginstalled git
then

#### Add credentials -----------------------------------------------------------

if ! grep "https://${LDAP_LOGIN}:${LDAP_PASSWORD}@172.16.56.22" "$HOME/.git-credentials" >/dev/null 2>/dev/null
then
    echo "https://${LDAP_LOGIN}:${LDAP_PASSWORD}@172.16.56.22" >> "$HOME/.git-credentials"
fi

if ! grep "https://${LDAP_LOGIN}:${LDAP_PASSWORD}@git.${LDAP_FQDN}" "$HOME/.git-credentials" >/dev/null 2>/dev/null
then
    echo "https://${LDAP_LOGIN}:${LDAP_PASSWORD}@git.${LDAP_FQDN}" >> "$HOME/.git-credentials"
fi

#### Add user information ------------------------------------------------------

git config --global user.name  "$GITLAB_FULLNAME"
git config --global user.email "$LDAP_EMAIL"

git config --global "credential.https://${GITLAB_SERVER}.username" "${LDAP_LOGIN}"
git config --global "credential.https://${GITLAB_IP}.username"     "${LDAP_LOGIN}"

#### ---------------------------------------------------------------------------

fi

#### Configure Subversion ======================================================

if ispkginstalled subversion
then

    if [[ -z "$(secret-tool search xdg:schema org.gnome.keyring.NetworkPassword user "${LDAP_LOGIN}" domain "${SVN_REALMSTRING}" 2>/dev/null)" ]]
    then
        echo -n "${LDAP_PASSWORD}" | secret-tool store --label="SVN password"   \
            xdg:schema org.gnome.keyring.NetworkPassword                        \
            user "${LDAP_LOGIN}"                                                \
            domain "${SVN_REALMSTRING}"
    fi

    mkdir -p "${HOME}/.subversion/auth/svn.simple"

    cat << _EOF > "${HOME}/.subversion/auth/svn.simple/$(echo -n "${SVN_REALMSTRING}" | md5sum | cut -d ' ' -f 1)"
K 8
passtype
V 6
simple
K 8
password
V ${#LDAP_PASSWORD}
${LDAP_PASSWORD}
K 15
svn:realmstring
V ${#SVN_REALMSTRING}
${SVN_REALMSTRING}
K 8
username
V ${#LDAP_LOGIN}
${LDAP_LOGIN}
END
_EOF

fi

#### Configure gitg ============================================================

if ispkginstalled gitg && ispkginstalled libsecret-tools
then
    if [[ -z "$(secret-tool search xdg:schema org.gnome.gitg.Credentials user "${LDAP_LOGIN}" scheme 'https' host "${GITLAB_SERVER}" 2>/dev/null)" ]]
    then
        echo -n "${LDAP_PASSWORD}" | secret-tool store  \
            --label="https://${GITLAB_SERVER}"          \
            xdg:schema org.gnome.gitg.Credentials       \
            user "${LDAP_LOGIN}"                        \
            scheme 'https'                              \
            host "${GITLAB_SERVER}"
    fi

    if [[ -z "$(secret-tool search xdg:schema org.gnome.gitg.Credentials user "${LDAP_LOGIN}" scheme 'https' host "${GITLAB_IP}" 2>/dev/null)" ]]
    then
        echo -n "${LDAP_PASSWORD}" | secret-tool store  \
            --label="https://${GITLAB_IP}"              \
            xdg:schema org.gnome.gitg.Credentials       \
            user "${LDAP_LOGIN}"                        \
            scheme 'https'                              \
            host "${GITLAB_IP}"
    fi
fi

#### Configure Epiphany ========================================================

if ispkginstalled epiphany-browser
then
    #### GitLab ----------------------------------------------------------------

    if [[ -z "$(secret-tool search xdg:schema org.epiphany.FormPassword username "${LDAP_LOGIN}" uri "https://${GITLAB_SERVER}" 2>/dev/null)" ]]
    then
        echo -n "${LDAP_PASSWORD}" | secret-tool store                              \
            --label="Пароль для ${LDAP_LOGIN} в форме в https://${GITLAB_SERVER}"   \
            xdg:schema org.epiphany.FormPassword                                    \
            server_time_modified 0                                                  \
            id "{$(uuidgen)}"                                                       \
            form_password 'password'                                                \
            target_origin "https://${GITLAB_SERVER}"                                \
            username "${LDAP_LOGIN}"                                                \
            uri "https://${GITLAB_SERVER}"                                          \
            form_username 'username'
    fi

    #### Exchange --------------------------------------------------------------

    if [[ -z "$(secret-tool search xdg:schema org.epiphany.FormPassword username "${LDAP_EMAIL}" uri "https://${EXCHANGE_SERVER}" 2>/dev/null)" ]]
    then
        echo -n "${LDAP_PASSWORD}" | secret-tool store                              \
            --label="Пароль для ${LDAP_EMAIL} в форме в https://${EXCHANGE_SERVER}" \
            xdg:schema org.epiphany.FormPassword                                    \
            server_time_modified 0                                                  \
            id "{$(uuidgen)}"                                                       \
            form_password 'password'                                                \
            target_origin "https://${EXCHANGE_SERVER}"                              \
            username "${LDAP_EMAIL}"                                                \
            uri "https://${EXCHANGE_SERVER}"                                        \
            form_username 'username'
    fi

    #### Redmine ---------------------------------------------------------------

    if [[ -z "$(secret-tool search xdg:schema org.epiphany.FormPassword username "${LDAP_EMAIL}" uri "http://${REDMINE_SERVER}" 2>/dev/null)" ]]
    then
        echo -n "${LDAP_PASSWORD}" | secret-tool store                              \
            --label="Пароль для ${LDAP_EMAIL} в форме в http://${REDMINE_SERVER}"   \
            xdg:schema org.epiphany.FormPassword                                    \
            server_time_modified 0                                                  \
            id "{$(uuidgen)}"                                                       \
            form_password 'password'                                                \
            target_origin "http://${REDMINE_SERVER}"                                \
            username "${LDAP_EMAIL}"                                                \
            uri "http://${REDMINE_SERVER}"                                          \
            form_username 'username'
    fi

fi

#### Configure pidgin ==========================================================

if ispkginstalled pidgin
then

    #### Kill pidgin processes -------------------------------------------------

    killall pidgin

    #### Create Pidgin config directory ----------------------------------------

    rm -rf "$HOME/.purple/icons"

    mkdir -p "$HOME/.purple"
    mkdir -p "$HOME/.purple/icons"

    #### Generate icon UUID and creation timestamp -----------------------------

    xmppiconuuid="$(uuidgen | tr -d '-')"
    bonjouriconuuid="$(uuidgen | tr -d '-')"
    currentts="$(date +%s)"

    #### Create account icons --------------------------------------------------

    srcw=$(identify -format "%w" "$avatar_chat")
    srch=$(identify -format "%h" "$avatar_chat")

    dst="$HOME/.purple/icons/${bonjouriconuuid}.png"

    for size in 512 384 256 192 128 96 64 48 32 24
    do
        if [[ $srcw -lt $size || $srch -lt $size ]]
        then
            continue
        fi

        convert -resize ${size}x${size} "$avatar_chat" "$dst"

        if [[ "$(stat -c "%s" "$dst")" -lt 51200 ]]
        then
            break
        fi

        rm -f "$dst"
    done

    dst="$HOME/.purple/icons/${xmppiconuuid}.png"

    for size in 96 88 80 72 64 56 48 40 32
    do
        if [[ $srcw -lt $size || $srch -lt $size ]]
        then
            continue
        fi

        convert -resize ${size}x${size} "$avatar_chat" "$dst"

        if [[ "$(stat -c "%s" "$dst")" -lt 8192 ]]
        then
            break
        fi

        rm -f "$dst"
    done

    #### Overwrite Pidgin config file ------------------------------------------

    cat > "$HOME/.purple/accounts.xml" << _EOF
<?xml version='1.0' encoding='UTF-8' ?>

<account version='1.0'>
    <account>
        <protocol>prpl-jabber</protocol>
        <name>${XMPP_EMAIL}/</name>
        <password>${LDAP_PASSWORD}</password>
        <alias>${LDAP_FULLNAME}</alias>
        <settings ui='gtk-gaim'>
            <setting name='auto-login' type='bool'>1</setting>
        </settings>
        <settings>
			<setting name='buddy_icon' type='string'>${xmppiconuuid}.png</setting>
			<setting name='buddy_icon_timestamp' type='int'>${currentts}</setting>
		</settings>
    </account>
	<account>
		<protocol>prpl-bonjour</protocol>
		<name>${LDAP_GDM_NAME}</name>
		<settings>
			<setting name='email' type='string'>${LDAP_EMAIL}</setting>
			<setting name='first' type='string'>${LDAP_FIRST_NAME}</setting>
			<setting name='last' type='string'>${LDAP_SURNAME}</setting>
			<setting name='jid' type='string'>${XMPP_EMAIL}</setting>
			<setting name='buddy_icon' type='string'>${bonjouriconuuid}.png</setting>
			<setting name='buddy_icon_timestamp' type='int'>${currentts}</setting>
		</settings>
		<settings ui='gtk-gaim'>
			<setting name='auto-login' type='bool'>1</setting>
		</settings>
	</account>
</account>
_EOF

    #### Configure global buddy icon -------------------------------------------

    if grep "<pref name='buddyicon' type='path' value='[^']*'/>"  "${HOME}/.purple/prefs.xml" >/dev/null 2>/dev/null
    then
        sed -i "s/<pref name='buddyicon' type='path' value='[^']*'\/>/<pref name='buddyicon' type='path' value='$(safestring "${avatar_chat}")'\/>/" "${HOME}/.purple/prefs.xml"
    fi

    #### Create autostart entry for pidgin -------------------------------------

    if [[ ! -e "${HOME}/.config/autostart/pidgin.desktop" ]]
    then
        for dir in "${HOME}/.local/share/applications" "/usr/share/applications"
        do
            if [[ -s "${dir}/pidgin.desktop" ]]
            then
                cp -f "${dir}/pidgin.desktop" "${HOME}/.config/autostart/pidgin.desktop"
                break
            fi
        done
    fi

    #### Start Pidgin ----------------------------------------------------------

    nohup pidgin >/dev/null 2>/dev/null &

fi

#### Configure Kopete ==========================================================

if ispkginstalled kopete
then

kopete_identity=$(echo "${LDAP_GDM_NAME}" | md5sum | cut -c 1-10)

grep -F "kopete_jabberEnabled=true" "$HOME/.config/kopeterc" >/dev/null 2>/dev/null
xmpp_status=$?

grep -F "kopete_bonjourEnabled=true" "$HOME/.config/kopeterc" >/dev/null 2>/dev/null
bonjour_status=$?

if [[ $xmpp_status -ne 0 || $bonjour_status -ne 0 ]]
then
    killall kopete

    mkdir -p "$HOME/.config"

    cat > "$HOME/.config/kopeterc" << _EOF
[Account_BonjourProtocol_${LDAP_GDM_NAME}]
AccountId=${LDAP_GDM_NAME}
ExcludeConnect=false
Identity=${kopete_identity}
Priority=1
Protocol=BonjourProtocol
emailAddress=${LDAP_EMAIL}
firstName=${LDAP_FIRST_NAME}
lastName=${LDAP_SURNAME}
username=${LDAP_GDM_NAME}

[Account_JabberProtocol_${XMPP_EMAIL}]
AccountId=${XMPP_EMAIL}
AllowPlainTextPassword=true
CustomServer=false
ExcludeConnect=false
HideSystemInfo=false
Identity=${kopete_identity}
Libjingle=true
MergeMessages=true
OldEncrypted=false
PasswordIsWrong=false
Port=5222
Priority=5
Protocol=JabberProtocol
ProxyJID=
RememberPassword=true
Resource=Kopete
SendComposingEvent=true
SendDeliveredEvent=true
SendDisplayedEvent=true
SendEvents=true
SendGoneEvent=true
Server=${XMPP_SERVER}
UseSSL=false
UseXOAuth2=false

[IdentityManager]
DefaultIdentity=${kopete_identity}

[Behavior]
initialStatus=Online

[ContactList]
contactListIconMode=IconPhoto
showOfflineUsers=false

[Notification Messages]
KopeteTLSWarning${XMPP_SERVER}InvalidCertSelfSigned=false

[Identity_${kopete_identity}]
Id=${kopete_identity}
Label=${LDAP_GDM_NAME}
prop_QString_emailAddress=${LDAP_EMAIL}
prop_QString_firstName=${LDAP_FIRST_NAME}
prop_QString_lastName=${LDAP_SURNAME}
prop_QString_photo=${HOME}/.local/share/kopete/avatars/User/${kopete_identity}.png

[Plugins]
kopete_bonjourEnabled=true
kopete_jabberEnabled=true

[Status Manager]
GlobalStatusCategory=2
GlobalStatusMessage=
GlobalStatusTitle=В сети
_EOF

    mkdir -p "${HOME}/.local/share/kopete/avatars/User"
    cp -f "$avatar_chat" "${HOME}/.local/share/kopete/avatars/User/${kopete_identity}.png"

    wallet_id="$(qdbus org.kde.kwalletd5 /modules/kwalletd5 org.kde.KWallet.open kdewallet 0 "Kopete")"

    qdbus org.kde.kwalletd5 /modules/kwalletd5 createFolder     "${wallet_id}" "Kopete" "Kopete"
    qdbus org.kde.kwalletd5 /modules/kwalletd5 writePassword    "${wallet_id}" "Kopete" "Account_JabberProtocol_${XMPP_EMAIL}" "${LDAP_PASSWORD}" "Kopete"

    nohup kopete >/dev/null 2>/dev/null &
fi

fi

#### Configure KMail ===========================================================

if ispkginstalled kmail
then

    count_resources_ews="$(getconfigline    'akonadi_ews_resource\InstanceCounter'    'InstanceCounters' "${HOME}/.config/akonadi/agentsrc" '0')"
    count_resources_ewsmta="$(getconfigline 'akonadi_ewsmta_resource\InstanceCounter' 'InstanceCounters' "${HOME}/.config/akonadi/agentsrc" '0')"

    index_resources_ews=-1
    index_resources_ewsmta=-1
    
    restart_akonadi=0

    for (( i = 0; i < $count_resources_ews; i++ ))
    do
        if [[ "$(getconfigline 'Email' 'General' "${HOME}/.config/akonadi_ews_resource_${i}rc")" == "${LDAP_EMAIL}" ]]
        then
            index_resources_ews=$i
            break
        fi
    done

    if [[ ${index_resources_ews} -lt 0 ]]
    then
        ## Akonadi resource ----------------------------------------------------

        index_resources_ews="${count_resources_ews}"
        i="${count_resources_ews}"

        addconfigline 'BaseUrl'  "https://ex01.${LDAP_FQDN}/EWS/Exchange.asmx" 'General' "${HOME}/.config/akonadi_ews_resource_${i}rc"

        addconfigline 'Domain'   "${LDAP_FQDN}"  'General' "${HOME}/.config/akonadi_ews_resource_${i}rc"
        addconfigline 'Email'    "${LDAP_EMAIL}" 'General' "${HOME}/.config/akonadi_ews_resource_${i}rc"
        addconfigline 'Username' "${LDAP_LOGIN}" 'General' "${HOME}/.config/akonadi_ews_resource_${i}rc"

        addconfigline 'RetrievalMethod' '1' 'General' "${HOME}/.config/akonadi_ews_resource_${i}rc"

        let count_resources_ews++

        ## Akonadi agent -------------------------------------------------------

        addconfigline 'Name' "$(utf16escaped "${LDAP_GDM_NAME}")" 'Agent' "${HOME}/.config/akonadi/agent_config_akonadi_ews_resource_${i}"

        addconfigline 'akonadi_ews_resource\InstanceCounter' "${count_resources_ews}" 'InstanceCounters' "${HOME}/.config/akonadi/agentsrc"
        addconfigline "akonadi_ews_resource_${i}\AgentType"  'akonadi_ews_resource'   'Instances'        "${HOME}/.config/akonadi/agentsrc"

        ## Get mail on startup -------------------------------------------------
        
        addconfigline 'CheckOnStartup' 'true' "Resource akonadi_ews_resource_${i}" "${HOME}/.config/kmail2rc"
        
        ## Password ------------------------------------------------------------

        wallet_id="$(qdbus org.kde.kwalletd5 /modules/kwalletd5 org.kde.KWallet.open kdewallet 0 "akonadi-ews")"

        qdbus org.kde.kwalletd5 /modules/kwalletd5 createFolder     "${wallet_id}" "akonadi-ews" "akonadi-ews"
        qdbus org.kde.kwalletd5 /modules/kwalletd5 writePassword    "${wallet_id}" "akonadi-ews" "akonadi_ews_resource_${i}rc" "${LDAP_PASSWORD}" "akonadi-ews"
        
        restart_akonadi=1

    fi

    for (( i = 0; i < $count_resources_ewsmta; i++ ))
    do
        if [[ "$(getconfigline 'EwsResource' 'General' "${HOME}/.config/akonadi_ewsmta_resource_${i}rc")" == "akonadi_ews_resource_${index_resources_ews}" ]]
        then
            index_resources_ewsmta=$i
            break
        fi
    done

    if [[ ${index_resources_ewsmta} -lt 0 ]]
    then
        ## Akonadi resource ----------------------------------------------------

        index_resources_ewsmta="${count_resources_ewsmta}"
        i="${count_resources_ewsmta}"

        addconfigline 'EwsResource' "akonadi_ews_resource_${index_resources_ews}" 'General' "${HOME}/.config/akonadi_ewsmta_resource_${i}rc"

        let count_resources_ewsmta++

        ## Akonadi agent -------------------------------------------------------

        addconfigline 'Name' "$(utf16escaped "${LDAP_GDM_NAME}")" 'Agent' "${HOME}/.config/akonadi/agent_config_akonadi_ewsmta_resource_${i}"

        addconfigline 'akonadi_ewsmta_resource\InstanceCounter' "${count_resources_ews}" 'InstanceCounters' "${HOME}/.config/akonadi/agentsrc"
        addconfigline "akonadi_ewsmta_resource_${i}\AgentType"  'akonadi_ewsmta_resource'   'Instances'     "${HOME}/.config/akonadi/agentsrc"

        ## Mail transport ------------------------------------------------------

        transport_id=$(date +%s)
        sleep 1

        addconfigline 'host'       "akonadi_ewsmta_resource_${i}" "Transport ${transport_id}" "${HOME}/.config/mailtransports"
        addconfigline 'id'         "${transport_id}"              "Transport ${transport_id}" "${HOME}/.config/mailtransports"
        addconfigline 'identifier' "akonadi_ewsmta_resource"      "Transport ${transport_id}" "${HOME}/.config/mailtransports"
        addconfigline 'name'       "${LDAP_EMAIL}"                "Transport ${transport_id}" "${HOME}/.config/mailtransports"

        addconfigline 'default-transport' "${transport_id}" "General" "${HOME}/.config/mailtransports"
        
        ## Profile -------------------------------------------------------------
        
        addconfigline 'EmailAddress' "${LDAP_EMAIL}"    'PROFILE_По умолчанию' "${HOME}/.config/emaildefaults"
        addconfigline 'FullName'     "${LDAP_FULLNAME}" 'PROFILE_По умолчанию' "${HOME}/.config/emaildefaults"
        
        addconfigline 'Profile'      'По умолчанию'     'Defaults'             "${HOME}/.config/emaildefaults"
        
        ## Identity ------------------------------------------------------------
        
        identity_id=$(date +%s)
        sleep 1
        
        addconfigline 'Default Domain'   "${LDAP_DOMAIN}"   'Identity #0' "${HOME}/.config/emailidentities"
        addconfigline 'Email Address'    "${LDAP_EMAIL}"    'Identity #0' "${HOME}/.config/emailidentities"
        addconfigline 'Identity'         "${LDAP_GDM_NAME}" 'Identity #0' "${HOME}/.config/emailidentities"
        addconfigline 'Name'             "${LDAP_FULLNAME}" 'Identity #0' "${HOME}/.config/emailidentities"
        addconfigline 'Transport'        "${transport_id}"  'Identity #0' "${HOME}/.config/emailidentities"
        addconfigline 'uoid'             "${identity_id}"   'Identity #0' "${HOME}/.config/emailidentities"
        
        addconfigline 'Default Identity' "${identity_id}"   'General'     "${HOME}/.config/emailidentities"
        
        ## ---------------------------------------------------------------------
        
        restart_akonadi=1
    fi
    
    if [[ $restart_akonadi -gt 0 ]]
    then
        akonadictl restart >/dev/null 2>/dev/null
    fi
fi

#### Configure work report =====================================================

if ispkginstalled work-report
then

unset reportconfig

if [[ -f "${HOME}/.config/work-report/config.json" ]]
then
    reportconfig="$(jq '' "${HOME}/.config/work-report/config.json")"
fi

if [[ -z "$reportconfig" ]]
then
    reportconfig='{}'
fi

if [[ -n "${LDAP_FIRST_NAME}" ]]
then
    reportconfig="$(echo "${reportconfig}" | jq ".\"userFirstName\" = \"${LDAP_FIRST_NAME}\"")"
fi

if [[ -n "${LDAP_SURNAME}" ]]
then
    reportconfig="$(echo "${reportconfig}" | jq ".\"userSurname\" = \"${LDAP_SURNAME}\"")"
fi

if [[ -n "${LDAP_MIDDLE_NAME}" ]]
then
    reportconfig="$(echo "${reportconfig}" | jq ".\"userLastName\" = \"${LDAP_MIDDLE_NAME}\"")"
fi

if [[ -n "${LDAP_DEPARTMENT}" ]]
then
    department_name="$(echo "${LDAP_DEPARTMENT}" | sed 's/^Отдел //' | sed 's/ ПО\($\|[[:space:]]\)/ программного обеспечения\1/')"
    reportconfig="$(echo "${reportconfig}" | jq ".\"department\" = \"${department_name}\"")"
fi

mkdir -p "${HOME}/.config/work-report"
echo "${reportconfig}" > "${HOME}/.config/work-report/config.json"

fi

#### Create network share passord ==============================================

if [[ -z "$(secret-tool search protocol 'smb' user "${LDAP_LOGIN}" server "${SMB_SERVER}" domain "${KERBEROS_FQDN}" 2>/dev/null)" ]]
then

    echo -n "${LDAP_PASSWORD}" | secret-tool store      \
        --label="${LDAP_EMAIL}"                         \
        xdg:schema org.gnome.keyring.NetworkPassword    \
        protocol 'smb'                                  \
        user "${LDAP_LOGIN}"                            \
        server "${SMB_SERVER}"                          \
        domain "${KERBEROS_FQDN}"

fi

if [[ -z "$(secret-tool search protocol 'smb' user "${LDAP_LOGIN}" server "${SMB_IP}" domain "${LDAP_FQDN}" 2>/dev/null)" ]]
then

    echo -n "${LDAP_PASSWORD}" | secret-tool store      \
        --label="${LDAP_EMAIL}"                         \
        xdg:schema org.gnome.keyring.NetworkPassword    \
        protocol 'smb'                                  \
        user "${LDAP_LOGIN}"                            \
        server "${SMB_IP}"                              \
        domain "${LDAP_FQDN}"

fi

#### Create GOA accounts =======================================================

if ispkginstalled gnome-online-accounts
then

mkdir -p "${HOME}/.config/goa-1.0"

acc_id="$(grep '^\[Account ' "${HOME}/.config/goa-1.0/accounts.conf" | sed 's/.*_//g;s/\].*//g' | sort -g | tail -n1)"

if [[ -z "$acc_id" ]]
then
    acc_id=0
else
    let acc_id++
fi

## Kerberos --------------------------------------------------------------------

if ! grep "Provider=kerberos" "${HOME}/.config/goa-1.0/accounts.conf" >/dev/null 2>/dev/null
then

    date_create=$(date +%s)

    echo -n "{'password': <'${LDAP_PASSWORD}'>}" | secret-tool store                                \
        --label="Учётные данные GOA kerberos для идентификатора account_${date_create}_${acc_id}"   \
        xdg:schema org.gnome.OnlineAccounts                                                         \
        goa-identity "kerberos:gen0:account_${date_create}_${acc_id}"

    cat >> "${HOME}/.config/goa-1.0/accounts.conf" << _EOF
[Account account_${date_create}_${acc_id}]
Provider=kerberos
Identity=${KERBEROS_EMAIL}
PresentationIdentity=${KERBEROS_EMAIL}
Realm=${KERBEROS_FQDN}
IsTemporary=false
TicketingEnabled=true

_EOF

let acc_id++

fi

## Exchange --------------------------------------------------------------------

if ! grep "Provider=exchange" "${HOME}/.config/goa-1.0/accounts.conf" >/dev/null 2>/dev/null
then

    date_create=$(date +%s)

    echo -n "{'password': <'${LDAP_PASSWORD}'>}" | secret-tool store                                \
        --label="Учётные данные GOA exchange для идентификатора account_${date_create}_${acc_id}"   \
        xdg:schema org.gnome.OnlineAccounts                                                         \
        goa-identity "exchange:gen0:account_${date_create}_${acc_id}"

    cat >> "${HOME}/.config/goa-1.0/accounts.conf" << _EOF
[Account account_${date_create}_${acc_id}]
Provider=exchange
Identity=${LDAP_LOGIN}
PresentationIdentity=${LDAP_EMAIL}
MailEnabled=true
CalendarEnabled=true
ContactsEnabled=true
Host=${EXCHANGE_SERVER}
AcceptSslErrors=true

_EOF
fi

## -----------------------------------------------------------------------------

fi

#### Configure Redmine Gnome Shell extension ===================================

if ispkginstalled gnome-shell
then
    dconf write /org/gnome/shell/extensions/redmine-issues/api-access-key               "' '"
    dconf write /org/gnome/shell/extensions/redmine-issues/auto-refresh                 15
    dconf write /org/gnome/shell/extensions/redmine-issues/group-by                     "'status'"
    dconf write /org/gnome/shell/extensions/redmine-issues/redmine-url                  "'http://${REDMINE_EMAIL}:${LDAP_PASSWORD}@${REDMINE_SERVER}/redmine'"
    dconf write /org/gnome/shell/extensions/redmine-issues/show-status-item-assigned-to false
    dconf write /org/gnome/shell/extensions/redmine-issues/show-status-item-project     true

    gsettingsadd org.gnome.shell enabled-extensions 'redmineIssues@UshakovVasilii_Github.yahoo.com'
fi

#### Remove autostart script ===================================================

disableautostart

