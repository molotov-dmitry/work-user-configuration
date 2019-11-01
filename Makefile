INSTALL_DIR  	= $(PREFIX)/usr/local/bin
AUTOSTART_DIR	= $(PREFIX)/etc/xdg/autostart

.PHONY: all install uninstall

all:

install: $(INSTALL_DIR)/user-ldap-config $(AUTOSTART_DIR)/user-ldap-config.desktop

uninstall:
	rm -f $(INSTALL_DIR)/user-ldap-config $(AUTOSTART_DIR)/user-ldap-config.desktop

### Executable =================================================================

$(INSTALL_DIR):
	mkdir -p $(INSTALL_DIR)

$(INSTALL_DIR)/user-ldap-config: $(INSTALL_DIR) user-ldap-config.sh
	install user-ldap-config.sh $(INSTALL_DIR)/user-ldap-config

### Global autostart ===========================================================
	
$(AUTOSTART_DIR):
	mkdir -p $(AUTOSTART_DIR)

$(AUTOSTART_DIR)/user-ldap-config.desktop: $(AUTOSTART_DIR) user-ldap-config.desktop
	cp -f user-ldap-config.desktop $(AUTOSTART_DIR)/user-ldap-config.desktop

