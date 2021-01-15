HOSTNAME=server.foo.bar
SERVICE=myservice # Change this to your service name
INST=$(shell pwd)/krb5inst
SBIN=$(INST)/sbin
ETC=$(INST)/etc
VAR=$(INST)/var
KRB5KDC=$(SBIN)/krb5kdc
KDB5UTIL=$(SBIN)/kdb5_util
KADMIN=$(SBIN)/kadmin.local
KRB5CONF=$(ETC)/krb5.conf
KDCCONF=$(VAR)/krb5kdc/kdc.conf
PRINCIPAL=$(VAR)/krb5kdc/principal
KADMACL=$(VAR)/krb5kdc/kadm5.acl
STASH=$(VAR)/krb5kdc/stash
LOG=$(VAR)/krb5kdc/admin.log
KADMKEYTAB=$(VAR)/krb5kdc/kadm5.keytab
HOSTKEYTAB=$(ETC)/krb5.keytab
SERVICEKEYTAB=$(ETC)/$(SERVICE).keytab
REALM=FOO.BAR
ADMIN=admin/admin
USER1=knoll # Change this to whatever you want to use as login
USER2=tott
PASS=qwer123 # Change this to whaterver you want to use as pw
LIBS=$(INST)/lib

all: $(LOG)

# Clone the KRB5 repository
krb5/src/Makefile.in:
	git clone -b krb5-1.16.2-final https://github.com/krb5/krb5.git # NOTE: Using a quite old version... :/

# Configure a build environment for KRB5
krb5/src/configure: krb5/src/Makefile.in
	cd $(dir $^) && autoreconf

krb5/src/Makefile: krb5/src/configure
	cd $(dir $^) && ./configure --prefix=$(INST) --runstatedir=$(VAR)/run && $(MAKE) -s && $(MAKE) -j1 -s install

# Compile a KRB5 KDC and put it in $INST
.NOTPARALLEL: build
.PHONY: build
krbbuild: krb5/src/Makefile
	mkdir -p $(dir $(KRB5CONF)) $(dir $(KDCCONF))

$(KRB5KDC): krbbuild

$(KDB5UTIL): krbbuild

$(KADMIN): krbbuild

# Configure krb5kdc
.NOTPARALLEL: $(KDCCONF)
$(KDCCONF):
	echo "[kdcdefaults]" > $@
	echo "  kdc_ports = 10750,10088" >> $@
	echo "  kdc_tcp_ports = 10750,10088" >> $@
	echo "[realms]" >> $@
	echo "  $(REALM) = {" >> $@
	echo "    database_name = $(PRINCIPAL)" >> $@
	echo "    admin_keytab = FILE:$(KADMKEYTAB)" >> $@
	echo "    acl_file = $(KADMACL)" >> $@
	echo "    key_stash_file = $(STASH)" >> $@
	echo "    max_life = 10h 0m 0s" >> $@
	echo "    max_renewable_life = 7d 0h 0m 0s" >> $@
	echo "  }" >> $@

# Configure krb5 client
.NOTPARALLEL: $(KRB5CONF)
$(KRB5CONF):
	echo "[libdefaults]" > $@
	echo "  default_realm = $(REALM)" >> $@
	echo "[realms]" >> $@
	echo "  $(REALM) = {" >> $@
	echo "    kdc = localhost:1088" >> $@
	echo "    admin_server = localhost:10750" >> $@
	echo "  }" >> $@

# Set up principals
$(PRINCIPAL): $(KDB5UTIL) $(KRB5CONF) $(KDCCONF)
	export KRB5_KDC_PROFILE=$(KDCCONF) && \
	export KRB5_CONFIG=$(ETC)/krb5.conf && \
	export LD_LIBRARY_PATH=$(LIBS) && \
	$(KDB5UTIL) -r $(REALM) -P $(PASS) create -s

# And the stash
$(STASH): $(KDB5UTIL) $(PRINCIPAL) $(KDCCONF)
	export KRB5_KDC_PROFILE=$(KDCCONF) && \
	export KRB5_CONFIG=$(ETC)/krb5.conf && \
	export LD_LIBRARY_PATH=$(LIBS) && \
	$(KDB5UTIL) -r $(REALM) -P $(PASS) stash -f $@

# Add admin/admin and the specified $USER1 and $USER2 along with the host/$HOSTNAME and service/$HOSTNAME
$(LOG): $(KADMIN) $(STASH) $(KDCCONF)
	export KRB5_KDC_PROFILE=$(KDCCONF) && \
	export KRB5_CONFIG=$(ETC)/krb5.conf && \
	export LD_LIBRARY_PATH=$(LIBS) && \
	/bin/echo -e "$(PASS)\n$(PASS)" | $< -r $(REALM) -p $(ADMIN)@$(REALM) -q "addprinc $(ADMIN)" > $@ && \
	$(KADMIN) -r $(REALM) -p $(ADMIN)@$(REALM) -q "addpol users" >> $@ && \
	$(KADMIN) -r $(REALM) -p $(ADMIN)@$(REALM) -q "addpol admin" >> $@ && \
	$(KADMIN) -r $(REALM) -p $(ADMIN)@$(REALM) -q "addpol hosts" >> $@ && \
	/bin/echo -e "$(PASS)\n$(PASS)" | $< -r $(REALM) -p $(ADMIN)@$(REALM) -q "addprinc -policy users $(USER1)" >> $@ && \
	/bin/echo -e "$(PASS)\n$(PASS)" | $< -r $(REALM) -p $(ADMIN)@$(REALM) -q "addprinc -policy users $(USER2)" >> $@ && \
	$(KADMIN) -r $(REALM) -p $(ADMIN)@$(REALM) -q "addprinc -randkey -policy hosts host/${HOSTNAME}" >> $@ && \
	$(KADMIN) -r $(REALM) -p $(ADMIN)@$(REALM) -q "ktadd -k $(ETC)/krb5.keytab host/$(HOSTNAME)" >> $@
	$(KADMIN) -r $(REALM) -p $(ADMIN)@$(REALM) -q "addprinc -randkey -policy ${SERVICE}/${HOSTNAME}" >> $@ && \
	$(KADMIN) -r $(REALM) -p $(ADMIN)@$(REALM) -q "ktadd -k $(ETC)/krb5.keytab ${SERVICE}/$(HOSTNAME)" >> $@

# Start the KDC service
run: $(LOG)
	export KRB5_KDC_PROFILE=$(KDCCONF) && \
	export KRB5_CONFIG=$(ETC)/krb5.conf && \
	export LD_LIBRARY_PATH=$(LIBS) && \
	$(KRB5KDC) -r $(REALM)

clean:
	$(RM) -rf $(INST) *~

clean-all: clean
	$(RM) -rf krb5
