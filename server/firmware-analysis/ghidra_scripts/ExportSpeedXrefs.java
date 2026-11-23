// Find known Ninebot packed speed immediates in the listing and write JSON.
// Usage: -postScript ExportSpeedXrefs.java /absolute/path/out.speeds.json
//@category ScooterCheck

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.scalar.Scalar;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

public class ExportSpeedXrefs extends GhidraScript {

    private static final long[] KNOWN = {
        0x1400, 0x1600, 0x1700, 0x1900, 0x1E00, 0x2000,
        0x2300, 0x2319, 0x2800, 0x2D00, 0x3200, 0x6300
    };
    private static final int MAX_PER_PACKED = 8;

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args == null || args.length < 1) {
            printerr("ExportSpeedXrefs: need output JSON path");
            return;
        }
        File out = new File(args[0]);
        File parent = out.getParentFile();
        if (parent != null && !parent.exists()) {
            parent.mkdirs();
        }

        Set<Long> known = new HashSet<>();
        for (long k : KNOWN) {
            known.add(k);
        }

        FunctionManager fm = currentProgram.getFunctionManager();
        Map<Long, List<String>> byPacked = new HashMap<>();
        int hits = 0;

        InstructionIterator it = currentProgram.getListing().getInstructions(true);
        while (it.hasNext() && !monitor.isCancelled()) {
            Instruction insn = it.next();
            int n = insn.getNumOperands();
            for (int i = 0; i < n; i++) {
                Object[] objs = insn.getOpObjects(i);
                if (objs == null) {
                    continue;
                }
                for (Object o : objs) {
                    if (!(o instanceof Scalar)) {
                        continue;
                    }
                    long v = ((Scalar) o).getUnsignedValue() & 0xFFFFL;
                    if (!known.contains(v)) {
                        continue;
                    }
                    List<String> list = byPacked.computeIfAbsent(v, k -> new ArrayList<>());
                    if (list.size() >= MAX_PER_PACKED) {
                        continue;
                    }
                    Function fn = fm.getFunctionContaining(insn.getAddress());
                    String fnName = fn != null ? fn.getName() : "NO_FN";
                    list.add(String.format(
                        "{\"addr\":\"%s\",\"fn\":\"%s\",\"mnem\":\"%s\"}",
                        insn.getAddress().toString(),
                        escape(fnName),
                        escape(insn.getMnemonicString())
                    ));
                    hits++;
                }
            }
        }

        try (BufferedWriter w = new BufferedWriter(new FileWriter(out, StandardCharsets.UTF_8))) {
            w.write("{\"schemaVersion\":1,\"hits\":" + hits + ",\"packed\":{");
            boolean first = true;
            for (Map.Entry<Long, List<String>> e : byPacked.entrySet()) {
                if (!first) {
                    w.write(',');
                }
                first = false;
                w.write(String.format("\"0x%04X\":[", e.getKey()));
                List<String> list = e.getValue();
                for (int i = 0; i < list.size(); i++) {
                    if (i > 0) {
                        w.write(',');
                    }
                    w.write(list.get(i));
                }
                w.write(']');
            }
            w.write("}}\n");
        }
        println("ExportSpeedXrefs: " + hits + " hits -> " + out.getAbsolutePath());
    }

    private static String escape(String s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"");
    }
}
