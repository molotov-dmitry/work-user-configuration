.PHONY: all install

all:

install: /usr/local/bin/user-ldap-config /etc/xdg/autostart/user-ldap-config.desktop

### Executable =================================================================

/usr/local/bin:
	mkdir -p /usr/local/bin

/usr/local/bin/user-ldap-config: /usr/local/bin user-ldap-config.sh
	install user-ldap-config.sh /usr/local/bin/user-ldap-config

### Global autostart ===========================================================
	
/etc/xdg/autostart:
	mkdir -p /etc/xdg/autostart

/etc/xdg/autostart/user-ldap-config.desktop: /etc/xdg/autostart user-ldap-config.desktop
	cp -f user-ldap-config.desktop /etc/xdg/autostart/

### Local autostart ============================================================

$(HOME)/.config/autostart:
	mkdir -p $(HOME)/.config/autostart

$(HOME)/.config/autostart/desktop-user: $(HOME)/.config/autostart user-ldap-config.desktop
	cp -f user-ldap-config.desktop $(HOME)/.config/autostart/

