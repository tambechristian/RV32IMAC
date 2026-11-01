override compile_ar = $(file >$(build_dir)/$(notdir $(1)).rsp,$(2))$(CMD_PREFIX)mkdir -p `dirname $(1)`; \
	echo " AR        $(subst $(build_dir)/,,$(1))"; \
	$(AR) $(ARFLAGS) $(1) @$(build_dir)/$(notdir $(1)).rsp
