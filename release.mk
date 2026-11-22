# Physical RIDI user builds: real private signing and secure framework defaults.
# Supply RIDI_RELEASE_KEY_DIR on the make command line to use another private store.
RIDI_RELEASE_KEY_DIR ?= $(HOME)/.local/share/ridi8-signing/keys
$(foreach key,releasekey platform shared media,\
    $(if $(wildcard $(RIDI_RELEASE_KEY_DIR)/$(key).pk8),,\
        $(error Missing private signing key $(key).pk8 in RIDI_RELEASE_KEY_DIR))\
    $(if $(wildcard $(RIDI_RELEASE_KEY_DIR)/$(key).x509.pem),,\
        $(error Missing signing certificate $(key).x509.pem in RIDI_RELEASE_KEY_DIR)))

PRODUCT_DEFAULT_DEV_CERTIFICATE := $(RIDI_RELEASE_KEY_DIR)/releasekey
PRODUCT_OTA_PUBLIC_KEYS := $(RIDI_RELEASE_KEY_DIR)/releasekey.x509.pem
