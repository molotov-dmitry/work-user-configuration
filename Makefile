TARGET			= user-ldap-config
INSTALL_DIR  	= $(PREFIX)/usr/local/bin
AUTOSTART_DIR	= $(PREFIX)/etc/xdg/autostart
PIXMAPS_DIR		= $(PREFIX)/usr/share/pixmaps

.PHONY: all install uninstall

all:

install: $(INSTALL_DIR)/$(TARGET) $(AUTOSTART_DIR)/$(TARGET).desktop $(PIXMAPS_DIR)/rczi.png

uninstall:
	rm -f $(INSTALL_DIR)/$(TARGET) $(AUTOSTART_DIR)/$(TARGET).desktop $(PIXMAPS_DIR)/rczi.png

### Executable =================================================================

$(INSTALL_DIR):
	mkdir -p $@

$(INSTALL_DIR)/$(TARGET): $(TARGET).sh $(INSTALL_DIR)
	install $< $@

### Global autostart ===========================================================
	
$(AUTOSTART_DIR):
	mkdir -p $@

$(AUTOSTART_DIR)/$(TARGET).desktop: $(TARGET).desktop $(AUTOSTART_DIR)
	install $< $@

### RCZI Icon ==================================================================

$(PIXMAPS_DIR):
	mkdir -p $@

$(PIXMAPS_DIR)/rczi.png: rczi.png $(PIXMAPS_DIR)
	install $< $@

