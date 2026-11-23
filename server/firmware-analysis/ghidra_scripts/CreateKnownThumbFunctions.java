// Optional preScript for controlled validation firmwares.
// Usage: -preScript CreateKnownThumbFunctions.java 0x08000008:add_values 0x0800000c:mul_values ...
//@category ScooterCheck

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.SourceType;

public class CreateKnownThumbFunctions extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args == null || args.length == 0) {
            printerr("CreateKnownThumbFunctions: need addr:name pairs");
            return;
        }
        int created = 0;
        for (String raw : args) {
            if (raw == null || raw.isEmpty()) {
                continue;
            }
            String[] parts = raw.split(":", 2);
            if (parts.length != 2) {
                printerr("skip bad arg: " + raw);
                continue;
            }
            long off;
            try {
                String hex = parts[0].trim().toLowerCase().replace("0x", "");
                off = Long.parseLong(hex, 16);
            } catch (Exception e) {
                printerr("bad addr: " + parts[0]);
                continue;
            }
            String name = parts[1].trim();
            Address addr = toAddr(off);
            // Thumb code: ensure disassembly at address.
            disassemble(addr);
            Function existing = getFunctionAt(addr);
            if (existing == null) {
                existing = createFunction(addr, name);
            }
            if (existing != null) {
                if (name.length() > 0 && !name.equals(existing.getName())) {
                    existing.setName(name, SourceType.USER_DEFINED);
                }
                created++;
            }
        }
        println("CreateKnownThumbFunctions: ensured " + created + " functions");
    }
}
