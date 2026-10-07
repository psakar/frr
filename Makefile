include /usr/share/dpkg/default.mk

PACKAGE=frr

SRCDIR=frr
BUILDDIR=$(PACKAGE)-$(DEB_VERSION_UPSTREAM)

ORIG_SRC_TAR=$(PACKAGE)_$(DEB_VERSION_UPSTREAM).orig.tar.gz
DSC=$(PACKAGE)_$(DEB_VERSION).dsc

MAIN_DEB=$(PACKAGE)_$(DEB_VERSION)_$(DEB_HOST_ARCH).deb
OTHER_DEBS=\
  frr-doc_$(DEB_VERSION)_all.deb \
  frr-pythontools_$(DEB_VERSION)_all.deb \
  frr-rpki-rtrlib_$(DEB_VERSION)_$(DEB_HOST_ARCH).deb \
  frr-snmp_$(DEB_VERSION)_$(DEB_HOST_ARCH).deb \
  frr-test-tools_$(DEB_VERSION)_$(DEB_HOST_ARCH).deb \

DBG_DEBS=\
  frr-dbgsym_$(DEB_VERSION)_$(DEB_HOST_ARCH).deb \
  frr-rpki-rtrlib-dbgsym_$(DEB_VERSION)_$(DEB_HOST_ARCH).deb \
  frr-snmp-dbgsym_$(DEB_VERSION)_$(DEB_HOST_ARCH).deb \
  frr-test-tools-dbgsym_$(DEB_VERSION)_$(DEB_HOST_ARCH).deb \


DEBS=$(MAIN_DEB) $(OTHER_DEBS) $(DBG_DEBS)

all: $(DEBS)
	@echo $(DEBS)

.PHONY: submodule
submodule:
	test -f "$(SRCDIR)/debian/changelog" || git submodule update --init

# FIXME: fully merge our and upstream (which is also the upstream for debian's "downstream") packaging
# so that the top-level debian directory is the canonical source.
$(BUILDDIR): submodule debian/changelog
	rm -rf $@ $@.tmp
	cp -a $(SRCDIR) $@.tmp
	rm $@.tmp/debian/changelog $@.tmp/debian/compat
ifneq (,$(filter pkg.frr.lsbservice,$(DEB_BUILD_PROFILES)))
# for systemd-free derivatives like Devuan (sysvinit or OpenRC): upstream's
# frrinit.sh as /etc/init.d/frr instead of the units, likewise neither enabled
# nor started on installation
	sed -i '/build\/tools\/frr@\{0,1\}\.service/d' $@.tmp/debian/rules
	sed -i 's/dh_installinit -r$$/dh_installinit -r --no-enable --no-start/' $@.tmp/debian/rules
else
	sed -i '/frrinit\.sh/d' $@.tmp/debian/rules
	sed -i 's/dh_installsystemd -r/dh_installsystemd -r --no-enable --no-start/' $@.tmp/debian/rules
endif
	cp -a debian/* $@.tmp/debian/
ifneq (,$(filter pkg.frr.lsbservice,$(DEB_BUILD_PROFILES)))
	cat debian/frr.lintian-overrides.lsbservice >>$@.tmp/debian/frr.lintian-overrides
endif
	mv $@.tmp $@

$(ORIG_SRC_TAR): $(BUILDDIR)
	tar czf $(ORIG_SRC_TAR) --exclude="$(BUILDDIR)/debian" $(BUILDDIR)

.PHONY: deb
deb: $(DEBS)
$(OTHER_DEBS) $(DBG_DEBS) $(MAIN_DEB) &: $(BUILDDIR)
	cd $(BUILDDIR); dpkg-buildpackage -b -uc -us
	lintian $(DEBS)

.PHONY: dsc
dsc:
	rm -rf $(BUILDDIR) $(ORIG_SRC_TAR) $(DSC)
	$(MAKE) $(DSC)
	lintian $(DSC)

$(DSC): $(BUILDDIR) $(ORIG_SRC_TAR)
	cd $(BUILDDIR); dpkg-buildpackage -S -uc -us --build-profiles="pkg.frr.nortrlib" -d

sbuild: $(DSC)
	sbuild $<

.PHONY: upload
upload: UPLOAD_DIST ?= $(DEB_DISTRIBUTION)
upload: $(DEBS)
	tar cf - $(DEBS)|ssh -X repoman@repo.proxmox.com -- upload --product pve --dist $(UPLOAD_DIST) --arch $(DEB_HOST_ARCH)

.PHONY: distclean
distclean: clean

.PHONY: clean
clean:
	rm -rf $(PACKAGE)-[0-9]*/
	rm -rf $(PACKAGE)*.tar* *.deb *.dsc *.changes *.dsc *.buildinfo *.build

.PHONY: dinstall
dinstall: deb
	dpkg -i $(DEBS)
