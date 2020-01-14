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

function addconfigline()
{
    key="$1"
    value="$2"
    section="$3"
    file="$4"

    if ! grep -F "[${section}]" "$file" 1>/dev/null 2>/dev/null
    then
        mkdir -p "$(dirname "$file")"

        echo >> "$file"

        echo "[${section}]" >> "$file"
    fi

    sed -i "/^[[:space:]]*\[${section}\][[:space:]]*$/,/^[[:space:]]*\[.*/{/^[[:space:]]*$(echo "${key}" | sed 's/\//\\\//g')[[:space:]]*=/d}" "$file"

    sed -i "/\[${section}\]/a $(echo "${key}=${value}" | sed 's/\//\\\//g')" "$file"

    [[ -n "$(tail -c1 "${file}")" ]] && echo >> "${file}"
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

KERBEROS_FQDN="${LDAP_FQDN^^}"
KERBEROS_EMAIL="${LDAP_LOGIN}@${KERBEROS_FQDN}"

GITLAB_TOKEN='YnHhW11Lf9tvb_JB9zuM'

XMPP_SERVER="chat.${LDAP_FQDN}"
XMPP_EMAIL="${LDAP_LOGIN}@${XMPP_SERVER}"

GITLAB_SERVER="git.${LDAP_FQDN}"
GITLAB_IP="172.16.56.22"

REDMINE_SERVER="redmine.${LDAP_FQDN}"

EXCHANGE_SERVER="ex01.${LDAP_FQDN}"

SVN_SERVER="172.16.8.81:3690"
SVN_REALM="RCZI DEV SVN"
SVN_REALMSTRING="<svn://${SVN_SERVER}> ${SVN_REALM}"

SMB_SERVER="data.${LDAP_FQDN}"

AVATAR_COLORS=('D32F2F' 'B71C1C' 'AD1457' 'EC407A' 'AB47BC' '6A1B9A' 'AA00FF' '5E35B1' '3F51B5' '1565C0' '0091EA' '00838F' '00897B' '388E3C' '558B2F' 'E65100' 'BF360C' '795548' '607D8B')
AVATAR_COLORS_COUNT=${#AVATAR_COLORS[@]}

#### Check LDAP login is correct ===============================================

ldapoutput="$(ldapsearch -o ldif-wrap=no -x -u -LLL -h "$LDAP_FQDN" -D "$LDAP_EMAIL" -w "$LDAP_PASSWORD" -b "$LDAP_SEARCHBASE" "(mail=$LDAP_EMAIL)" "cn" "memberOf")"

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

if [[ -n "$LDAP_GDM_NAME" ]]
then
    sudo usermod -c "$LDAP_GDM_NAME" "$USER"
fi

#### Update avatar =============================================================

if [[ -n "${GITLAB_AVATAR}" ]]
then

    #### Download avatar from GitLab -------------------------------------------

    wget -qqq --no-check-certificate "${GITLAB_AVATAR}" -O "${HOME}/.face"
    
    #### Generate avatar if not exists -----------------------------------------
    
    if [[ ! -s "${HOME}/.face" ]] && which convert >/dev/null && which rsvg-convert >/dev/null
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
    
        cat << _EOF | rsvg-convert -w 512 -h 512 -f png -o "${HOME}/.face"
<svg width="1000" height="1000">
  <circle cx="500" cy="500" r="400" fill="${bgcolor}" />
  <text x="50%" y="50%" text-anchor="middle" fill="white" font-size="500px" dy="0.${dy}em" font-family="${fgfont}">${USER_NAME_LETTER}</text>
</svg>
_EOF
    fi
    
    #### Configure account icon ------------------------------------------------

    sudo mkdir -p '/var/lib/AccountsService/icons/'

    sudo cp -f "${HOME}/.face" "/var/lib/AccountsService/icons/${USER}"

    FUNC="$(declare -f addconfigline)"
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
d.sorokin
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
    
    srcw=$(identify -format "%w" "${HOME}/.face")
    srch=$(identify -format "%h" "${HOME}/.face")

    dst="$HOME/.purple/icons/${bonjouriconuuid}.png"

    for size in 512 384 256 192 128 96 64 48 32 24
    do
        if [[ $srcw -lt $size || $srch -lt $size ]]
        then
            continue
        fi
        
        convert -resize ${size}x${size} "${HOME}/.face" "$dst"
        
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
        
        convert -resize ${size}x${size} "${HOME}/.face" "$dst"
        
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

#### Configure kopete ==========================================================

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
    cp -f "${HOME}/.face" "${HOME}/.local/share/kopete/avatars/User/${kopete_identity}.png"
    
    wallet_id="$(qdbus org.kde.kwalletd5 /modules/kwalletd5 org.kde.KWallet.open kdewallet 0 "Kopete")"
    
    qdbus org.kde.kwalletd5 /modules/kwalletd5 createFolder     "${wallet_id}" "Kopete" "Kopete"
    qdbus org.kde.kwalletd5 /modules/kwalletd5 writePassword    "${wallet_id}" "Kopete" "Account_JabberProtocol_${XMPP_EMAIL}" "${LDAP_PASSWORD}" "Kopete"
    
    nohup kopete >/dev/null 2>/dev/null &
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

#### Remove autostart script ===================================================

disableautostart

