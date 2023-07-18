# input directory of compression files
IDIR=common
# intermediate directory of compressed files (when compressed)
INTER=inter
# output directory of compressed files (when decompressed)
ODIR=out

# Collect input .png objects
_PNG_OBJS=$(wildcard $(IDIR)/*.png)
COBJS=$(patsubst $(IDIR)/%.png,$(INTER)/%.fcf,$(_PNG_OBJS))

# Collect input .fcf objects
_FCF_OBJS=$(wildcard $(INTER)/*.fcf)
DOBJS=$(patsubst $(INTER)/%.fcf,$(ODIR)/%.png,$(_FCF_OBJS))

# build the program
finn.bin: finn/*.odin
	odin build finn/

compress: finn.bin $(COBJS)

decompress: finn.bin $(DOBJS)

$(INTER)/%.fcf: $(IDIR)/%.png
	./finn.bin -c $< $@
	@chmod +rw $@

$(ODIR)/%.png: $(INTER)/%.fcf
	./finn.bin -d $< $@
	@chmod +rw $@

clean:
	rm $(INTER)/* $(ODIR)/* finn.bin

.PHONY: clean
