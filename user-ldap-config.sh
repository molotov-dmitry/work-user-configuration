#!/bin/bash

ROOT_PATH="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT_PATH}" || exit 1

#### Functions =================================================================

function join_by
{
    local IFS="$1"
    shift
    echo "$*"
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

GITLAB_TOKEN='YnHhW11Lf9tvb_JB9zuM'

#### Check LDAP login is correct ===============================================

ldapoutput="$(ldapsearch -o ldif-wrap=no -x -u -LLL -h "$LDAP_FQDN" -D "$LDAP_EMAIL" -w "$LDAP_PASSWORD" -b "$LDAP_SEARCHBASE" "(mail=$LDAP_EMAIL)" "cn")"

LDAP_FULLNAME="$(echo "$ldapoutput" | grep '^cn:: ' | cut -d ' ' -f 2 | base64 --decode)"

LDAP_GDM_NAME="$(echo "${LDAP_FULLNAME}" | awk '{print $2,$1}' | sed 's/^ *//' | sed 's/ *$//')"

LDAP_SURNAME="$(echo "${LDAP_FULLNAME}" | awk '{print $1}')"
LDAP_FIRST_NAME="$(echo "${LDAP_FULLNAME}" | awk '{print $2}')"
LDAP_MIDDLE_NAME="$(echo "${LDAP_FULLNAME}" | awk '{print $3}')"

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

    wget -qqq --no-check-certificate "${GITLAB_AVATAR}" -O "${HOME}/.face"

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

#### ---------------------------------------------------------------------------

fi

#### Configure pidgin ==========================================================

if ispkginstalled pidgin
then

grep -F "<name>${LDAP_LOGIN}@chat.${LDAP_FQDN}/</name>" "$HOME/.purple/accounts.xml" >/dev/null 2>/dev/null
xmpp_status=$?

grep -F "<protocol>prpl-bonjour</protocol>" "$HOME/.purple/accounts.xml" >/dev/null 2>/dev/null
bonjour_status=$?

if [[ $xmpp_status -ne 0 || $bonjour_status -ne 0 ]]
then
    killall pidgin
    
    mkdir -p "$HOME/.purple"

    cat > "$HOME/.purple/accounts.xml" << _EOF
<?xml version='1.0' encoding='UTF-8' ?>

<account version='1.0'>
    <account>
        <protocol>prpl-jabber</protocol>
        <name>${LDAP_LOGIN}@chat.${LDAP_FQDN}/</name>
        <password>${LDAP_PASSWORD}</password>
        <settings ui='gtk-gaim'>
            <setting name='auto-login' type='bool'>1</setting>
        </settings>
    </account>
	<account>
		<protocol>prpl-bonjour</protocol>
		<name>${LDAP_GDM_NAME}</name>
		<settings>
			<setting name='email' type='string'>${LDAP_EMAIL}</setting>
			<setting name='first' type='string'>${LDAP_FIRST_NAME}</setting>
			<setting name='last' type='string'>${LDAP_SURNAME}</setting>
			<setting name='jid' type='string'>${LDAP_LOGIN}@chat.${LDAP_FQDN}</setting>
		</settings>
		<settings ui='gtk-gaim'>
			<setting name='auto-login' type='bool'>1</setting>
		</settings>
	</account>
</account>
_EOF

    nohup pidgin >/dev/null 2>/dev/null &

fi

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

[Account_JabberProtocol_${LDAP_LOGIN}@chat.${LDAP_FQDN}]
AccountId=${LDAP_LOGIN}@chat.${LDAP_FQDN}
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
Server=chat.${LDAP_FQDN}
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
KopeteTLSWarningchat.${LDAP_FQDN}InvalidCertSelfSigned=false

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
    qdbus org.kde.kwalletd5 /modules/kwalletd5 writePassword    "${wallet_id}" "Kopete" "Account_JabberProtocol_${LDAP_LOGIN}@chat.${LDAP_FQDN}" "${LDAP_PASSWORD}" "Kopete"
    
    nohup kopete >/dev/null 2>/dev/null &
fi

fi

#### Create GOA accounts =======================================================

if ispkginstalled gnome-online-accounts
then
    :
#mkdir -p /home/dmitry/.config/goa-1.0

#if ! grep "Provider=kerberos" "$HOME/.config/goa-1.0/accounts.conf" >/dev/null 2>/dev/null
#then
#cat >> "$HOME/.config/goa-1.0/accounts.conf" << _EOF
#[Account account_1564571125_0]
#Provider=kerberos
#Identity=${LDAP_EMAIL}
#PresentationIdentity=${LDAP_EMAIL}
#Realm=${LDAP_FQDN}
#IsTemporary=false
#TicketingEnabled=true

#_EOF
#fi

#if ! grep "Provider=exchange" "$HOME/.config/goa-1.0/accounts.conf" >/dev/null 2>/dev/null
#then
#cat >> "$HOME/.config/goa-1.0/accounts.conf" << _EOF
#[Account account_1566981726_0]
#Provider=exchange
#Identity=${LDAP_LOGIN}
#PresentationIdentity=${LDAP_EMAIL}
#MailEnabled=true
#CalendarEnabled=true
#ContactsEnabled=true
#Host=${LDAP_FQDN}
#AcceptSslErrors=true

#_EOF
#fi

fi

#### Remove autostart script ===================================================

disableautostart

