install:
	mkdir -p /usr/local/bin
	cp -f user-ldap-config.sh /usr/local/bin/user-ldap-config
	chmod +x /usr/local/bin/user-ldap-config

desktop-skel:
	mkdir -p /etc/skel/.config/autostart
	cp -f user-ldap-config.desktop /etc/skel/.config/autostart/

desktop:
	mkdir -p $(HOME)/.config/autostart
	cp -f user-ldap-config.desktop $(HOME)/.config/autostart/

